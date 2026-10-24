//===----------------------------------------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "FormalUtils.h"
#include "circt/Dialect/Comb/CombOps.h"
#include "circt/Dialect/HW/HWOps.h"
#include "circt/Dialect/LLHD/LLHDOps.h"
#include "circt/Dialect/LLHD/LLHDPasses.h"
#include "circt/Support/UnusedOpPruner.h"
#include "mlir/Analysis/CFGLoopInfo.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/Dominance.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/PostOrderIterator.h"
#include "llvm/Support/Debug.h"

#define DEBUG_TYPE "llhd-unroll-loops"

namespace circt {
namespace llhd {
#define GEN_PASS_DEF_UNROLLLOOPSPASS
#include "circt/Dialect/LLHD/LLHDPasses.h.inc"
} // namespace llhd
} // namespace circt

using namespace mlir;
using namespace circt;
using namespace llhd;
using llvm::SmallDenseSet;
using llvm::SmallSetVector;

//===----------------------------------------------------------------------===//
// Utilities
//===----------------------------------------------------------------------===//

/// Clone a list of blocks into a region before the given block.
///
/// See `Region::cloneInto` for the original code that clones an entire region.
static void cloneBlocks(ArrayRef<Block *> blocks, Region &region,
                        Region::iterator before, IRMapping &mapper) {
  // If the list is empty there is nothing to clone.
  if (blocks.empty())
    return;

  // First clone all the blocks and block arguments and map them, but don't yet
  // clone the operations, as they may otherwise add a use to a block that has
  // not yet been mapped
  SmallVector<Block *> newBlocks;
  newBlocks.reserve(blocks.size());
  for (auto *block : blocks) {
    auto *newBlock = new Block();
    mapper.map(block, newBlock);
    for (auto arg : block->getArguments())
      mapper.map(arg, newBlock->addArgument(arg.getType(), arg.getLoc()));
    region.getBlocks().insert(before, newBlock);
    newBlocks.push_back(newBlock);
  }

  // Now follow up with creating the operations, but don't yet clone their
  // regions, nor set their operands. Setting the successors is safe as all have
  // already been mapped. We are essentially just creating the operation results
  // to be able to map them. Cloning the operands and region as well would lead
  // to uses of operations not yet mapped.
  auto cloneOptions =
      Operation::CloneOptions::all().cloneRegions(false).cloneOperands(false);
  for (auto [oldBlock, newBlock] : llvm::zip(blocks, newBlocks))
    for (auto &op : *oldBlock)
      newBlock->push_back(op.clone(mapper, cloneOptions));

  // Finally now that all operation results have been mapped, set the operands
  // and clone the regions.
  SmallVector<Value> operands;
  for (auto [oldBlock, newBlock] : llvm::zip(blocks, newBlocks)) {
    for (auto [oldOp, newOp] : llvm::zip(*oldBlock, *newBlock)) {
      operands.resize(oldOp.getNumOperands());
      llvm::transform(
          oldOp.getOperands(), operands.begin(),
          [&](Value operand) { return mapper.lookupOrDefault(operand); });
      newOp.setOperands(operands);
      for (auto [oldRegion, newRegion] :
           llvm::zip(oldOp.getRegions(), newOp.getRegions()))
        oldRegion.cloneInto(&newRegion, mapper);
    }
  }
}

//===----------------------------------------------------------------------===//
// Loop Unroller
//===----------------------------------------------------------------------===//

namespace {
/// Evaluate integer Comb expressions for concrete header argument values. Use
/// the operations' own folders so extensions, comparisons and arithmetic retain
/// their actual fixed-width semantics. Folding a clone keeps recognition from
/// mutating the user's IR when an operation only supports in-place folding.
struct StaticLoopEvaluator {
  StaticLoopEvaluator(Block::BlockArgListType arguments,
                      ArrayRef<IntegerAttr> values) {
    for (auto [arg, value] : llvm::zip(arguments, values))
      cache[arg] = value;
  }

