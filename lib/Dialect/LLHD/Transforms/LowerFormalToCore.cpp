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
#include "circt/Dialect/LTL/LTLOps.h"
#include "circt/Dialect/Seq/SeqOps.h"
#include "circt/Dialect/Sim/SimOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/Passes.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/ADT/SmallBitVector.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/Support/MathExtras.h"
#include <limits>

namespace circt::llhd {
#define GEN_PASS_DEF_LOWERLLHDFORMALTOCOREPASS
#include "circt/Dialect/LLHD/LLHDPasses.h.inc"
} // namespace circt::llhd

using namespace mlir;
using namespace circt;
using namespace circt::llhd;

namespace {
/// A fixed sequence is a list of predicates indexed by sample number. Empty
/// cycles are true. Concatenation overlaps endpoints; repetition advances one
/// sample between consecutive copies. All lengths are checked before expansion.
using Timeline = SmallVector<Value>;

struct MonitorBuilder {
  MonitorBuilder(Operation *check, unsigned limit)
      : check(check), builder(check), loc(check->getLoc()), limit(limit) {
    if (isClockedFormalCheck(check)) {
      clock = check->getOperand(1);
      edge = cast<verif::ClockEdgeAttr>(check->getAttr("edge")).getValue();
      if (check->getNumOperands() == 3)
        enable = check->getOperand(2);
    }
  }

  Operation *check;
  OpBuilder builder;
  Location loc;
  unsigned limit;
  Value clock, enable, seqClock, disable;
  DenseSet<Value> sequencesInProgress, booleansInProgress;
  verif::ClockEdge edge = verif::ClockEdge::Pos;

  Value konst(bool value) {
    return hw::ConstantOp::create(builder, loc, builder.getI1Type(), value);
  }
  Value andWith(Value a, Value b) {
    return builder.createOrFold<comb::AndOp>(loc, a, b);
  }
  Value notOf(Value a) { return comb::createOrFoldNot(builder, loc, a); }
  Value orWith(Value a, Value b) {
    return builder.createOrFold<comb::OrOp>(loc, a, b);
  }
  LogicalResult error(Value value, StringRef message) {
    if (auto *op = value.getDefiningOp())
      op->emitError(message);
    else
      check->emitError(message);
    return failure();
  }
  bool withinLimit(uint64_t length) {
    if (length <= limit)
      return true;
    check->emitError("temporal monitor exceeds max-monitor-depth");
    return false;
  }
  Value reg(Value input) {
    if (!seqClock) {
      seqClock = builder.createOrFold<seq::ToClockOp>(loc, clock);
      if (edge == verif::ClockEdge::Neg)
        seqClock = seq::ClockInverterOp::create(builder, loc, seqClock);
    }
    if (enable && !disable)
      disable = notOf(enable);
    // Asynchronous reset cancels every in-flight attempt, including a disable
    // pulse entirely between sampling edges. This is not a clock enable.
    return seq::FirRegOp::create(
        builder, loc, input, seqClock, builder.getStringAttr(""),
        hw::InnerSymAttr{}, builder.getIntegerAttr(builder.getI1Type(), 0),
        disable, disable ? konst(false) : Value{}, bool(disable));
  }

  LogicalResult sequence(Value value, Timeline &result) {
    if (value.getType().isSignlessInteger(1)) {
      result.push_back(value);
      return success();
    }
    if (!sequencesInProgress.insert(value).second)
      return error(value, "cyclic temporal expression is unsupported");
    auto done = llvm::scope_exit([&] { sequencesInProgress.erase(value); });
    if (auto op = value.getDefiningOp<ltl::DelayOp>()) {
      if (!op.getLength() || *op.getLength() != 0)
        return error(value,
                     "only fixed temporal delays are supported; unbounded "
                     "or variable temporal sequence is unsupported");
      Timeline input;
      if (failed(sequence(op.getInput(), input)))
        return failure();
      auto delay = op.getDelay();
      if (delay > limit || input.size() > limit - delay) {
        check->emitError("temporal monitor exceeds max-monitor-depth");
        return failure();
      }
      result.append(delay, konst(true));
      result.append(input);
      return success();
    }
    if (auto op = value.getDefiningOp<ltl::ConcatOp>()) {
      for (auto input : op.getInputs()) {
        Timeline next;
        if (failed(sequence(input, next)))
          return failure();
        if (result.empty()) {
          result = std::move(next);
          continue;
        }
        if (next.empty())
          continue;
        if (!withinLimit(result.size() + next.size() - 1))
          return failure();
        result.back() = andWith(result.back(), next.front());
        result.append(next.begin() + 1, next.end());
      }
      return success();
    }
    if (auto op = value.getDefiningOp<ltl::RepeatOp>()) {
      if (!op.getMore() || *op.getMore() != 0)
        return error(value,
                     "only fixed finite consecutive repetition is supported");
      Timeline input;
      if (failed(sequence(op.getInput(), input)))
        return failure();
      auto count = op.getBase();
      if (count < 0 ||
          (input.size() && uint64_t(count) > limit / input.size())) {
        check->emitError("temporal monitor exceeds max-monitor-depth");
        return failure();
      }
      for (uint64_t i = 0; i < count; ++i)
        result.append(input);
      return success();
    }
    if (auto op = value.getDefiningOp<ltl::ClockOp>()) {
      if (op.getClock() != clock || unsigned(op.getEdge()) != unsigned(edge))
        return error(value, "property observes multiple unrelated clocks");
      return sequence(op.getInput(), result);
    }
    if (auto op = value.getDefiningOp<ltl::ClockedAtomOp>()) {
      if (op.getClock() != clock || unsigned(op.getEdge()) != unsigned(edge))
        return error(value, "property observes multiple unrelated clocks");
      result.push_back(op.getInput());
      return success();
    }
    // Boolean LTL expressions are handled without a monitor.
    auto boolean = booleanExpr(value);
    if (!boolean)
      return failure();
    result.push_back(boolean);
    return success();
  }

  Value booleanExpr(Value value) {
    if (value.getType().isSignlessInteger(1))
      return value;
    if (!booleansInProgress.insert(value).second) {
      (void)error(value, "cyclic temporal expression is unsupported");
      return {};
    }
    auto done = llvm::scope_exit([&] { booleansInProgress.erase(value); });
    if (auto op = value.getDefiningOp<ltl::BooleanConstantOp>())
      return konst(op.getValue());
    if (auto op = value.getDefiningOp<ltl::NotOp>()) {
      auto input = booleanExpr(op.getInput());
      return input ? notOf(input) : Value{};
    }
    auto *op = value.getDefiningOp();
    if (op && isa<ltl::AndOp, ltl::OrOp, ltl::IntersectOp>(op)) {
      bool isOr = isa<ltl::OrOp>(op);
      Value result = konst(!isOr);
      for (auto operand : op->getOperands()) {
        auto next = booleanExpr(operand);
        if (!next)
          return {};
        result = isOr ? orWith(result, next) : andWith(result, next);
      }
      return result;
    }
    if (auto op = value.getDefiningOp<ltl::ImplicationOp>()) {
      auto a = booleanExpr(op.getAntecedent());
      auto b = booleanExpr(op.getConsequent());
      return a && b ? orWith(notOf(a), b) : Value{};
    }
    (void)error(value, "unsupported temporal operator in Boolean property");
    return {};
  }

