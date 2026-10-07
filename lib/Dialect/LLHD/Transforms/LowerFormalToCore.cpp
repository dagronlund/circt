//===- LowerFormalToCore.cpp - Strict LLHD formal lowering
//------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "FormalUtils.h"
#include "circt/Dialect/Comb/CombOps.h"
#include "circt/Dialect/HW/HWOps.h"
#include "circt/Dialect/LLHD/LLHDPasses.h"
#include "circt/Dialect/Seq/SeqOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/Passes.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/ADT/SmallBitVector.h"

namespace circt::llhd {
#define GEN_PASS_DEF_LOWERLLHDFORMALTOCOREPASS
#include "circt/Dialect/LLHD/LLHDPasses.h.inc"
} // namespace circt::llhd

using namespace mlir;
using namespace circt;
using namespace circt::llhd;

namespace {
/// Recognize only the frontend's property-only trampoline/self-loop wrapper.
/// Its loop describes a concurrent property, not repeated procedural execution.
LogicalResult unwrapPropertyProcess(ProcessOp process) {
  auto &region = process.getBody();
  if (process.getNumResults() || region.getBlocks().size() != 2)
    return failure();
  auto &entry = region.front();
  auto &body = region.back();
  auto entryBr = dyn_cast<cf::BranchOp>(entry.getTerminator());
  auto backBr = dyn_cast<cf::BranchOp>(body.getTerminator());
  if (!entry.without_terminator().empty() || !entryBr || !backBr ||
      entryBr.getDest() != &body || backBr.getDest() != &body ||
      body.getNumArguments())
    return failure();
  bool hasCheck = false;
  for (auto &op : body.without_terminator()) {
    if (isClockedFormalCheck(&op)) {
      hasCheck = true;
      continue;
    }
    if (!isMemoryEffectFree(&op) || op.getNumRegions() ||
        !(op.getName().getDialectNamespace() == "comb" ||
          op.getName().getDialectNamespace() == "hw" ||
          op.getName().getDialectNamespace() == "ltl"))
      return failure();
  }
  if (!hasCheck)
    return failure();
  while (!body.without_terminator().empty())
    body.front().moveBefore(process);
  process.erase();
  return success();
}

LogicalResult preflight(ModuleOp module, bool normalized = false) {
  auto result = module.walk([&](Operation *op) -> WalkResult {
    auto dialect = op->getName().getDialectNamespace();
    if (dialect != "builtin" && dialect != "hw" && dialect != "seq" &&
        dialect != "comb" && dialect != "llhd" && dialect != "ltl" &&
        dialect != "cf" && dialect != "verif" && dialect != "arith" &&
        dialect != "ub") {
      op->emitError(
          "unsupported operation in strict synchronous formal lowering");
      return WalkResult::interrupt();
    }

    if (isFormalCheck(op) &&
        !op->getOperand(0).getType().isSignlessInteger(1)) {
      if (auto parent = op->getParentOfType<CombinationalOp>();
          parent && !llvm::hasSingleElement(parent.getBody())) {
        op->emitError(
            "guarded temporal checks require separate attempt-start "
            "and disable semantics; combinational CFG checks must be Boolean");
        return WalkResult::interrupt();
      }
    }

    if (dialect == "verif" && !isFormalCheck(op)) {
      op->emitError(
          "unsupported verification effect in strict formal lowering");
      return WalkResult::interrupt();
    }
    if (auto drive = dyn_cast<DriveOp>(op)) {
      TimeAttr time;
      if (!matchPattern(drive.getTime(), m_Constant(&time)) ||
          time.getTime() != 0 || time.getDelta() > 1 || time.getEpsilon() > 1) {
        drive.emitError(
            "real time delays are unsupported in synchronous formal lowering");
        return WalkResult::interrupt();
      }
    }
    if (auto signal = dyn_cast<SignalOp>(op)) {
      DenseSet<Operation *> drivers;
      for (auto *user : signal->getUsers()) {
        if (isa<DriveOp>(user)) {
          auto process = user->getParentOfType<ProcessOp>();
          drivers.insert(process ? process.getOperation() : user);
        } else if (!isa<ProbeOp>(user)) {
          user->emitError(
              "unsupported signal access in strict formal lowering");
          return WalkResult::interrupt();
        }
      }
      if (drivers.size() != 1) {
        signal.emitError("signal must have exactly one resolved driver");
        return WalkResult::interrupt();
      }
    }
    if (auto process = dyn_cast<ProcessOp>(op)) {
      for (auto &block : process.getBody())
        for (auto &nested : block)
          if (!isMemoryEffectFree(&nested) && !isFormalCheck(&nested) &&
              !isa<WaitOp, HaltOp>(nested) &&
              (normalized || !isa<DriveOp, ProbeOp>(nested))) {
            nested.emitError("unsupported effect in formal process")
                << " at " << process.getLoc();
            return WalkResult::interrupt();
          }
    }
    return WalkResult::advance();
  });
  return failure(result.wasInterrupted());
}

LogicalResult verifyCore(ModuleOp module) {
  auto result = module.walk([&](Operation *op) -> WalkResult {
    StringRef dialect = op->getName().getDialectNamespace();
    bool badType = false;
    auto checkType = [&](Type type) {
      type.walk([&](Type nested) {
        auto dialect = nested.getDialect().getNamespace();
        badType |= dialect != "builtin" && dialect != "hw" && dialect != "seq";
        badType |= isa<FloatType, ComplexType>(nested);
      });
    };
    for (Type type : op->getOperandTypes())
      checkType(type);
    for (Type type : op->getResultTypes())
      checkType(type);
    for (auto &region : op->getRegions())
      for (auto &block : region)
        for (auto arg : block.getArguments())
          checkType(arg.getType());
    if (badType) {
      op->emitError("unsupported type remains in formal hardware");
      return WalkResult::interrupt();
    }

    if (isa<ModuleOp>(op) || dialect == "hw" || dialect == "seq" ||
        dialect == "comb")
      return WalkResult::advance();
    if (isFormalCheck(op)) {
      if (!op->getOperand(0).getType().isSignlessInteger(1)) {
        op->emitError("formal property must be Boolean");
        return WalkResult::interrupt();
      }
      if (isClockedFormalCheck(op) &&
          cast<verif::ClockEdgeAttr>(op->getAttr("edge")).getValue() ==
              verif::ClockEdge::Both) {
        op->emitError("both-edge properties are unsupported");
        return WalkResult::interrupt();
      }
      return WalkResult::advance();
    }
    op->emitError(
        "operation remains after strict formal lowering; unsupported ")
        << op->getName();
    return WalkResult::interrupt();
  });
  if (result.wasInterrupted())
    return failure();
  // Summarize dependencies per output port across module boundaries. An
  // instance is not wholly combinational merely because it has input operands:
  // feedback through a child register must cut the path just like a local reg.
  using Dependencies = SmallVector<llvm::SmallBitVector>;
  DenseMap<Operation *, Dependencies> summaries;
  DenseSet<Operation *> visitingModules;
  std::function<LogicalResult(hw::HWModuleOp)> summarize;
  summarize = [&](hw::HWModuleOp moduleOp) -> LogicalResult {
    if (summaries.count(moduleOp))
      return success();
    if (!visitingModules.insert(moduleOp).second)
      return moduleOp.emitError(
          "recursive module hierarchy in formal hardware");
    auto done = llvm::scope_exit([&] { visitingModules.erase(moduleOp); });
    DenseMap<Value, llvm::SmallBitVector> cache;
    DenseSet<Value> visiting;
    unsigned numInputs = moduleOp.getNumInputPorts();
    std::function<LogicalResult(Value)> visit;
    visit = [&](Value value) -> LogicalResult {
      if (cache.count(value))
        return success();
      if (!visiting.insert(value).second)
        return value.getDefiningOp()->emitError(
            "combinational dependency cycle in formal hardware");
      auto done = llvm::scope_exit([&] { visiting.erase(value); });
      llvm::SmallBitVector deps(numInputs);
      if (auto arg = dyn_cast<BlockArgument>(value)) {
        if (arg.getOwner() == moduleOp.getBodyBlock())
          deps.set(arg.getArgNumber());
      } else {
        auto *op = value.getDefiningOp();
        SmallVector<Value> operands;
        if (auto instance = dyn_cast<hw::InstanceOp>(op)) {
          auto child = SymbolTable::lookupNearestSymbolFrom<hw::HWModuleOp>(
              instance, instance.getModuleNameAttr());
          if (child) {
            if (failed(summarize(child)))
              return failure();
            auto &childDeps =
                summaries[child.getOperation()]
                         [cast<OpResult>(value).getResultNumber()];
            for (int index : childDeps.set_bits())
              operands.push_back(instance->getOperand(index));
          } else {
            operands.append(op->getOperands().begin(), op->getOperands().end());
          }
        } else if (!isa<seq::FirRegOp, seq::CompRegOp, seq::ShiftRegOp>(op)) {
          operands.append(op->getOperands().begin(), op->getOperands().end());
        }
        for (auto operand : operands) {
          if (failed(visit(operand)))
            return failure();
          deps |= cache.lookup(operand);
        }
      }
      cache[value] = std::move(deps);
      return success();
    };
    // Visit next-state logic and checks as well as visible module outputs.
    for (auto &op : *moduleOp.getBodyBlock())
      for (auto operand : op.getOperands())
        if (failed(visit(operand)))
          return failure();
    Dependencies outputs;
    for (auto value : moduleOp.getBodyBlock()->getTerminator()->getOperands()) {
      if (failed(visit(value)))
        return failure();
      outputs.push_back(cache.lookup(value));
    }
    summaries[moduleOp] = std::move(outputs);
    return success();
  };
  for (auto moduleOp : module.getOps<hw::HWModuleOp>())
    if (failed(summarize(moduleOp)))
      return failure();
  return success();
}

struct LowerLLHDFormalToCorePass
    : llhd::impl::LowerLLHDFormalToCorePassBase<LowerLLHDFormalToCorePass> {
  using Base::Base;

  void runOnOperation() override {
    // Work transactionally. Failed recognition must not leave half-extracted
    // checks or state in the user's design.
    OwningOpRef<ModuleOp> work(cast<ModuleOp>(getOperation()->clone()));
    getOperation().getBody()->push_back(work->getOperation());
    if (failed(lower(*work))) {
      signalPassFailure();
      return;
    }
    work->getOperation()->remove();
    getOperation().getBodyRegion().takeBody(work->getBodyRegion());
  }

  LogicalResult cleanup(ModuleOp module) {
    PassManager pm(&getContext());
    pm.addPass(createCanonicalizerPass());
    pm.addPass(createCSEPass());
    return runPipeline(pm, module);
  }

  LogicalResult lower(ModuleOp module) {
    if (failed(preflight(module)))
      return failure();
    auto temporal = module.walk([&](Operation *op) -> WalkResult {
      if (isFormalCheck(op) &&
          !op->getOperand(0).getType().isSignlessInteger(1)) {
        op->emitError("temporal verification is not yet supported");
        return WalkResult::interrupt();
      }
      return WalkResult::advance();
    });
    if (temporal.wasInterrupted())
      return failure();
    PassManager storage(&getContext());
    storage.addNestedPass<hw::HWModuleOp>(createMem2RegPass());
    if (failed(runPipeline(storage, module)))
      return failure();
    hoistFormalSignals(module);
    if (failed(preflight(module, true)))
      return failure();
    SmallVector<ProcessOp> processes;
    module.walk([&](ProcessOp op) { processes.push_back(op); });
    for (auto process : processes) {
      if (succeeded(unwrapPropertyProcess(process)))
        continue;
      if (failed(deseqFormal(process)))
        return failure();
    }
    PassManager processesPM(&getContext());
    processesPM.addNestedPass<hw::HWModuleOp>(createLowerProcessesPass());
    if (failed(runPipeline(processesPM, module)))
      return failure();
    auto remaining = module.walk([&](ProcessOp op) -> WalkResult {
      op.emitError(
          "unsupported formal process: expected a recognizable single-edge "
          "clocked process or a property-only wrapper; multiple clocks, "
          "event-region dependencies and general loops are unsupported");
      return WalkResult::interrupt();
    });
    if (remaining.wasInterrupted())
      return failure();
    // Remove unreachable edge-specialization blocks before CFG predication.
    if (failed(cleanup(module)))
      return failure();
    SmallVector<CombinationalOp> combinational;
    module.walk([&](CombinationalOp op) { combinational.push_back(op); });
    for (auto op : combinational) {
      removeFormalControlFlow(op);
      if (!llvm::hasSingleElement(op.getBody()))
        return op.emitError("unsupported control-flow cycle or effect in "
                            "formal combinational process");
      auto &block = op.getBody().front();
      auto yield = dyn_cast<YieldOp>(block.getTerminator());
      if (!yield)
        return op.emitError(
            "formal combinational process must end in llhd.yield");
      op.replaceAllUsesWith(yield.getOperands());
      while (!block.without_terminator().empty())
        block.front().moveBefore(op);
      op.erase();
    }
    PassManager signals(&getContext());
    signals.addNestedPass<hw::HWModuleOp>(createSig2Reg());
    if (failed(runPipeline(signals, module)))
      return failure();
    if (failed(cleanup(module)))
      return failure();
    // Region simplification may materialize integer constants with Arith.
    // Normalize those implementation artifacts before enforcing dialect purity.
    SmallVector<arith::ConstantOp> constants;
    module.walk([&](arith::ConstantOp op) { constants.push_back(op); });
    for (auto op : constants) {
      auto value = dyn_cast<IntegerAttr>(op.getValue());
      if (!value)
        return op.emitError(
            "only integer constants are supported in formal hardware");
      OpBuilder builder(op);
      auto core = hw::ConstantOp::create(builder, op.getLoc(), value);
      op.replaceAllUsesWith(core.getResult());
      op.erase();
    }
    return verifyCore(module);
  }
};
} // namespace