  IntegerAttr evaluate(Value value) {
    auto [it, inserted] = cache.try_emplace(value, IntegerAttr{});
    if (!inserted)
      return it->second;
    if (cache.size() > 256 || !isa<IntegerType>(value.getType()))
      return {};
    IntegerAttr constant;
    if (matchPattern(value, m_Constant(&constant)))
      return cache[value] = constant;
    auto *op = value.getDefiningOp();
    if (!op || op->getName().getDialectNamespace() != "comb" ||
        op->getNumResults() != 1 || op->getNumRegions())
      return {};
    SmallVector<Attribute> operands;
    for (auto operand : op->getOperands()) {
      auto attr = evaluate(operand);
      if (!attr)
        return {};
      operands.push_back(attr);
    }
    auto *copy = op->clone();
    SmallVector<OpFoldResult> results;
    IntegerAttr result;
    if (succeeded(copy->fold(operands, results)) && results.size() == 1) {
      if (auto attr = dyn_cast<Attribute>(results.front()))
        result = dyn_cast<IntegerAttr>(attr);
      else if (auto operand = dyn_cast<Value>(results.front()))
        result = cache.lookup(operand);
    }
    copy->destroy();
    return cache[value] = result;
  }

  DenseMap<Value, IntegerAttr> cache;
};

/// A data structure tracking information on a single loop.
struct Loop {
  Loop(unsigned loopId, CFGLoop &cfgLoop, bool formal)
      : loopId(loopId), cfgLoop(cfgLoop), formal(formal) {}
  bool failMatch(const Twine &msg) const;
  bool match(DominanceInfo &domInfo);
  bool matchBound(Value condition);
  bool matchFormalBound(Value condition);
  void unroll(CFGLoopInfo &cfgLoopInfo);

  /// A numeric identifier for debugging purposes.
  unsigned loopId;
  /// Loop analysis information about this specific loop.
  CFGLoop &cfgLoop;
  bool formal;
  /// The CFG edge exiting the loop at its static bound.
  BlockOperand *exitEdge = nullptr;
  /// Whether the loop has exits besides the statically bounded exit.
  bool hasEarlyExits = false;
  /// Whether the full condition may exit before the selected static bound.
  bool preserveCondition = false;
  /// The SSA value holding the exit condition.
  Value exitCondition;
  /// Whether the exit condition is inverted, i.e. the contination condition.
  bool exitInverted;
  /// The induction variable.
  Value indVar;
  /// The continuation predicate. The loop continues until the induction
  /// variable compared against the end bound no longer matches this predicate.
  comb::ICmpPredicate predicate;
  /// The induction variable increment.
  APInt indVarIncrement;
  /// The initial value for the induction variable.
  APInt beginBound;
  /// The final value for the induction variable.
  APInt endBound;
  /// Concrete header counter values, including the final exiting iteration.
  SmallVector<APInt> indVarValues;
  /// The number of iterations before the static bound (excluding early exits).
  unsigned tripCount = 0;
};
} // namespace

static llvm::raw_ostream &operator<<(llvm::raw_ostream &os, const Loop &loop) {
  os << "#" << loop.loopId << " from ";
  loop.cfgLoop.getHeader()->printAsOperand(os);
  os << " to ";
  SmallVector<Block *> latches;
  loop.cfgLoop.getLoopLatches(latches);
  llvm::interleaveComma(latches, os,
                        [&](Block *latch) { latch->printAsOperand(os); });
  return os;
}

/// Helper to print a debug message on match failure and return false.
bool Loop::failMatch(const Twine &msg) const {
  LLVM_DEBUG(llvm::dbgs() << "- Ignoring loop " << *this << ": " << msg
                          << "\n");
  return false;
}