  /// A pipeline tracks all overlapping attempts, one bit per sample position.
  /// No attempt exists before startup. The enable starts attempts and async
  /// cancellation clears intermediate stages.
  Value match(ArrayRef<Value> timeline, Value start) {
    Value active = start;
    for (auto [i, predicate] : llvm::enumerate(timeline)) {
      active = andWith(active, predicate);
      if (i + 1 != timeline.size())
        active = reg(active);
    }
    return active;
  }
  void emit(Value property, Value guard) {
    OperationState state(loc, check->getName());
    state.addOperands(property);
    if (clock)
      state.addOperands(clock);
    if (guard)
      state.addOperands(guard);
    state.addAttributes(check->getAttrs());
    builder.create(state);
  }

  LogicalResult lower() {
    Value property = check->getOperand(0);
    if (property.getType().isSignlessInteger(1))
      return success();
    // Explicit clocks can turn an unclocked property into a clocked check.
    if (!clock) {
      if (auto op = property.getDefiningOp<ltl::ClockOp>()) {
        clock = op.getClock();
        edge = verif::ClockEdge(unsigned(op.getEdge()));
        property = op.getInput();
      } else if (auto op = property.getDefiningOp<ltl::ClockedAtomOp>()) {
        clock = op.getClock();
        edge = verif::ClockEdge(unsigned(op.getEdge()));
        property = op.getInput();
      }
      if (clock) {
        OperationState state(
            loc, "verif.clocked_" +
                     check->getName().getStringRef().drop_front(6).str());
        state.addOperands({property, clock});
        if (check->getNumOperands() == 2) {
          enable = check->getOperand(1);
          state.addOperands(enable);
        }
        state.addAttributes(check->getAttrs());
        state.addAttribute(
            "edge", verif::ClockEdgeAttr::get(builder.getContext(), edge));
        auto *replacement = builder.create(state);
        check->erase();
        check = replacement;
        builder.setInsertionPoint(check);
      }
    }
    if (edge == verif::ClockEdge::Both)
      return check->emitError("both-edge properties are unsupported");
    bool cover = isa<verif::CoverOp, verif::ClockedCoverOp>(check);
    auto implication = property.getDefiningOp<ltl::ImplicationOp>();
    Timeline antecedent, consequent;
    if (implication) {
      if (failed(sequence(implication.getAntecedent(), antecedent)) ||
          failed(sequence(implication.getConsequent(), consequent)))
        return failure();
    } else if (failed(sequence(property, consequent))) {
      return failure();
    }
    if (!clock && (antecedent.size() > 1 || consequent.size() > 1))
      return check->emitError("temporal property has no sampling clock");
    Value start = enable ? enable : konst(true);
    if (implication)
      start = match(antecedent, start);
    if (cover) {
      // Cover witnesses are completed non-vacuous matches, never disabled or
      // merely pending attempts. In particular !antecedent is not a cover hit.
      emit(match(consequent, start), enable);
    } else {
      // Each attempted sequence requires each Boolean sample. Outstanding
      // obligations remain in registers when a finite checking bound ends.
      Value pending = start;
      for (auto [i, predicate] : llvm::enumerate(consequent)) {
        emit(predicate, pending);
        if (i + 1 != consequent.size())
          pending = reg(andWith(pending, predicate));
      }
    }
    check->erase();
    return success();
  }
};

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

/// After static loop unrolling and signal promotion, a fully initialized ROM
/// is a one-shot process yielding constant data. Inline that data without
/// accepting startup expressions that sample inputs or unwritten signal lanes.
LogicalResult unwrapConstantInitialProcess(ProcessOp process) {
  if (!isa<hw::HWModuleOp>(process->getParentOp()) ||
      !process.getBody().hasOneBlock())
    return failure();
  auto &block = process.getBody().front();
  auto halt = dyn_cast<HaltOp>(block.getTerminator());
  if (!halt)
    return failure();

  DenseMap<Value, bool> constants;
  std::function<bool(Value, unsigned)> isConstant = [&](Value value,
                                                        unsigned depth) {
    auto [it, inserted] = constants.try_emplace(value, false);
    if (!inserted)
      return it->second;
    auto *op = value.getDefiningOp();
    if (!op || depth == 64 || !isMemoryEffectFree(op) || op->getNumRegions())
      return false;
    auto dialect = op->getName().getDialectNamespace();
    // Hardware instances and registers can have constant inputs without
    // constant outputs. Only admit literal data and aggregate constructors
    // from HW, plus pure arithmetic on such data.
    if (!isa<hw::ConstantOp, hw::AggregateConstantOp, hw::ArrayCreateOp,
             hw::StructCreateOp, hw::UnionCreateOp, hw::BitcastOp>(op) &&
        dialect != "comb" && dialect != "arith")
      return false;
    return constants[value] = llvm::all_of(op->getOperands(), [&](Value v) {
             return isConstant(v, depth + 1);
           });
  };
  for (auto &op : block.without_terminator())
    if (!op.getNumResults() || !llvm::all_of(op.getResults(), [&](Value value) {
          return isConstant(value, 0);
        }))
      return failure();
  if (!llvm::all_of(halt.getYieldOperands(),
                    [&](Value value) { return isConstant(value, 0); }))
    return failure();

  process.replaceAllUsesWith(halt.getYieldOperands());
  while (!block.without_terminator().empty())
    block.front().moveBefore(process);
  process.erase();
  return success();
}

/// Rematerialize a startup expression using the declaration value and module
/// inputs. Other state probes are deliberately excluded: independent initial
/// processes have no defined execution order.
struct InitialValueEvaluator {
  InitialValueEvaluator(SignalOp signal, IntegerAttr initial,
                        OpBuilder &builder)
      : signal(signal), initial(initial), builder(builder) {}

  Value evaluate(Value value, unsigned depth = 0) {
    if (auto it = cache.find(value); it != cache.end())
      return it->second;
    if (depth == 64 || !active.insert(value).second)
      return {};
    auto done = llvm::scope_exit([&] { active.erase(value); });
    Value result;
    if (auto arg = dyn_cast<BlockArgument>(value)) {
      if (arg.getOwner() == signal->getBlock())
        result = arg;
    } else if (auto probe = value.getDefiningOp<ProbeOp>()) {
      if (probe.getSignal() == signal.getResult()) {
        result = hw::ConstantOp::create(builder, probe.getLoc(), initial);
      } else if (auto input = probe.getSignal().getDefiningOp<SignalOp>();
                 input && input->getBlock() == signal->getBlock() &&
                 !input->hasAttr("llhd.explicit_init")) {
        DriveOp driver;
        for (auto *user : input->getUsers()) {
          if (isa<ProbeOp>(user))
            continue;
          auto drive = dyn_cast<DriveOp>(user);
          if (!drive || driver)
            return {};
          driver = drive;
        }
        TimeAttr time;
        auto arg = driver ? dyn_cast<BlockArgument>(driver.getValue())
                          : BlockArgument{};
        if (arg && arg.getOwner() == signal->getBlock() &&
            driver->getBlock() == signal->getBlock() && !driver.getEnable() &&
            matchPattern(driver.getTime(), m_Constant(&time)) &&
            time.getTime() == 0 && time.getDelta() == 0 &&
            time.getEpsilon() == 1)
          result = arg;
      }
    } else if (auto *op = value.getDefiningOp();
               op && isMemoryEffectFree(op) && !op->getNumRegions() &&
               op->getNumResults() == 1 && isa<IntegerType>(value.getType()) &&
               (isa<hw::ConstantOp>(op) ||
                op->getName().getDialectNamespace() == "comb" ||
                op->getName().getDialectNamespace() == "arith")) {
      IRMapping mapping;
      for (auto operand : op->getOperands()) {
        auto mapped = evaluate(operand, depth + 1);
        if (!mapped)
          return {};
        mapping.map(operand, mapped);
      }
      auto *copy = builder.clone(*op, mapping);
      SmallVector<Value, 1> folded;
      if (succeeded(builder.tryFold(copy, folded)) && !folded.empty()) {
        result = folded.front();
        copy->erase();
      } else {
        result = copy->getResult(0);
      }
    }
    cache[value] = result;
    return result;
  }

