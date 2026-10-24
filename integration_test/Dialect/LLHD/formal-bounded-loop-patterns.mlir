// REQUIRES: slang, verilator
// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %CIRCT_SOURCE%/test/circt-verilog/formal-bounded-loop-patterns.sv -o %t.frontend.mlir
// RUN: circt-opt %t.frontend.mlir --lower-hw-to-sv --export-verilog -o /dev/null > %t.frontend.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.frontend.model %t.frontend.sv %S/Inputs/bounded-loop-patterns-driver.cpp > %t.frontend.build.log 2>&1
// RUN: %t.frontend.model/Vtop | FileCheck %s
// RUN: circt-verilog --ir-llhd %CIRCT_SOURCE%/test/circt-verilog/formal-bounded-loop-patterns.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-opt %t.direct.mlir --lower-hw-to-sv --export-verilog -o /dev/null > %t.direct.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.direct.model %t.direct.sv %S/Inputs/bounded-loop-patterns-driver.cpp > %t.direct.build.log 2>&1
// RUN: %t.direct.model/Vtop | FileCheck %s
// CHECK: All bounded-loop combinations and transitions passed
module {}