/// Check that the loop matches the specific pattern we understand, and extract
/// the loop condition and induction variable.
bool Loop::match(DominanceInfo &domInfo) {
  // Formal process loops must execute entirely within one sampling step.
  if (formal)
    for (auto *block : cfgLoop.getBlocks())
      for (auto &op : *block)
        if (isa<WaitOp, HaltOp>(op))
          return failMatch("loop suspends execution");

  // A statically bounded exit must be encountered before every back-edge.
  // Besides header-tested loops this includes do/while latch tests, even when
  // another path exits early through a break.
  SmallVector<BlockOperand *> exits;
  for (auto *block : cfgLoop.getBlocks())
    for (auto &edge : block->getTerminator()->getBlockOperands())
      if (!cfgLoop.contains(edge.get()))
        exits.push_back(&edge);
  if (!formal && exits.size() != 1)
    return failMatch("multiple exits");
  SmallVector<Block *> latches;
  cfgLoop.getLoopLatches(latches);
  for (auto *edge : exits) {
    auto exitBranch = dyn_cast<cf::CondBranchOp>(edge->getOwner());
    if (!exitBranch)
      continue;
    if (formal && !llvm::all_of(latches, [&](Block *latch) {
          return domInfo.dominates(exitBranch->getBlock(), latch);
        }))
      continue;
    exitEdge = edge;
    hasEarlyExits = exits.size() != 1;
    exitCondition = exitBranch.getCondition();
    exitInverted = exitEdge->getOperandNumber() == 1;

    // A conjunct can bound a continuation condition with dynamic guards.
    // Dually, a disjunct can force an exit. Preserve the complete condition
    // in cloned iterations when only one part supplies the static bound.
    SmallSetVector<Value, 8> conditions;
    conditions.insert(exitCondition);
    for (unsigned i = 0; i < conditions.size(); ++i) {
      Value condition = conditions[i];
      auto *op = condition.getDefiningOp();
      if (formal && op &&
          ((exitInverted && isa<comb::AndOp>(op)) ||
           (!exitInverted && isa<comb::OrOp>(op)))) {
        conditions.insert(op->operand_begin(), op->operand_end());
        continue;
      }
      if (formal ? matchFormalBound(condition) : matchBound(condition)) {
        preserveCondition = condition != exitCondition;
        return true;
      }
    }
  }
  return failMatch("no supported static loop bound");
}

/// Prove termination by evaluating statically known header recurrences and the
/// exit condition. Unknown or path-dependent values cannot establish a bound.
/// Repeated states and sequences exceeding the expansion limit are rejected.
bool Loop::matchFormalBound(Value condition) {
  auto *header = cfgLoop.getHeader();
  SmallVector<IntegerAttr> initial(header->getNumArguments());
  SmallVector<SmallVector<Value>> updates(header->getNumArguments());
  for (auto counter : header->getArguments()) {
    if (!isa<IntegerType>(counter.getType()))
      continue;
    auto index = counter.getArgNumber();
    bool valid = true;
    for (auto &edge : header->getUses()) {
      auto branch = dyn_cast<BranchOpInterface>(edge.getOwner());
      if (!branch)
        return failMatch("unsupported branch to loop header");
      auto incoming =
          branch.getSuccessorOperands(edge.getOperandNumber())[index];
      if (cfgLoop.contains(branch->getBlock())) {
        updates[index].push_back(incoming);
        continue;
      }
      IntegerAttr constant;
      if (!matchPattern(incoming, m_Constant(&constant)) ||
          (initial[index] && initial[index] != constant))
        valid = false;
      else
        initial[index] = constant;
    }
    if (!valid || updates[index].empty())
      initial[index] = {};
  }

  // Track all statically known header arguments together: conditions can use
  // more than one counter, such as i < j with i++ and j--. Data-dependent
  // accumulators become unknown without preventing evaluation of the counters.
  SmallDenseSet<APInt, 16> seen;
  SmallVector<SmallVector<IntegerAttr>> states;
  auto current = initial;
  for (unsigned iteration = 0; iteration < 1024; ++iteration) {
    APInt state(1, 0);
    for (auto [arg, value] : llvm::zip(header->getArguments(), current))
      if (auto type = dyn_cast<IntegerType>(arg.getType())) {
        state =
            state.concat(value ? value.getValue() : APInt(type.getWidth(), 0));
        state = state.concat(APInt(1, bool(value)));
      }
    if (!seen.insert(state).second)
      break;
    StaticLoopEvaluator evaluator(header->getArguments(), current);
    auto test = evaluator.evaluate(condition);
    if (!test)
      break;
    states.push_back(current);
    if (test.getValue().isZero() == exitInverted) {
      // One concrete counter is sufficient for the unroller. Other statically
      // known arguments still flow through the cloned blocks normally.
      for (auto counter : header->getArguments()) {
        auto index = counter.getArgNumber();
        if (!llvm::all_of(states, [&](const auto &values) {
              return bool(values[index]);
            }))
          continue;
        indVar = counter;
        beginBound = initial[index].getValue();
        tripCount = states.size() - 1;
        for (const auto &values : states)
          indVarValues.push_back(values[index].getValue());
        return true;
      }
      break;
    }
    for (auto [index, incoming] : llvm::enumerate(updates)) {
      IntegerAttr next;
      for (auto update : incoming) {
        auto value = evaluator.evaluate(update);
        if (!value || (next && next != value)) {
          next = {};
          break;
        }
        next = value;
      }
      current[index] = next;
    }
  }
  return failMatch("counter recurrence is not statically bounded");
}