  SignalOp signal;
  IntegerAttr initial;
  OpBuilder &builder;
  DenseMap<Value, Value> cache;
  DenseSet<Value> active;
};

/// Find the sole recurring driver alongside a startup assignment. Before
/// HoistSignals the drive is inside its process; afterwards the value is a
/// process result or an already extracted register.
DriveOp getClockedDriver(SignalOp signal, DriveOp startup) {
  DriveOp clocked;
  for (auto *user : signal->getUsers()) {
    if (user == startup.getOperation() || isa<ProbeOp>(user))
      continue;
    auto drive = dyn_cast<DriveOp>(user);
    if (!drive || clocked)
      return {};
    clocked = drive;
  }
  if (!clocked)
    return {};
  if (clocked.getValue().getDefiningOp<seq::FirRegOp>())
    return clocked;
  auto process = clocked->getParentOfType<ProcessOp>();
  if (!process)
    process = clocked.getValue().getDefiningOp<ProcessOp>();
  TimeAttr time;
  if (!process || !matchPattern(clocked.getTime(), m_Constant(&time)) ||
      time.getTime() != 0 || time.getDelta() != 1 || time.getEpsilon() != 0 ||
      !process.walk([](WaitOp) { return WalkResult::interrupt(); })
           .wasInterrupted())
    return {};
  return clocked;
}

/// Constant startup assignments also initialize otherwise unconstrained state.
/// Module-level assignments require the provenance retained by HoistSignals.
void normalizeConstantInitialState(ModuleOp module) {
  SmallVector<DriveOp> drives;
  module.walk([&](DriveOp op) { drives.push_back(op); });
  for (auto startup : drives) {
    auto process = startup->getParentOfType<ProcessOp>();
    if (process) {
      if (process.getNumResults() || !process.getBody().hasOneBlock() ||
          !isa<HaltOp>(process.getBody().front().getTerminator()) ||
          !llvm::all_of(process.getBody().front().without_terminator(),
                        [&](Operation &op) {
                          return &op == startup.getOperation() ||
                                 (isMemoryEffectFree(&op) &&
                                  !op.getNumRegions());
                        }))
        continue;
    } else if (!isa<hw::HWModuleOp>(startup->getParentOp()) ||
               !startup->hasAttr("llhd.initial"))
      continue;
    IntegerAttr value;
    TimeAttr time;
    if (startup.getEnable() ||
        !matchPattern(startup.getValue(), m_Constant(&value)) ||
        !matchPattern(startup.getTime(), m_Constant(&time)) ||
        time.getTime() != 0 || time.getDelta() != 0 || time.getEpsilon() != 1)
      continue;
    auto signal = startup.getSignal().getDefiningOp<SignalOp>();
    if (!signal || !isa<hw::HWModuleOp>(signal->getParentOp()))
      continue;
    auto clocked = getClockedDriver(signal, startup);
    if (!clocked)
      continue;
    auto reg = clocked.getValue().getDefiningOp<seq::FirRegOp>();
    if (reg && reg.getPresetAttr()) {
      IntegerAttr initial;
      if (signal->hasAttr("llhd.unconstrained") ||
          !matchPattern(signal.getInit(), m_Constant(&initial)) ||
          reg.getPresetAttr() != initial)
        continue;
    }
    OpBuilder builder(signal);
    signal.getInitMutable().assign(
        hw::ConstantOp::create(builder, signal.getLoc(), value));
    signal->removeAttr("llhd.unconstrained");
    signal->setAttr("llhd.explicit_init", UnitAttr::get(module.getContext()));
    if (reg)
      reg.setPresetAttr(value);
    startup.erase();
    if (process)
      process.erase();
  }
}

/// Blocking startup assignments refine a scalar declaration
/// initializer. Recognize both raw processes and the result/drive pair left by
/// ordinary Mem2Reg. Require exactly one other, clocked driver so startup races
/// and genuine multiple drivers remain errors.
LogicalResult normalizeInitialState(ModuleOp module) {
  SmallVector<ProcessOp> processes;
  module.walk([&](ProcessOp op) { processes.push_back(op); });
  for (auto process : processes) {
    if (!process.getBody().hasOneBlock())
      continue;
    auto halt = dyn_cast<HaltOp>(process.getBody().front().getTerminator());
    if (!halt || process.getNumResults() > 2 ||
        (process.getNumResults() == 2 &&
         !matchPattern(halt.getYieldOperands()[1], m_One())))
      continue;
    DriveOp startup;
    SmallVector<DriveOp> startupDrives;
    bool supported = true;
    for (auto &op : process.getBody().front().without_terminator()) {
      if (auto drive = dyn_cast<DriveOp>(&op)) {
        if (process.getNumResults() ||
            (startup && startup.getSignal() != drive.getSignal())) {
          supported = false;
          break;
        }
        startup = drive;
        startupDrives.push_back(drive);
      } else if (!isa<ProbeOp>(op) &&
                 (!isMemoryEffectFree(&op) || op.getNumRegions() ||
                  (op.getName().getDialectNamespace() != "comb" &&
                   op.getName().getDialectNamespace() != "hw" &&
                   op.getName().getDialectNamespace() != "arith"))) {
        supported = false;
        break;
      }
    }
    if (!supported)
      continue;
    if (process.getNumResults()) {
      if (!process.getResult(0).hasOneUse())
        continue;
      startup = dyn_cast<DriveOp>(*process.getResult(0).getUsers().begin());
      if (!startup || startup.getValue() != process.getResult(0) ||
          startup->getParentOp() != process->getParentOp())
        continue;
      if (process.getNumResults() == 2 &&
          (!process.getResult(1).hasOneUse() ||
           startup.getEnable() != process.getResult(1)))
        continue;
    }
    TimeAttr time;
    if (!startup || (startup.getEnable() && process.getNumResults() != 2) ||
        !matchPattern(startup.getTime(), m_Constant(&time)) ||
        time.getTime() != 0 || time.getDelta() != 0 || time.getEpsilon() != 1)
      continue;
    auto signal = startup.getSignal().getDefiningOp<SignalOp>();
    IntegerAttr initial;
    if (!signal || signal->getParentOp() != process->getParentOp() ||
        !signal->hasAttr("llhd.explicit_init") ||
        signal->hasAttr("llhd.unconstrained") ||
        !matchPattern(signal.getInit(), m_Constant(&initial)))
      continue;
    if (startupDrives.size() > 1) {
      // Unrolling leaves separate blocking writes. Forward their values in
      // procedural order before evaluating the final startup expression.
      if (!llvm::all_of(startupDrives, [&](DriveOp drive) {
            return !drive.getEnable() && drive.getTime() == startup.getTime();
          }))
        continue;
      if (failed(promoteFormalInitialProcess(process)))
        return failure();
      auto drives = process.getBody().front().getOps<DriveOp>();
      if (!llvm::hasSingleElement(drives))
        continue;
      startup = *drives.begin();
    }
    auto clocked = getClockedDriver(signal, startup);
    if (!clocked)
      continue;
    auto reg = clocked.getValue().getDefiningOp<seq::FirRegOp>();
    if (reg) {
      if (reg.getPresetAttr() != initial)
        continue;
    }
    Value expression = process.getNumResults() ? halt.getYieldOperands()[0]
                                               : startup.getValue();
    OpBuilder builder(signal);
    auto value =
        InitialValueEvaluator(signal, initial, builder).evaluate(expression);
    if (!value || value.getType() != initial.getType())
      continue;
    signal.getInitMutable().assign(value);
    IntegerAttr constant;
    if (matchPattern(value, m_Constant(&constant))) {
      if (reg)
        reg.setPresetAttr(constant);
    } else if (reg) {
      reg.removePresetAttr();
      constrainFormalInitialState(builder, signal.getLoc(), reg, reg.getClk(),
                                  value,
                                  reg.getIsAsync() ? reg.getReset() : Value{});
    } else {
      // Formal extraction will supply the clock for the startup constraint.
      signal->setAttr("llhd.symbolic_init", builder.getUnitAttr());
    }
    startup.erase();
    process.erase();
  }
  return success();
}

/// Find an unchanged packed lane through concatenations and nested extracts.
/// Only return an existing value covering the entire requested interval.
Value getPackedLane(Value value, unsigned low, unsigned width,
                    unsigned depth = 0) {
  if (depth == 64)
    return {};
  if (low == 0 && value.getType().isSignlessInteger(width))
    return value;
  if (auto extract = value.getDefiningOp<comb::ExtractOp>())
    return getPackedLane(extract.getInput(), low + extract.getLowBit(), width,
                         depth + 1);
  if (auto concat = value.getDefiningOp<comb::ConcatOp>()) {
    unsigned offset = 0;
    for (auto input : llvm::reverse(concat.getInputs())) {
      unsigned inputWidth = input.getType().getIntOrFloatBitWidth();
      if (low >= offset && low + width <= offset + inputWidth)
        return getPackedLane(input, low - offset, width, depth + 1);
      offset += inputWidth;
    }
  }
  return {};
}

/// Project a constant array element through aggregate construction and muxes.
/// Without a builder, only return an existing value common to every mux arm.
/// Memoize shared mux trees and bound traversal of graph-region cycles.
struct ArrayLaneProjector {
  ArrayLaneProjector(hw::ArrayGetOp slice, uint64_t index,
                     OpBuilder *builder = nullptr)
      : slice(slice), index(index), builder(builder) {}

