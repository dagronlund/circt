//===- AbstractRandom.cpp - Random call abstraction -----------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "circt/Dialect/Comb/CombOps.h"
#include "circt/Dialect/HW/HWOps.h"
#include "circt/Dialect/LLHD/LLHDOps.h"
#include "circt/Dialect/Verif/VerifOps.h"
#include "circt/Dialect/Verif/VerifPasses.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;
using namespace circt;

namespace circt::verif {
#define GEN_PASS_DEF_ABSTRACTRANDOMPASS
#include "circt/Dialect/Verif/Passes.h.inc"
} // namespace circt::verif

namespace {
/// Remove only dead producers of abstraction artifacts. In particular, do not
/// prune block arguments: unused HW module ports remain part of the interface.
struct ArtifactPruner {
  llvm::SmallSetVector<Operation *, 16> pending;

  void eraseLaterIfUnused(Operation *op) { pending.insert(op); }

  void eraseNow(Operation *op) {
    for (auto operand : op->getOperands())
      if (auto *producer = operand.getDefiningOp())
        pending.insert(producer);
    pending.remove(op);
    op->erase();
  }

  void eraseNow() {
    while (!pending.empty()) {
      auto *op = pending.pop_back_val();
      if (isOpTriviallyDead(op))
        eraseNow(op);
    }
  }
};

struct RandomCall {
  func::CallOp call;
  hw::HWModuleOp module;
  func::FuncOp function;
  LLVM::AllocaOp seedStorage;
  LLVM::StoreOp seedStore;
  LLVM::LoadOp seedLoad;

  LogicalResult validate(SymbolTableCollection &symbolTables);
  void rewrite(bool assumeRanges, ArtifactPruner &pruner);
};

struct AbstractRandomPass
    : verif::impl::AbstractRandomPassBase<AbstractRandomPass> {
  using Base::Base;
  void runOnOperation() override;
};
} // namespace

LogicalResult RandomCall::validate(SymbolTableCollection &symbolTables) {
  module = call->getParentOfType<hw::HWModuleOp>();
  // The normal Verilog-to-HW pipeline has already inlined user functions and
  // converted SCF to CFGs. Do not overlook repeated execution in other regions.
  if (!module ||
      !isa<hw::HWModuleOp, llhd::ProcessOp, llhd::CombinationalOp,
           llhd::FinalOp>(call->getParentOp()) ||
      (call->getParentOp() != module.getOperation() &&
       call->getParentOp()->getParentOp() != module.getOperation()))
    return call.emitError("random call must be directly nested in an HW module "
                          "or LLHD procedural region; inline functions and "
                          "lower structured control flow first");

  function = symbolTables.lookupNearestSymbolFrom<func::FuncOp>(
      call, call.getCalleeAttr());
  if (!function || !function.isDeclaration() || call.getNumOperands() != 3 ||
      call.getNumResults() != 1 ||
      !call.getResult(0).getType().isSignlessInteger(32) ||
      !call.getOperand(0).getType().isSignlessInteger(32) ||
      !call.getOperand(1).getType().isSignlessInteger(32) ||
      call.getOperand(2).getType() !=
          LLVM::LLVMPointerType::get(call.getContext()))
    return call.emitError(
        "expected an external __circt_urandom_range call with "
        "type (i32, i32, !llvm.ptr) -> i32");

  // A module-level symbolic source can change between sampling steps, but
  // cannot stand for several independent draws within one activation. Allow
  // recurrence only across an LLHD suspension. Statically unrolled calls are
  // already separate operations and therefore get separate sources.
  SmallVector<Block *> worklist{call->getBlock()};
  DenseSet<Block *> visited;
  while (!worklist.empty()) {
    auto *block = worklist.pop_back_val();
    if (!visited.insert(block).second ||
        llvm::any_of(*block, [](Operation &op) {
          return isa<llhd::WaitOp, llhd::HaltOp>(op);
        }))
      continue;
    for (auto *successor : block->getSuccessors()) {
      if (successor == call->getBlock())
        return call.emitError("random call may execute repeatedly without an "
                              "LLHD suspension; unroll the loop first");
      worklist.push_back(successor);
    }
  }

  Value seed = call.getOperand(2);
  if (seed.getDefiningOp<LLVM::ZeroOp>())
    return success();

  // Only discard the frontend's dedicated seed temporary. Never discard
  // arbitrary memory operations or another call that shares the pointer.
  seedStorage = seed.getDefiningOp<LLVM::AllocaOp>();
  if (!seedStorage || !seedStorage.getElemType().isSignlessInteger(32) ||
      !matchPattern(seedStorage.getArraySize(), m_One()) ||
      !llvm::all_of(
          seed.getUsers(),
          [&](Operation *user) {
            if (user == call.getOperation())
              return true;
            if (auto store = dyn_cast<LLVM::StoreOp>(user);
                store && !seedStore) {
              seedStore = store;
              return store.getAddr() == seed && !store.getVolatile_() &&
                     store.getOrdering() == LLVM::AtomicOrdering::not_atomic;
            }
            if (auto load = dyn_cast<LLVM::LoadOp>(user); load && !seedLoad) {
              seedLoad = load;
              return !load.getVolatile_() &&
                     load.getOrdering() == LLVM::AtomicOrdering::not_atomic;
            }
            return false;
          }) ||
      !seedStore || !seedStore.getValue().getType().isSignlessInteger(32) ||
      seedStore->getBlock() != call->getBlock() ||
      !seedStore->isBeforeInBlock(call) ||
      (seedLoad && (!seedLoad.getType().isSignlessInteger(32) ||
                    seedLoad->getBlock() != call->getBlock() ||
                    !call->isBeforeInBlock(seedLoad))))
    return call.emitError("unsupported random seed storage; expected a "
                          "dedicated i32 temporary stored before the call and "
                          "optionally loaded afterward");
  return success();
}

