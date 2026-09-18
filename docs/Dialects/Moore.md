# Moore Dialect

This dialect provides operations and types to capture a SystemVerilog design after parsing, type checking, and elaboration.

[TOC]


## Rationale

The main goal of the `moore` dialect is to provide a set of operations and types for the `ImportVerilog` conversion to translate a fully parsed, type-checked, and elaborated Slang AST into MLIR operations.
See IEEE 1800-2017 for more details about SystemVerilog.
The dialect aims to faithfully capture the full SystemVerilog types and semantics, and provide a platform for transformation passes to resolve language quirks, analyze the design at a high level, and lower it to the core dialects.

In contrast, the `sv` dialect is geared towards emission of SystemVerilog text, and is focused on providing a good lowering target to allow for emission.
The `moore` and `sv` dialect may eventually converge into a single dialect.
As we are building out the Verilog frontend capabilities of CIRCT it is valuable to have a separate ingestion dialect, such that we do not have to make disruptive changes to the load-bearing `sv` dialect used in production.


## Functional coverage

Basic explicitly sampled SystemVerilog covergroups can be imported with
`circt-verilog --ir-moore`. A `moore.covergroup.decl` holds the sample inputs
and coverpoint expressions, `moore.covergroup.new` creates an independent
instance, and `moore.covergroup.sample` records a sample on that instance.
`moore.coverpoint` preserves automatic binning, signedness, and an optional
SystemVerilog `iff` condition.

The importer supports integral coverpoint expressions involving input sample
arguments, constants, and module variables captured when sampling. Scalar
explicit `bins` and `illegal_bins` with integral constant value lists are
represented by `moore.coverbin`. Their hit predicates include the coverpoint's
`iff` condition. Explicit bins replace automatic binning; illegal hits lower to
a runtime error, while ordinary hits update per-instance saturating counters.

Automatic crosses of integral coverpoints are represented by `moore.coverbin`
predicates for the Cartesian product of the target bins. Targets may use default
automatic bins or supported scalar explicit bins. Coverpoint `iff` conditions
are preserved, and illegal bins do not participate in the cross. Implicit
coverpoints and unnamed crosses are supported. Cross expansion is limited to
65,536 bins per cross.

Bin arrays, ranges, transitions, wildcard bins, default bins, `ignore_bins`,
bin-level conditions, and dynamic bin value sets are not yet supported. Enum
automatic bins, explicit cross bins, cross options and cross-level `iff`,
function calls in coverpoint expressions, inheritance, and coverage methods
other than `sample` also remain unsupported. Coverage reporting is not
implemented.


## Types

### Simple Bit Vector Type

The `moore.iN` and `moore.lN` types represent a two-valued or four-valued simple bit vector of width `N`.

| Verilog    | Moore Dialect |
| ---------- | ------------- |
| `bit`      | `!moore.i1`   |
| `logic`    | `!moore.l1`   |
| `reg`      | `!moore.l1`   |
| `byte`     | `!moore.i8`   |
| `shortint` | `!moore.i16`  |
| `int`      | `!moore.i32`  |
| `integer`  | `!moore.l32`  |
| `longint`  | `!moore.i64`  |
| `time`     | `!moore.l64`  |

### Event Type

The SystemVerilog `event` type is represented as a `!moore.i1` value.
A variable `event e` is lowered to the equivalent of `bit b`.
Triggering an event through `-> e` is lowered to the equivalent of `b = ~b`.
Waiting on an event through `@(e)` is lowered to the equivalent of `@(b)`.

### Default Values

Behavior of unconnected ports:

| Port Type        | Unconnected Behavior       |
| ---------------- | -------------------------- |
| Input (Net)      | High-impedance value ('Z)  |
| Input (Variable) | Default initial value      |
| Output           | No effect on Simulation    |
| Inout (Net)      | High-impedance value ('Z)  |
| Inout (Variable) | Default initial value      |
| Ref              | Cannot be left unconnected |
| Interconnect     | Cannot be left unconnected |
| Interface        | Cannot be left unconnected |

Uninitialized variables:

| Type                | Default initial value           |
| ------------------- | ------------------------------- |
| 4-state integral    | 'X                              |
| 2-state integral    | '0                              |
| `real`, `shortreal` | 0.0                             |
| Enumeration         | Base type default initial value |
| `string`            | "" (empty string)               |
| `event`             | New event                       |
| `class`             | `null`                          |
| `covergroup`        | `null`                          |
| `interface class`   | `null`                          |
| `chandle`           | `null`                          |
| `virtual interface` | `null`                          |

[include "Dialects/MooreTypes.md"]


## Operations

[include "Dialects/MooreOps.md"]