  Value project(Value input, unsigned depth = 0) {
    if (auto it = cache.find(input); it != cache.end())
      return it->second;
    Value value;
    if (depth < 64) {
      if (auto create = input.getDefiningOp<hw::ArrayCreateOp>()) {
        auto elements = create.getInputs();
        if (index < elements.size())
          value = elements[elements.size() - index - 1];
      } else if (auto inject = input.getDefiningOp<hw::ArrayInjectOp>()) {
        APInt injectedIndex;
        if (matchPattern(inject.getIndex(), m_ConstantInt(&injectedIndex)) &&
            injectedIndex.getActiveBits() <= 64)
          value = injectedIndex.getZExtValue() == index
                      ? inject.getElement()
                      : project(inject.getInput(), depth + 1);
      } else if (auto mux = input.getDefiningOp<comb::MuxOp>()) {
        Value trueValue = project(mux.getTrueValue(), depth + 1);
        Value falseValue = project(mux.getFalseValue(), depth + 1);
        if (trueValue && trueValue == falseValue)
          value = trueValue;
        else if (builder && trueValue && falseValue) {
          IRMapping mapping;
          mapping.map(mux.getTrueValue(), trueValue);
          mapping.map(mux.getFalseValue(), falseValue);
          auto *projected = builder->clone(*mux, mapping);
          projected->getResult(0).setType(slice.getType());
          value = projected->getResult(0);
        }
      }
    }
    if (!value && builder) {
      IRMapping mapping;
      mapping.map(slice.getInput(), input);
      value = builder->clone(*slice, mapping)->getResult(0);
    }
    cache[input] = value;
    return value;
  }