/// Match one comparison that guarantees termination of the loop.
bool Loop::matchBound(Value condition) {
  // Determine one of the loop bounds and the induction variable based on the
  // exit condition.
  if (auto icmpOp = condition.getDefiningOp<comb::ICmpOp>()) {
    IntegerAttr boundAttr;
    if (!matchPattern(icmpOp.getRhs(), m_Constant(&boundAttr)))
      return failMatch("non-constant loop bound");
    indVar = icmpOp.getLhs();
    predicate = icmpOp.getPredicate();
    endBound = boundAttr.getValue();
  } else {
    return failMatch("unsupported exit condition");
  }

  // If the exit condition is not inverted, the predicate is the exit predicate.
  // Negate it such that we have a continuation predicate.
  if (!exitInverted)
    predicate = comb::ICmpOp::getNegatedPredicate(predicate);

  // Determine the initial and next value of the induction variable.
  auto *header = cfgLoop.getHeader();
  auto indVarArg = dyn_cast<BlockArgument>(indVar);
  if (!indVarArg || indVarArg.getOwner() != header)
    return failMatch("induction variable is not a header block argument");
  IntegerAttr beginBoundAttr;
  SmallVector<Value> nextValues;
  for (auto &pred : header->getUses()) {
    auto branchOp = dyn_cast<BranchOpInterface>(pred.getOwner());
    if (!branchOp)
      return failMatch("header predecessor terminator is not a branch op");
    auto indVarValue = branchOp.getSuccessorOperands(
        pred.getOperandNumber())[indVarArg.getArgNumber()];
    IntegerAttr boundAttr;
    if (cfgLoop.contains(pred.getOwner()->getBlock())) {
      nextValues.push_back(indVarValue);
    } else if (matchPattern(indVarValue, m_Constant(&boundAttr))) {
      if (!beginBoundAttr)
        beginBoundAttr = boundAttr;
      else if (boundAttr != beginBoundAttr)
        return failMatch("multiple initial bounds");
    } else {
      return failMatch("unsupported induction variable value");
    }
  }
  if (!beginBoundAttr)
    return failMatch("no initial bound");
  beginBound = beginBoundAttr.getValue();

  // Every back edge must advance the induction variable by the same constant.
  // Cleanup may share the increment across conditional paths and branch back
  // to the header separately with different loop-carried data values.
  std::optional<APInt> increment;
  for (auto nextValue : nextValues) {
    auto addOp = nextValue.getDefiningOp<comb::AddOp>();
    if (!addOp || addOp.getNumOperands() != 2)
      return failMatch("unsupported increment");
    if (addOp.getOperand(0) != indVarArg)
      return failMatch("increment LHS not the induction variable");
    IntegerAttr incAttr;
    if (!matchPattern(addOp.getOperand(1), m_Constant(&incAttr)))
      return failMatch("increment RHS non-constant");
    if (increment && *increment != incAttr.getValue())
      return failMatch("inconsistent increments across back edges");
    increment = incAttr.getValue();
  }
  if (!increment)
    return failMatch("no induction variable increment");
  indVarIncrement = *increment;

  std::optional<unsigned> range;
  // Determine the trip count and loop behavior.
  // for (unsigned i = N; i < M; i += S) with N <= M and S > 0
  if (predicate == comb::ICmpPredicate::ult && beginBound.ule(endBound) &&
      indVarIncrement.sgt(0)) {
    range = endBound.getZExtValue() - beginBound.getZExtValue();
  }
  // for (signed i = N; i < M; i += S) with M > 0, N <= M and S > 0
  if (predicate == comb::ICmpPredicate::slt && !endBound.isNegative() &&
      beginBound.sle(endBound) && indVarIncrement.sgt(0)) {
    range = endBound.getZExtValue() - beginBound.getZExtValue();
  }
  // for (signed i = N; i >= M; i += S) for N > 0, M >= 0, S < 0
  if (predicate == comb::ICmpPredicate::sgt && !beginBound.isNegative() &&
      endBound.sle(beginBound) && indVarIncrement.isNegative()) {
    if (!endBound.isNegative())
      range = beginBound.getZExtValue() - endBound.getZExtValue();
    // Expressions like >= 0 are converted into > -1, so we handle this case.
    else if (endBound.isAllOnes())
      range = beginBound.getZExtValue() + 1;
  }
  // for (signless i = N; i == N; i += S) with S != 0
  if (predicate == comb::ICmpPredicate::eq && indVarIncrement != 0 &&
      beginBound == endBound) {
    tripCount = 1;
    return true;
  }

  if (!range.has_value())
    return failMatch("unsupported loop bounds");

  // Calculate the trip count as ceil(range/stride)
  unsigned stride = indVarIncrement.abs().getZExtValue();
  tripCount = (*range + stride - 1) / stride;
  // For now don't expand more than 1k iterations.
  if (tripCount >= 1024)
    return failMatch("unsupported loop bounds");

  return true;
}

