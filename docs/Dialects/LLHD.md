# LLHD Dialect

This dialect provides operations and types to interact with an event queue in an event-based simulation.
It describes how signals change over time in reaction to changes in other signals and physical time advancing.
Established hardware description languages such as SystemVerilog and VHDL use an event queue as their programming model to describe combinational and sequential logic, as well as test harnesses and test benches.

[TOC]

## Rationale

### Register Reset Values

Resets are problematic since Verilog forces designers to describe them as edge-sensitive triggers.
This does _not_ match the async resets found on almost all standard cell flip-flops, which are level-sensitive.
Therefore a pass lowering from Verilog-style processes to a structural register such as `seq.compreg` would have to verify that the reset value is a constant in order to make the mapping from edge-sensitive Verilog description to level-sensitive standard cell valid.

In practice, designers commonly implement registers encapsulated in a Verilog module, with the reset value being provided as a module input
port.
This makes determining whether the input is a constant much more difficult.
Most commercial tools relax this constraint and simply map the edge-sensitive reset to a level-sensitive one.
This does not preserve the semantics of the input, which is bad.
Most synthesis tools will then go ahead and fail during synthesis if a register's reset value does not end up being a constant value.

Therefore the Deseq pass does not verify that a register's reset value is a constant.
Instead, it applies the same transform from edge-sensitive to level-sensitive reset as most other tools.

## Types

[include "Dialects/LLHDTypes.md"]

## Attributes

[include "Dialects/LLHDAttributes.md"]

## Operations

[include "Dialects/LLHDOps.md"]

## Passes

[include "LLHDPasses.md"]

## Strict formal lowering

`circt-opt --lower-llhd-formal-to-core` lowers supported verification-bearing
LLHD under a synchronous, two-state formal interpretation. The initial subset
supports Boolean checks in acyclic combinational regions. Guards are combined
with existing enables; covers seek enabled predicates rather than implications.
SSA values preserve statement order and merge values with muxes. Verification
operations retain their global effect classification.

Conversion is transactional. Successful output contains only HW, Seq, Comb,
builtin containers, and the six Boolean assert/assume/cover operations including
their clocked variants. Unsupported effects, procedural/temporal constructs,
types, drivers, or combinational dependency cycles fail instead of leaving a
partially lowered design. Module output dependency summaries preserve register
boundaries across instances. This pass does not require or run
`comb-assume-two-valued`; callers choose their handling of X/Z semantics.

Single-edge sequential processes extract registers and immediate checks from
the same edge-specialized SSA computation. Checks observe current state before
simultaneous nonblocking updates; blocking local assignments affect later checks.
Both positive and negative edges are supported. Checks before the first wait,
unrelated clocks, general process loops, and event-region dependencies fail.
Property-only trampoline/self-loop wrappers are recognized separately. Only
scheduled nonblocking drives may commute across verification observations.

Constant native LLHD signal initial values become register presets. Frontend
integer variables carry `llhd.explicit_init` or `llhd.unconstrained` provenance;
implicit scheduling zeros and initial wait placeholders do not constrain state.
Explicit constant initialization survives the ordinary frontend pipeline.
Nonconstant formal register initialization is rejected. Legacy IR without
provenance cannot recover source initialization that was already discarded.

The temporal subset supports Boolean expressions and implication, explicit
clock scopes/atoms, fixed delays, finite concatenation, fixed consecutive
repetition, and sampled history. Concatenation overlaps endpoints; next-cycle
implication uses `concat(a, delay(true, 1, 0))`. Pipelines track every overlapping
attempt. Assert/assume monitors check each required sample; covers report completed
non-vacuous matches. Pending bits start false, while sampled history remains
unconstrained initially. `max-monitor-depth` defaults to 256; overflow and
unsupported, variable, or unbounded temporal forms fail.

For temporal checks, the existing enable denotes `disable iff`; its negation
asynchronously clears active attempts, including pulses between sampling edges.
This differs from procedural reachability. Guarded temporal CFG checks requiring
separate start/disable predicates are rejected. Pending attempts at a bounded
trace's end remain state rather than automatically becoming failures.

The result is hardware, not a proof or a checking problem. Backends must support
the remaining clocks, initialization, asynchronous reset, and cover operations.
The unchanged CIRCT BMC register externalizer rejects asynchronous reset;
backend compatibility is checked independently of formal IR legality.

Before cycle analysis, packed-vector extracts are distributed through bitwise
OR, then folded through concatenations and constants. This exposes relevant
lanes without discarding full packed outputs. The OR's `twoState` flag and
attributes are retained. OR slice expansion is bounded to 65,536 cloned
operations; exceeding the budget fails. Genuine feedback remains an error.