  hw::ArrayGetOp slice;
  uint64_t index;
  OpBuilder *builder;
  DenseMap<Value, Value> cache;
};

std::optional<uint64_t> getArrayLaneIndex(hw::ArrayGetOp slice) {
  APInt index;
  if (!matchPattern(slice.getIndex(), m_ConstantInt(&index)) ||
      index.getActiveBits() > 64)
    return {};
  uint64_t value = index.getZExtValue();
  if (value >= cast<hw::ArrayType>(slice.getInput().getType()).getNumElements())
    return {};
  return value;
}

/// Mem2Reg in the ordinary frontend pipeline can expand a partial drive into
/// an aggregate injection or packed concatenation using a probe of the same
/// signal. Recover its static targets before SROA, retaining only actual
/// writes.
bool normalizePartialDrives(ModuleOp module) {
  bool changed = false;
  SmallVector<DriveOp> drives;
  module.walk([&](DriveOp op) { drives.push_back(op); });
  for (auto drive : drives) {
    if (!isa<hw::HWModuleOp>(drive->getParentOp()))
      continue;
    OpBuilder builder(drive);
    auto cloneDrive = [&](Value target, Value value) {
      IRMapping mapping;
      mapping.map(drive.getSignal(), target);
      mapping.map(drive.getValue(), value);
      // Retain the drive's delay, enable, and attributes. Only the statically
      // unchanged portions are removed from its target.
      builder.clone(*drive, mapping);
    };
    if (auto inject = drive.getValue().getDefiningOp<hw::StructInjectOp>()) {
      auto probe = inject.getInput().getDefiningOp<ProbeOp>();
      if (!probe || probe.getSignal() != drive.getSignal())
        continue;
      Value target =
          SigStructExtractOp::create(builder, drive.getLoc(), drive.getSignal(),
                                     inject.getFieldNameAttr());
      cloneDrive(target, inject.getNewValue());
      drive.erase();
      changed = true;
      continue;
    }
    if (auto concat = drive.getValue().getDefiningOp<comb::ConcatOp>()) {
      SmallVector<std::pair<Value, unsigned>> updates;
      unsigned offset = 0;
      bool hasPadding = false;
      for (auto input : llvm::reverse(concat.getInputs())) {
        auto extract = input.getDefiningOp<comb::ExtractOp>();
        auto probe =
            extract ? extract.getInput().getDefiningOp<ProbeOp>() : ProbeOp();
        if (probe && probe.getSignal() == drive.getSignal() &&
            extract.getLowBit() == offset)
          hasPadding = true;
        else
          updates.emplace_back(input, offset);
        offset += input.getType().getIntOrFloatBitWidth();
      }
      if (!hasPadding)
        continue;
      auto indexType =
          builder.getIntegerType(std::max(1u, llvm::Log2_64_Ceil(offset)));
      for (auto [value, low] : updates) {
        Value index =
            hw::ConstantOp::create(builder, drive.getLoc(), indexType, low);
        Value target = SigExtractOp::create(builder, drive.getLoc(),
                                            RefType::get(value.getType()),
                                            drive.getSignal(), index);
        cloneDrive(target, value);
      }
      drive.erase();
      changed = true;
      continue;
    }
    auto inject = drive.getValue().getDefiningOp<hw::ArrayInjectOp>();
    if (!inject)
      continue;
    auto probe = inject.getInput().getDefiningOp<ProbeOp>();
    if (!probe || probe.getSignal() != drive.getSignal())
      continue;
    APInt index;
    if (!matchPattern(inject.getIndex(), m_ConstantInt(&index)) ||
        index.getActiveBits() > 64 ||
        index.getZExtValue() >=
            cast<hw::ArrayType>(inject.getInput().getType()).getNumElements())
      continue;

    auto target = SigArrayGetOp::create(builder, drive.getLoc(),
                                        drive.getSignal(), inject.getIndex());
    cloneDrive(target, inject.getElement());
    drive.erase();
    changed = true;
  }
  return changed;
}

/// Find packed lane boundaries hidden by register extraction. Follow mux arms
/// as well as concatenations so enabled updates retain their original lanes.
SmallVector<unsigned> getPackedLaneBoundaries(Value value) {
  SmallVector<unsigned> boundaries{0, value.getType().getIntOrFloatBitWidth()};
  SmallVector<std::pair<Value, unsigned>> worklist{{value, 0}};
  DenseSet<std::pair<Value, unsigned>> visited;
  while (!worklist.empty()) {
    auto [input, offset] = worklist.pop_back_val();
    if (!visited.insert({input, offset}).second)
      continue;
    if (auto concat = input.getDefiningOp<comb::ConcatOp>()) {
      for (auto lane : llvm::reverse(concat.getInputs())) {
        boundaries.push_back(offset);
        worklist.emplace_back(lane, offset);
        offset += lane.getType().getIntOrFloatBitWidth();
      }
    } else if (auto mux = input.getDefiningOp<comb::MuxOp>()) {
      worklist.emplace_back(mux.getTrueValue(), offset);
      worklist.emplace_back(mux.getFalseValue(), offset);
    }
  }
  llvm::sort(boundaries);
  boundaries.erase(std::unique(boundaries.begin(), boundaries.end()),
                   boundaries.end());
  return boundaries;
}

/// Register extraction can hide every partial access behind whole-signal
/// registers and drives. Expose the lanes of multiply driven signals so
/// SROA can split their storage and normalizeRegisterDrives can distinguish
/// actual updates from registered passthrough lanes.
void splitRegisterDrives(ModuleOp module) {
  SmallVector<DriveOp> drives;
  module.walk([&](DriveOp op) { drives.push_back(op); });
  for (auto drive : drives) {
    auto type = drive.getValue().getType();
    auto reg = drive.getValue().getDefiningOp<seq::FirRegOp>();
    if (!isa<IntegerType, hw::ArrayType>(type) ||
        !isa<hw::HWModuleOp>(drive->getParentOp()) || !reg ||
        !drive.getSignal().getDefiningOp<SignalOp>() ||
        !llvm::any_of(drive.getSignal().getUsers(), [&](Operation *user) {
          auto other = dyn_cast<DriveOp>(user);
          return other && other != drive &&
                 other.getSignal() == drive.getSignal();
        }))
      continue;

    OpBuilder builder(drive);
    if (auto intType = dyn_cast<IntegerType>(type)) {
      auto boundaries = getPackedLaneBoundaries(reg.getNext());
      if (boundaries.size() <= 2)
        continue;
      auto indexType = builder.getIntegerType(
          std::max(1u, llvm::Log2_64_Ceil(intType.getWidth())));
      for (unsigned i = 1; i < boundaries.size(); ++i) {
        unsigned low = boundaries[i - 1];
        unsigned width = boundaries[i] - low;
        Value index =
            hw::ConstantOp::create(builder, drive.getLoc(), indexType, low);
        Value target =
            SigExtractOp::create(builder, drive.getLoc(),
                                 RefType::get(builder.getIntegerType(width)),
                                 drive.getSignal(), index);
        Value value = comb::ExtractOp::create(builder, drive.getLoc(),
                                              drive.getValue(), low, width);
        IRMapping mapping;
        mapping.map(drive.getSignal(), target);
        mapping.map(drive.getValue(), value);
        builder.clone(*drive, mapping);
      }
      drive.erase();
      continue;
    }
    auto arrayType = cast<hw::ArrayType>(type);
    auto indexType = builder.getIntegerType(
        std::max(1u, llvm::Log2_64_Ceil(arrayType.getNumElements())));
    for (uint64_t i = 0, e = arrayType.getNumElements(); i < e; ++i) {
      Value index =
          hw::ConstantOp::create(builder, drive.getLoc(), indexType, i);
      Value target = SigArrayGetOp::create(builder, drive.getLoc(),
                                           drive.getSignal(), index);
      Value value = hw::ArrayGetOp::create(builder, drive.getLoc(),
                                           drive.getValue(), index);
      IRMapping mapping;
      mapping.map(drive.getSignal(), target);
      mapping.map(drive.getValue(), value);
      builder.clone(*drive, mapping);
    }
    drive.erase();
  }
}

/// Ordinary register extraction can pad a partial write with probes of the
/// untouched signal lanes. After SROA, those lanes appear to have both their
/// actual driver and a registered copy of themselves. Recover the partial write
/// when the register is only used to drive split signals, apart from an
/// optional self-feedback enable mux. Discard only exact passthrough lanes with
/// another driver. Reset, preset, symbolic, or independently observed register
/// state must not be discarded. Narrow aggregate registers even without padding
/// at this level, so subsequent iterations can expose padding in nested lanes.
/// Return whether any registers were narrowed.
bool normalizeRegisterDrives(ModuleOp module) {
  bool changed = false;
  SmallVector<seq::FirRegOp> registers;
  module.walk([&](seq::FirRegOp op) { registers.push_back(op); });
  for (auto reg : registers) {
    if (!isa<hw::HWModuleOp>(reg->getParentOp()) ||
        !isa<IntegerType, hw::ArrayType>(reg.getType()) || reg.getReset() ||
        reg.getPresetAttr() || reg.getInnerSymAttr())
      continue;
    // Ordinary extraction represents an enable as a mux feeding back the
    // entire register on its hold arm. Analyze padding on the update arm and
    // retain this mux around each surviving lane's state.
    Value update = reg.getNext();
    auto hold = update.getDefiningOp<comb::MuxOp>();
    if (hold && hold->getBlock() == reg->getBlock() &&
        (hold.getTrueValue() == reg.getResult() ||
         hold.getFalseValue() == reg.getResult()) &&
        hold.getCond() != reg.getResult() && hold.getResult().hasOneUse())
      update = hold.getTrueValue() == reg.getResult() ? hold.getFalseValue()
                                                      : hold.getTrueValue();
    else
      hold = {};
    SmallVector<Operation *> slices;
    bool supported = true;
    for (auto *user : reg->getUsers()) {
      if (hold && user == hold.getOperation())
        continue;
      auto arraySlice = dyn_cast<hw::ArrayGetOp>(user);
      if ((!isa<comb::ExtractOp>(user) &&
           (!arraySlice || !getArrayLaneIndex(arraySlice))) ||
          user->getBlock() != reg->getBlock() ||
          !llvm::all_of(user->getUsers(), [&](Operation *sliceUser) {
            auto drive = dyn_cast<DriveOp>(sliceUser);
            TimeAttr time;
            return drive && drive.getValue() == user->getResult(0) &&
                   drive->getBlock() == reg->getBlock() && !drive.getEnable() &&
                   drive.getSignal().getDefiningOp<SignalOp>() &&
                   matchPattern(drive.getTime(), m_Constant(&time)) &&
                   time.getTime() == 0 && time.getDelta() <= 1 &&
                   time.getEpsilon() <= 1;
          })) {
        supported = false;
        break;
      }
      slices.push_back(user);
    }
    if (!supported || slices.empty())
      continue;
    SmallVector<DriveOp> padding;
    for (auto *slice : slices) {
      Value next;
      if (auto packedSlice = dyn_cast<comb::ExtractOp>(slice))
        next = getPackedLane(update, packedSlice.getLowBit(),
                             packedSlice.getType().getIntOrFloatBitWidth());
      else {
        auto arraySlice = cast<hw::ArrayGetOp>(slice);
        next = ArrayLaneProjector(arraySlice, *getArrayLaneIndex(arraySlice))
                   .project(update);
      }
      if (!next)
        continue;
      auto probe = next.getDefiningOp<ProbeOp>();
      if (!probe)
        continue;
      for (auto *user : slice->getUsers()) {
        auto drive = cast<DriveOp>(user);
        if (probe.getSignal() == drive.getSignal() &&
            llvm::any_of(drive.getSignal().getUsers(), [&](Operation *other) {
              auto otherDrive = dyn_cast<DriveOp>(other);
              return otherDrive && otherDrive != drive &&
                     otherDrive.getSignal() == drive.getSignal() &&
                     otherDrive.getValue() != slice->getResult(0);
            }))
          padding.push_back(drive);
      }
    }
    for (auto drive : padding)
      drive.erase();
    for (auto *slice : slices) {
      if (!slice->use_empty()) {
        OpBuilder builder(slice);
        Value next;
        if (auto packedSlice = dyn_cast<comb::ExtractOp>(slice))
          next = builder.createOrFold<comb::ExtractOp>(
              slice->getLoc(), update, packedSlice.getLowBit(),
              packedSlice.getType().getIntOrFloatBitWidth());
        else {
          auto arraySlice = cast<hw::ArrayGetOp>(slice);
          next = ArrayLaneProjector(arraySlice, *getArrayLaneIndex(arraySlice),
                                    &builder)
                     .project(update);
        }
        IRMapping mapping;
        mapping.map(reg.getNext(), next);
        auto *narrowed = builder.clone(*reg, mapping);
        narrowed->getResult(0).setType(slice->getResult(0).getType());
        if (hold) {
          IRMapping holdMapping;
          holdMapping.map(update, next);
          holdMapping.map(reg.getResult(), narrowed->getResult(0));
          auto *narrowedHold = builder.clone(*hold, holdMapping);
          narrowedHold->getResult(0).setType(slice->getResult(0).getType());
          cast<seq::FirRegOp>(narrowed).getNextMutable().assign(
              narrowedHold->getResult(0));
        }
        slice->getResult(0).replaceAllUsesWith(narrowed->getResult(0));
      }
      slice->erase();
    }
    if (hold) {
      reg.getNextMutable().assign(update);
      hold.erase();
    }
    reg.erase();
    changed = true;
  }
  return changed;
}

LogicalResult preflight(ModuleOp module, bool normalized = false,
                        bool allowUndriven = false) {
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

    if (dialect == "verif" && !isFormalCheck(op) &&
        !isa<verif::SymbolicValueOp>(op)) {
      op->emitError(
          "unsupported verification effect in strict formal lowering");
      return WalkResult::interrupt();
    }
    if (auto drive = dyn_cast<DriveOp>(op)) {
      // Diagnose explicit aggregate state before process recognition. The
      // ordinary frontend pipeline may already have moved the drive outside
      // its process, and aggregate presets are not supported by extraction.
      if (auto signal = drive.getSignal().getDefiningOp<SignalOp>();
          signal && signal->hasAttr("llhd.explicit_init") &&
          !signal->hasAttr("llhd.unconstrained") &&
          isa<hw::ArrayType, hw::StructType, hw::UnionType>(
              signal.getInit().getType()) &&
          (drive->getParentOfType<ProcessOp>() ||
           drive.getValue().getDefiningOp<ProcessOp>())) {
        signal.emitError("aggregate register initialization is unsupported");
        return WalkResult::interrupt();
      }
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
      SmallVector<Value> worklist{signal.getResult()};
      while (!worklist.empty()) {
        for (auto *user : worklist.pop_back_val().getUsers()) {
          if (isa<DriveOp>(user)) {
            // Assignments along a region's control-flow paths share one
            // procedural driver, before and after process lowering.
            auto *owner = user->getParentOp();
            while (owner && !isa<ProcessOp, CombinationalOp>(owner))
              owner = owner->getParentOp();
            drivers.insert(owner ? owner : user);
          } else if (!normalized &&
                     isa<SigArrayGetOp, SigArraySliceOp, SigExtractOp,
                         SigStructExtractOp>(user)) {
            // Dynamic projections cannot be split by SROA. Count their actual
            // drivers before Mem2Reg promotes them to whole-signal updates.
            worklist.push_back(user->getResult(0));
          } else if (!isa<ProbeOp>(user)) {
            user->emitError(
                "unsupported signal access in strict formal lowering");
            return WalkResult::interrupt();
          }
        }
      }
      // Module-level undriven slices may only feed a process sensitivity list.
      // Defer their check until process lowering and cleanup remove those uses.
      // Check local signals before Mem2Reg can fold their initializer.
      if (drivers.size() > 1 ||
          (drivers.empty() &&
           (!allowUndriven || !isa<hw::HWModuleOp>(signal->getParentOp())))) {
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

/// Discard warning diagnostics and recover immediate assertions with explicit
/// $error actions before rejecting Sim operations. Cleanup removes the unused
/// formatting and value probes.
void lowerFormalDiagnostics(ModuleOp module) {
  SmallVector<sim::PrintFormattedProcOp> diagnostics;
  module.walk([&](sim::PrintFormattedProcOp op) {
    if ((op->getAttrOfType<UnitAttr>("sim.warning") ||
         op->getAttrOfType<UnitAttr>("verif.assertion_failure")) &&
        !op.getStream())
      diagnostics.push_back(op);
  });
  for (auto op : diagnostics) {
    if (op->getAttrOfType<UnitAttr>("sim.warning")) {
      op.erase();
      continue;
    }
    OpBuilder builder(op);
    Value condition =
        hw::ConstantOp::create(builder, op.getLoc(), builder.getI1Type(), 0);
    verif::AssertOp::create(builder, op.getLoc(), condition, Value{},
                            StringAttr{});
    op.erase();
  }
}

/// Time-valued data is an unsigned i64 count of femtoseconds, as in the Moore
/// frontend. Scheduling operands retain LLHD time and are checked separately.
/// Split constants shared by data and scheduling before rewriting types, so
/// neither delta/epsilon scheduling nor frontend timescale arithmetic is lost.
LogicalResult lowerTimeData(ModuleOp module) {
  auto isSchedulingUse = [](OpOperand &use) {
    if (auto drive = dyn_cast<DriveOp>(use.getOwner()))
      return &use == &drive.getTimeMutable();
    if (auto wait = dyn_cast<WaitOp>(use.getOwner()))
      return wait.getDelay() &&
             use.getOperandNumber() == wait.getYieldOperands().size();
    return false;
  };
  SmallVector<ConstantTimeOp> constants;
  SmallVector<Operation *> conversions;
  auto scan = module.walk([&](Operation *op) -> WalkResult {
    if (isa<CurrentTimeOp>(op)) {
      op->emitError("simulation time queries are unsupported in synchronous "
                    "formal lowering");
      return WalkResult::interrupt();
    }
    for (auto &use : op->getOpOperands())
      if (isSchedulingUse(use) && !use.get().getDefiningOp<ConstantTimeOp>()) {
        op->emitError("dynamic time delays are unsupported in synchronous "
                      "formal lowering");
        return WalkResult::interrupt();
      }
    if (auto constant = dyn_cast<ConstantTimeOp>(op))
      constants.push_back(constant);
    if (isa<IntToTimeOp, TimeToIntOp>(op))
      conversions.push_back(op);
    return WalkResult::advance();
  });
  if (scan.wasInterrupted())
    return failure();
  for (auto constant : constants) {
    if (llvm::all_of(constant.getResult().getUses(), isSchedulingUse))
      continue;
    auto attr = constant.getValue();
    if (attr.getDelta() || attr.getEpsilon())
      return constant.emitError(
          "time-valued data cannot contain delta or epsilon components");
    uint64_t scale = llvm::StringSwitch<uint64_t>(attr.getTimeUnit())
                         .Case("fs", 1)
                         .Case("ps", 1000)
                         .Case("ns", 1000000)
                         .Case("us", 1000000000)
                         .Case("ms", 1000000000000)
                         .Case("s", 1000000000000000)
                         .Default(0);
    if (!scale)
      return constant.emitError(
          "time-valued data with units smaller than fs is unsupported");
    if (attr.getTime() > std::numeric_limits<uint64_t>::max() / scale)
      return constant.emitError(
          "time-valued data does not fit into i64 femtoseconds");
    OpBuilder builder(constant);
    auto value = hw::ConstantOp::create(
        builder, constant.getLoc(),
        builder.getIntegerAttr(builder.getI64Type(),
                               APInt(64, attr.getTime() * scale)));
    constant.getResult().replaceUsesWithIf(
        value, [&](OpOperand &use) { return !isSchedulingUse(use); });
  }
  // Update module/instance ports, nested aggregate/ref types, SSA results and
  // block arguments together. There is no pass boundary while the identity
  // conversions are temporarily ill-typed; all work is on the transaction
  // clone.
  AttrTypeReplacer replacer;
  replacer.addReplacement([](TimeType type) -> Type {
    return IntegerType::get(type.getContext(), 64);
  });
  // Handwritten field/port lists are not exposed as type sub-elements.
  replacer.addReplacement([&](hw::StructType type) -> Type {
    SmallVector<hw::StructType::FieldInfo> fields(type.getElements());
    for (auto &field : fields)
      field.type = replacer.replace(field.type);
    return hw::StructType::get(type.getContext(), fields);
  });
  replacer.addReplacement([&](hw::UnionType type) -> Type {
    SmallVector<hw::UnionType::FieldInfo> fields(type.getElements());
    for (auto &field : fields)
      field.type = replacer.replace(field.type);
    return hw::UnionType::get(type.getContext(), fields);
  });
  replacer.addReplacement([&](hw::ModuleType type) -> Type {
    SmallVector<hw::ModulePort> ports(type.getPorts());
    for (auto &port : ports)
      port.type = replacer.replace(port.type);
    return hw::ModuleType::get(type.getContext(), ports);
  });
  // Keep any unhandled time attributes intact for the final legality check.
  replacer.addReplacement(
      [](TimeAttr attr) -> std::optional<std::pair<Attribute, WalkResult>> {
        return std::make_pair(attr, WalkResult::skip());
      });
  module.walk([&](Operation *op) {
    if (!isa<ConstantTimeOp>(op))
      replacer.replaceElementsIn(op, /*replaceAttrs=*/true,
                                 /*replaceLocs=*/false, /*replaceTypes=*/true);
  });
  for (auto *op : conversions) {
    op->getResult(0).replaceAllUsesWith(op->getOperand(0));
    op->erase();
  }
  for (auto constant : constants)
    if (constant->use_empty())
      constant.erase();
  return success();
}

/// Select between updated elements instead of whole-array partial updates.
/// This exposes complete injection chains across conditional loop iterations,
/// allowing cleanup to remove their apparent dependence on the old array.
struct FactorArrayUpdateMux : OpRewritePattern<comb::MuxOp> {
  FactorArrayUpdateMux(MLIRContext *context, unsigned &budget, bool &exhausted)
      : OpRewritePattern(context), budget(budget), exhausted(exhausted) {}

  LogicalResult matchAndRewrite(comb::MuxOp op,
                                PatternRewriter &rewriter) const override {
    auto trueUpdate = op.getTrueValue().getDefiningOp<hw::ArrayInjectOp>();
    auto falseUpdate = op.getFalseValue().getDefiningOp<hw::ArrayInjectOp>();
    if (!trueUpdate || !falseUpdate ||
        trueUpdate.getInput() != falseUpdate.getInput() ||
        trueUpdate.getIndex() != falseUpdate.getIndex())
      return failure();
    if (budget < 2) {
      exhausted = true;
      return rewriter.notifyMatchFailure(op, "array update expansion limit");
    }
    budget -= 2;
    IRMapping mapping;
    mapping.map(op.getTrueValue(), trueUpdate.getElement());
    mapping.map(op.getFalseValue(), falseUpdate.getElement());
    // Retain the mux's twoState flag and attributes on the element selection.
    auto *mux = rewriter.clone(*op, mapping);
    mux->getResult(0).setType(trueUpdate.getElement().getType());
    rewriter.replaceOpWithNewOp<hw::ArrayInjectOp>(
        op, trueUpdate.getInput(), trueUpdate.getIndex(), mux->getResult(0));
    return success();
  }

  unsigned &budget;
  bool &exhausted;
};

/// Expose packed array lanes so truncations can discard unobserved storage
/// after SROA reconstructs a probed aggregate from independently driven slices.
struct FlattenPackedArrayCast : OpRewritePattern<hw::BitcastOp> {
  FlattenPackedArrayCast(MLIRContext *context, unsigned &budget,
                         bool &exhausted)
      : OpRewritePattern(context), budget(budget), exhausted(exhausted) {}

  LogicalResult matchAndRewrite(hw::BitcastOp op,
                                PatternRewriter &rewriter) const override {
    auto array = op.getInput().getDefiningOp<hw::ArrayCreateOp>();
    if (!array || array.getInputs().empty() || !isa<IntegerType>(op.getType()))
      return failure();
    auto width = hw::getBitWidth(array.getInputs().front().getType());
    if (width <= 0)
      return failure();
    unsigned cost = array.getNumOperands() + 1;
    if (cost > budget) {
      exhausted = true;
      return rewriter.notifyMatchFailure(op, "packed cast expansion limit");
    }
    budget -= cost;
    SmallVector<Value> lanes;
    for (auto input : array.getInputs()) {
      lanes.push_back(rewriter.createOrFold<hw::BitcastOp>(
          op.getLoc(), rewriter.getIntegerType(width), input));
    }
    rewriter.replaceOpWithNewOp<comb::ConcatOp>(op, lanes);
    return success();
  }

  unsigned &budget;
  bool &exhausted;
};

/// Expose the lanes of packed bitwise wiring before whole-value dependency
/// analysis. A full packed output may still be used, so width narrowing of the
/// producer alone cannot eliminate dependencies on unrelated lanes.
struct DistributeExtractThroughOr : OpRewritePattern<comb::ExtractOp> {
  DistributeExtractThroughOr(MLIRContext *context, unsigned &budget,
                             bool &exhausted)
      : OpRewritePattern(context), budget(budget), exhausted(exhausted) {}

  LogicalResult matchAndRewrite(comb::ExtractOp op,
                                PatternRewriter &rewriter) const override {
    auto bitwise = op.getInput().getDefiningOp<comb::OrOp>();
    if (!bitwise || op.getType() == bitwise.getType())
      return failure();
    unsigned cost = bitwise.getNumOperands() + 1;
    if (cost > budget) {
      exhausted = true;
      return rewriter.notifyMatchFailure(op, "packed slice expansion limit");
    }
    budget -= cost;

    IRMapping operands;
    for (Value input : bitwise.getInputs()) {
      if (operands.contains(input))
        continue;
      IRMapping sliceInput;
      sliceInput.map(op.getInput(), input);
      auto *slice = rewriter.clone(*op, sliceInput);
      operands.map(input, slice->getResult(0));
    }
    // Cloning retains the OR's twoState property and other attributes. The
    // extraction itself also retains its attributes and bit offset on each
    // input. Bitwise OR commutes with slicing in both two- and four-state
    // logic.
    auto *narrowed = rewriter.clone(*bitwise, operands);
    narrowed->getResult(0).setType(op.getType());
    rewriter.replaceOp(op, narrowed->getResult(0));
    return success();
  }

  unsigned &budget;
  bool &exhausted;
};

LogicalResult normalizePackedSlices(ModuleOp module) {
  // Bound expansion of conditional array updates, aggregate casts, and shared
  // OR trees. Only expose packed lanes and push slices towards inputs; do not
  // factor packed producers back out and oscillate. A separate cleanup folds
  // complete array updates and the exposed zero-padded lanes.
  unsigned budget = 65536;
  bool exhausted = false;
  RewritePatternSet patterns(module.getContext());
  patterns.add<FactorArrayUpdateMux>(module.getContext(), budget, exhausted);
  patterns.add<FlattenPackedArrayCast>(module.getContext(), budget, exhausted);
  patterns.add<DistributeExtractThroughOr>(module.getContext(), budget,
                                           exhausted);
  comb::ExtractOp::getCanonicalizationPatterns(patterns, module.getContext());
  if (failed(applyPatternsGreedily(module, std::move(patterns))))
    return module.emitError("packed slice normalization did not converge");
  if (exhausted)
    return module.emitError(
        "packed slice normalization exceeds expansion limit");
  return success();
}

LogicalResult verifyCore(ModuleOp module) {
  auto result = module.walk([&](Operation *op) -> WalkResult {
    StringRef dialect = op->getName().getDialectNamespace();
    bool badType = false;
    std::function<void(Type)> checkType = [&](Type type) {
      type.walk([&](Type nested) {
        auto dialect = nested.getDialect().getNamespace();
        badType |= dialect != "builtin" && dialect != "hw" && dialect != "seq";
        badType |= isa<FloatType, ComplexType>(nested);
        if (auto structure = dyn_cast<hw::StructType>(nested))
          for (auto &field : structure.getElements())
            checkType(field.type);
        if (auto unionType = dyn_cast<hw::UnionType>(nested))
          for (auto &field : unionType.getElements())
            checkType(field.type);
      });
    };
    for (Type type : op->getOperandTypes())
      checkType(type);
    for (Type type : op->getResultTypes())
      checkType(type);
    for (auto attr : op->getAttrs())
      attr.getValue().walk(checkType);
    if (auto moduleLike = dyn_cast<hw::HWModuleLike>(op))
      for (auto &port : moduleLike.getHWModuleType().getPorts())
        checkType(port.type);
    for (auto &region : op->getRegions())
      for (auto &block : region)
        for (auto arg : block.getArguments())
          checkType(arg.getType());
    if (badType) {
      op->emitError("unsupported type remains in formal hardware");
      return WalkResult::interrupt();
    }

    if (isa<ModuleOp, verif::SymbolicValueOp>(op) || dialect == "hw" ||
        dialect == "seq" || dialect == "comb")
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
    if (!maxMonitorDepth)
      return module.emitError("max-monitor-depth must be positive");
    lowerFormalDiagnostics(module);
    // Resolve static procedural loops before SROA and driver validation. Their
    // induction variables may select independently driven packed slices.
    unrollFormalLoops(module);
    if (failed(cleanup(module)))
      return failure();
    normalizeConstantInitialState(module);
    if (failed(normalizeInitialState(module)))
      return failure();
    // Independent aggregate elements may have different drivers, including a
    // mix of combinational and clocked assignments. Split these before checking
    // driver ownership or promoting partial writes to whole-signal updates.
    // Repeat after recovering partial drives or narrowing registers: aggregate
    // elements can themselves contain independently driven packed lanes or
    // nested aggregates. Each iteration reduces the width or aggregate depth.
    bool changed;
    do {
      changed = normalizePartialDrives(module);
      splitRegisterDrives(module);
      PassManager aggregates(&getContext());
      aggregates.addNestedPass<hw::HWModuleOp>(createSROA());
      if (failed(runPipeline(aggregates, module)) || failed(cleanup(module)))
        return failure();
      changed |= normalizeRegisterDrives(module);
      if (failed(cleanup(module)))
        return failure();
    } while (changed);
    if (failed(preflight(module, false, true)))
      return failure();
    if (failed(lowerTimeData(module)))
      return failure();
    PassManager storage(&getContext());
    storage.addNestedPass<hw::HWModuleOp>(createMem2RegPass());
    if (failed(runPipeline(storage, module)))
      return failure();
    hoistFormalSignals(module);
    if (failed(preflight(module, true, true)))
      return failure();
    SmallVector<ProcessOp> processes;
    module.walk([&](ProcessOp op) { processes.push_back(op); });
    for (auto process : processes) {
      if (succeeded(unwrapConstantInitialProcess(process)))
        continue;
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
          "unsupported formal process: expected a recognizable edge-triggered "
          "clocked process or a property-only wrapper; multiple clocks, "
          "event-region dependencies and general loops are unsupported");
      return WalkResult::interrupt();
    });
    if (remaining.wasInterrupted())
      return failure();
    // Mem2Reg and register extraction may expose additional combinational
    // loops.
    unrollFormalLoops(module);
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
    // Expose truncations through packed casts before deciding which slices
    // remain observable. Never fill a live undriven slice from its initializer.
    if (failed(normalizePackedSlices(module)) || failed(cleanup(module)) ||
        failed(preflight(module, true)))
      return failure();
    PassManager signals(&getContext());
    signals.addNestedPass<hw::HWModuleOp>(createSig2Reg());
    if (failed(runPipeline(signals, module)))
      return failure();
    // Past has its own sampling clock and intentionally no invented initial
    // value. Pending obligations, in contrast, are initialized to false.
    SmallVector<ltl::PastOp> pastOps;
    module.walk([&](ltl::PastOp op) { pastOps.push_back(op); });
    for (auto op : pastOps) {
      if (op.getDelay() > maxMonitorDepth)
        return op.emitError("sampled history exceeds max-monitor-depth");
      OpBuilder builder(op);
      Value clock =
          builder.createOrFold<seq::ToClockOp>(op.getLoc(), op.getClk());
      Value value = op.getInput();
      for (unsigned i = 0; i < op.getDelay(); ++i)
        value = seq::CompRegOp::create(builder, op.getLoc(), value, clock);
      op.replaceAllUsesWith(value);
      op.erase();
    }
    SmallVector<Operation *> checks;
    module.walk([&](Operation *op) {
      if (isFormalCheck(op))
        checks.push_back(op);
    });
    for (auto *check : checks)
      if (failed(MonitorBuilder(check, maxMonitorDepth).lower()))
        return failure();
    if (failed(cleanup(module)))
      return failure();
    // Region simplification may materialize constants and selections with
    // Arith. Normalize those implementation artifacts before enforcing dialect
    // purity.
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
    SmallVector<arith::SelectOp> selects;
    module.walk([&](arith::SelectOp op) { selects.push_back(op); });
    for (auto op : selects) {
      if (!isa<IntegerType>(op.getType()))
        continue;
      OpBuilder builder(op);
      auto mux = comb::MuxOp::create(builder, op.getLoc(), op.getCondition(),
                                     op.getTrueValue(), op.getFalseValue());
      op.replaceAllUsesWith(mux.getResult());
      op.erase();
    }
    if (failed(normalizePackedSlices(module)) || failed(cleanup(module)))
      return failure();
    return verifyCore(module);
  }
};
} // namespace