/// Forward values defined in the loop through block arguments outside it.
/// Early-exit blocks need the values from the iteration that took the exit,
/// rather than values defined in the final, non-executing loop header.
static LogicalResult closeLoopValues(CFGLoop &loop) {
  auto &region = *loop.getHeader()->getParent();
  SmallVector<Value> values;
  for (auto &block : region) {
    if (!loop.contains(&block))
      continue;
    llvm::append_range(values, block.getArguments());
    for (auto &op : block)
      llvm::append_range(values, op.getResults());
  }

  SmallVector<std::pair<Value, SmallSetVector<Block *, 8>>> escaping;
  for (auto value : values) {
    SmallSetVector<Block *, 8> blocks;
    for (auto &use : value.getUses()) {
      auto *block =
          region.findAncestorBlockInRegion(*use.getOwner()->getBlock());
      if (block && !loop.contains(block))
        blocks.insert(block);
    }
    // Walk backwards to the loop, including intermediate blocks and cycles.
    for (unsigned i = 0; i < blocks.size(); ++i)
      for (auto *pred : blocks[i]->getPredecessors())
        if (!loop.contains(pred))
          blocks.insert(pred);

    // Check all required edges before modifying any blocks. Process exits may
    // suspend execution instead of using an extensible branch interface.
    for (auto *block : blocks)
      for (auto &edge : block->getUses())
        if (!isa<BranchOpInterface>(edge.getOwner()))
          return failure();
    if (!blocks.empty())
      escaping.emplace_back(value, std::move(blocks));
  }

  for (auto &[value, blocks] : escaping) {
    DenseMap<Block *, BlockArgument> arguments;
    for (auto *block : blocks)
      arguments[block] = block->addArgument(value.getType(), value.getLoc());
    for (auto &use : llvm::make_early_inc_range(value.getUses())) {
      auto *block =
          region.findAncestorBlockInRegion(*use.getOwner()->getBlock());
      if (auto arg = arguments.lookup(block))
        use.set(arg);
    }
    for (auto *block : blocks)
      for (auto &edge : block->getUses()) {
        auto branch = cast<BranchOpInterface>(edge.getOwner());
        Value incoming = arguments.lookup(branch->getBlock());
        branch.getSuccessorOperands(edge.getOperandNumber())
            .append(incoming ? incoming : value);
      }
  }
  return success();
}