void RandomCall::rewrite(bool assumeRanges, ArtifactPruner &pruner) {
  if (seedLoad) {
    // Drop a writeback still expressed as a drive to the original seed signal.
    // If signal promotion already put it into process results, forwarding the
    // pre-call value instead removes the seed mutation without changing CFGs.
    if (auto probe = seedStore.getValue().getDefiningOp<llhd::ProbeOp>())
      for (auto *user : llvm::make_early_inc_range(seedLoad->getUsers()))
        if (auto drive = dyn_cast<llhd::DriveOp>(user);
            drive && drive.getSignal() == probe.getSignal() &&
            drive.getValue() == seedLoad.getResult())
          pruner.eraseNow(drive);
    seedLoad.replaceAllUsesWith(seedStore.getValue());
    pruner.eraseNow(seedLoad);
  }
  if (seedStore)
    pruner.eraseNow(seedStore);

  auto loc = call.getLoc();
  OpBuilder builder(module.getBodyBlock(), module.getBodyBlock()->begin());
  auto value = verif::SymbolicValueOp::create(
      builder, loc, builder.getI32Type(), StringAttr{});
  Value min = call.getOperand(0), max = call.getOperand(1);
  IntegerAttr minConstant, maxConstant;
  bool fullWidth =
      matchPattern(min, m_Constant(&minConstant)) &&
      matchPattern(max, m_Constant(&maxConstant)) &&
      ((minConstant.getValue().isZero() &&
        maxConstant.getValue().isAllOnes()) ||
       (maxConstant.getValue().isZero() && minConstant.getValue().isAllOnes()));
  if (assumeRanges && !fullWidth) {
    // Keep the assumption at the call site: the enclosing branches, waits and
    // processes retain its execution guard and sampling context.
    builder.setInsertionPoint(call);
    Value ordered = builder.createOrFold<comb::ICmpOp>(
        loc, comb::ICmpPredicate::ule, min, max, /*twoState=*/true);
    Value low = builder.createOrFold<comb::MuxOp>(loc, ordered, min, max,
                                                  /*twoState=*/true);
    Value high = builder.createOrFold<comb::MuxOp>(loc, ordered, max, min,
                                                   /*twoState=*/true);
    Value aboveLow = builder.createOrFold<comb::ICmpOp>(
        loc, comb::ICmpPredicate::ule, low, value, /*twoState=*/true);
    Value belowHigh = builder.createOrFold<comb::ICmpOp>(
        loc, comb::ICmpPredicate::ule, value, high, /*twoState=*/true);
    Value inRange = builder.createOrFold<comb::AndOp>(loc, aboveLow, belowHigh,
                                                      /*twoState=*/true);
    verif::AssumeOp::create(builder, loc, inRange, Value{}, StringAttr{});
  }
  call.getResult(0).replaceAllUsesWith(value.getResult());
  pruner.eraseNow(call);
  if (seedStorage)
    pruner.eraseNow(seedStorage);
  pruner.eraseLaterIfUnused(value.getOperation());
}

void AbstractRandomPass::runOnOperation() {
  SmallVector<RandomCall> calls;
  getOperation().walk([&](func::CallOp call) {
    if (call.getCallee() == "__circt_urandom_range")
      calls.push_back({call, {}, {}, {}, {}, {}});
  });

  // Validate every candidate before modifying anything, including when an
  // unsupported call follows a supported one in another module.
  SymbolTableCollection symbolTables;
  for (auto &call : calls)
    if (failed(call.validate(symbolTables)))
      return signalPassFailure();

  ArtifactPruner pruner;
  llvm::SmallSetVector<Operation *, 4> functions;
  for (auto &call : calls) {
    functions.insert(call.function);
    call.rewrite(assumeRanges, pruner);
  }
  pruner.eraseNow();
  for (auto *function : functions)
    if (SymbolTable::symbolKnownUseEmpty(function, getOperation()))
      function->erase();
}