/// Unroll the loop by cloning its body blocks and replacing the induction
/// variable with constant iteration indices.
void Loop::unroll(CFGLoopInfo &cfgLoopInfo) {
  LLVM_DEBUG(llvm::dbgs() << "- Unrolling loop " << *this << "\n");
  UnusedOpPruner pruner;
  if ((hasEarlyExits || preserveCondition) &&
      failed(closeLoopValues(cfgLoop))) {
    failMatch("cannot forward values outside loop");
    return;
  }

  // Sort the blocks in the body. This is not strictly necessary, but makes the
  // pass a lot easier to reason about in tests.
  auto *header = cfgLoop.getHeader();
  SmallVector<Block *> orderedBody;
  SmallPtrSet<Block *, 8> originalBlocks;
  for (auto &block : *header->getParent())
    if (cfgLoop.contains(&block)) {
      orderedBody.push_back(&block);
      originalBlocks.insert(&block);
    }

  // Copy the loop body for every iteration of the loop.
  SmallVector<Block *> latches;
  cfgLoop.getLoopLatches(latches);
  OpBuilder builder(indVar.getContext());
  auto indValue = beginBound;
  for (unsigned trip = 0; trip < tripCount; ++trip) {
    // Clone the loop body.
    IRMapping mapper;
    cloneBlocks(orderedBody, *header->getParent(), header->getIterator(),
                mapper);
    auto *clonedHeader = mapper.lookup(header);

    // Replace the induction variable with the concrete value.
    auto iterIndVar = mapper.lookup(indVar);
    pruner.eraseLaterIfUnused(iterIndVar);
    builder.setInsertionPointAfterValue(iterIndVar);
    iterIndVar.replaceAllUsesWith(
        hw::ConstantOp::create(builder, iterIndVar.getLoc(), indValue));

    // Update all edges to the original loop header to point to the cloned loop
    // header. Leave every original back-edge untouched. Previously cloned
    // back-edges now lead to this iteration even though those blocks have
    // already been added to the loop analysis.
    for (auto &blockOperand : llvm::make_early_inc_range(header->getUses()))
      if (!originalBlocks.contains(blockOperand.getOwner()->getBlock()))
        blockOperand.set(clonedHeader);

    // Update all cloned back-edges to point to the original loop header,
    // i.e. the next iteration, instead of the cloned loop header.
    for (auto *latch : latches)
      for (auto &blockOperand :
           mapper.lookup(latch)->getTerminator()->getBlockOperands())
        if (blockOperand.get() == clonedHeader)
          blockOperand.set(header);

    // A compound condition can stop before the selected bound, so preserve it
    // in every executing iteration. Otherwise this bounded exit is known not
    // to be taken. Other early exits remain conditional in either case.
    if (!preserveCondition) {
      auto exitBranchOp =
          cast<cf::CondBranchOp>(mapper.lookup(exitEdge->getOwner()));
      Block *continueDest = exitBranchOp.getTrueDest();
      ValueRange continueDestOperands = exitBranchOp.getTrueDestOperands();
      if (exitEdge->getOperandNumber() == 0) {
        continueDest = exitBranchOp.getFalseDest();
        continueDestOperands = exitBranchOp.getFalseDestOperands();
      }
      builder.setInsertionPoint(exitBranchOp);
      cf::BranchOp::create(builder, exitBranchOp.getLoc(), continueDest,
                           continueDestOperands);
      pruner.eraseLaterIfUnused(exitBranchOp.getOperands());
      exitBranchOp.erase();
    }

    // Add the new blocks to the loop body.
    for (auto *block : orderedBody) {
      auto *newBlock = mapper.lookup(block);
      cfgLoop.addBasicBlockToLoop(newBlock, cfgLoopInfo);
    }

    // Increment the induction variable value.
    if (formal)
      indValue = indVarValues[trip + 1];
    else
      indValue += indVarIncrement;
  }

  // Now that the loop body has been cloned once for each trip throughout the
  // loop, we can clean up the final iteration by always breaking out of the
  // loop. Start by replacing the induction variable with the final value.
  pruner.eraseLaterIfUnused(indVar);
  builder.setInsertionPointAfterValue(indVar);
  indVar.replaceAllUsesWith(
      hw::ConstantOp::create(builder, indVar.getLoc(), indValue));
  indVar = {};

  // Remove the continue edge of the exit branch in the loop body, since we
  // statically know that the loop will exit.
  auto exitBranchOp = cast<cf::CondBranchOp>(exitEdge->getOwner());
  Block *exitDest = exitBranchOp.getTrueDest();
  ValueRange exitDestOperands = exitBranchOp.getTrueDestOperands();
  if (exitEdge->getOperandNumber() == 1) {
    exitDest = exitBranchOp.getFalseDest();
    exitDestOperands = exitBranchOp.getFalseDestOperands();
  }
  builder.setInsertionPoint(exitBranchOp);
  cf::BranchOp::create(builder, exitBranchOp.getLoc(), exitDest,
                       exitDestOperands);
  pruner.eraseLaterIfUnused(exitBranchOp.getOperands());
  exitBranchOp.erase();
  exitEdge = nullptr;

  // Prune any body blocks that have become unreachable.
  auto &region = *header->getParent();
  SmallPtrSet<Block *, 8> reachable;
  SmallVector<Block *> worklist;
  reachable.insert(&region.front());
  worklist.push_back(&region.front());
  while (!worklist.empty())
    for (auto *succ : worklist.pop_back_val()->getSuccessors())
      if (reachable.insert(succ).second)
        worklist.push_back(succ);

  SmallVector<Block *> deadBlocks;
  for (auto &block : region) {
    if (reachable.contains(&block))
      continue;
    block.dropAllDefinedValueUses();
    deadBlocks.push_back(&block);
  }

  for (auto *block : deadBlocks) {
    cfgLoopInfo.removeBlock(block);
    block->erase();
  }

  // Remove any unused operations and block arguments.
  pruner.eraseNow();

  // Collapse trivial branches to avoid carrying a lot of useless blocks around
  // especially when unrolling nested loops.
  for (auto &block : *header->getParent()) {
    if (!cfgLoop.contains(&block))
      continue;
    while (true) {
      auto branchOp = dyn_cast<cf::BranchOp>(block.getTerminator());
      if (!branchOp)
        break;
      auto *otherBlock = branchOp.getDest();
      if (!cfgLoop.contains(otherBlock) || !otherBlock->getSinglePredecessor())
        break;
      for (auto [blockArg, branchArg] :
           llvm::zip(otherBlock->getArguments(), branchOp.getDestOperands()))
        blockArg.replaceAllUsesWith(branchArg);
      block.getOperations().splice(branchOp->getIterator(),
                                   otherBlock->getOperations());
      branchOp.erase();
      cfgLoopInfo.removeBlock(otherBlock);
      otherBlock->erase();
    }
  }
}

//===----------------------------------------------------------------------===//
// Pass Infrastructure
//===----------------------------------------------------------------------===//

namespace {
struct LoopUnroller {
  explicit LoopUnroller(bool formal = false) : formal(formal) {}
  void run(Region &region);
  bool unrollLoops(Region &region);
  bool formal;
};

struct UnrollLoopsPass
    : public llhd::impl::UnrollLoopsPassBase<UnrollLoopsPass> {
  void runOnOperation() override;
};
} // namespace

void UnrollLoopsPass::runOnOperation() {
  for (auto op : getOperation().getOps<CombinationalOp>())
    LoopUnroller().run(op.getBody());
}

void LoopUnroller::run(Region &region) {
  // Unrolling a loop may open up opportunities to unroll its nested loops.
  // Iterate until all possible loops are unrolled or the limit is reached.
  for (unsigned i = 0; i < 16; ++i)
    if (!unrollLoops(region))
      break;
}

bool LoopUnroller::unrollLoops(Region &region) {
  // There's nothing to do if we only have a single block. MLIR even refuses to
  // compute a dominator tree in that case.
  if (region.empty() || region.hasOneBlock())
    return false;

  // Find the loops.
  LLVM_DEBUG(llvm::dbgs() << "Unrolling loops in "
                          << region.getParentOp()->getLoc() << "\n");
  DominanceInfo domInfo(region.getParentOp());
  CFGLoopInfo cfgLoopInfo(domInfo.getDomTree(&region));

  // Formal loops may have multiple back-edges with the same counter recurrence.
  // Each latch block must still belong to a single loop header. Create a
  // data structure for each loop we can potentially unroll. The loops are in
  // preorder, with outer loops appearing before their child loops.
  SmallVector<Loop> loops;
  bool retry = false;
  for (auto *cfgLoop : cfgLoopInfo.getLoopsInPreorder()) {
    // Keep the ordinary unroller's single-latch matching rules.
    auto *header = cfgLoop->getHeader();
    if (!formal && !cfgLoop->getLoopLatch())
      continue;

    LLVM_DEBUG({
      llvm::dbgs() << "- ";
      cfgLoop->print(llvm::dbgs(), false, false);
      llvm::dbgs() << "\n";
    });
    Loop loop(loops.size(), *cfgLoop, formal);

    // Ensure that the header block is only a header for the current loop. This
    // simplifies unrolling.
    auto *parent = cfgLoop->getParentLoop();
    while (parent && parent->getHeader() != header)
      parent = parent->getParentLoop();
    if (parent) {
      loop.failMatch("header block shared across multiple loops");
      continue;
    }

    // Ensure that no latch is shared with an enclosing loop.
    SmallVector<Block *> latches;
    cfgLoop->getLoopLatches(latches);
    if (llvm::any_of(latches, [&](Block *latch) {
          auto *parent = cfgLoop->getParentLoop();
          while (parent && !parent->isLoopLatch(latch))
            parent = parent->getParentLoop();
          return parent != nullptr;
        })) {
      loop.failMatch("latch block shared across multiple loops");
      continue;
    }

    // Check if the loop body matches the pattern we can unroll.
    if (loop.match(domInfo)) {
      loops.push_back(std::move(loop));
      continue;
    }

    // If an enclosing loop is unrolled, we retry the unrolling.
    retry |= llvm::any_of(loops, [&](const Loop &other) {
      return other.cfgLoop.contains(cfgLoop);
    });
  }

  if (loops.empty())
    return false;

  // Dump some debugging information about the loops we've found.
  LLVM_DEBUG({
    auto &os = llvm::dbgs();
    for (auto &loop : loops) {
      os << "- Loop " << loop << ":\n";
      os << "  - ";
      loop.cfgLoop.print(os, false, false);
      os << "\n";
      os << "  - Exit: ";
      loop.exitEdge->get()->printAsOperand(os);
      os << " if ";
      if (loop.exitInverted)
        os << "not ";
      os << loop.exitCondition;
      os << "\n";
      os << "  - Induction variable: ";
      loop.indVar.printAsOperand(os, OpPrintingFlags().useLocalScope());
      os << ", from " << loop.beginBound;
      if (!loop.formal)
        os << ", while " << loop.predicate << " " << loop.endBound
           << ", increment " << loop.indVarIncrement;
      os << "\n";
      os << "  - Trip count: " << loop.tripCount << "\n";
    }
  });

  // Unroll the loops. Handling the loops in reverse unrolls inner loops before
  // their parent loops.
  for (auto &loop : llvm::reverse(loops))
    loop.unroll(cfgLoopInfo);

  return retry;
}

void circt::llhd::unrollFormalLoops(Operation *op) {
  op->walk([](Operation *nested) {
    if (isa<ProcessOp, CombinationalOp>(nested))
      LoopUnroller(true).run(nested->getRegion(0));
  });
}
