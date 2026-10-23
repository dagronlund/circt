// REQUIRES: slang, verilator
// RUN: circt-verilog --top top --ir-hw --lower-llhd-formal-to-core %CIRCT_SOURCE%/test/circt-verilog/formal-conditional-loop-break.sv -o %t.frontend.mlir
// RUN: circt-opt %t.frontend.mlir --lower-hw-to-sv --export-verilog -o /dev/null > %t.frontend.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.frontend.model %t.frontend.sv %S/Inputs/conditional-loop-break-driver.cpp > %t.frontend.build.log 2>&1
// RUN: %t.frontend.model/Vtop | FileCheck %s
// RUN: circt-verilog --top top --ir-llhd %CIRCT_SOURCE%/test/circt-verilog/formal-conditional-loop-break.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-opt %t.direct.mlir --lower-hw-to-sv --export-verilog -o /dev/null > %t.direct.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.direct.model %t.direct.sv %S/Inputs/conditional-loop-break-driver.cpp > %t.direct.build.log 2>&1
// RUN: %t.direct.model/Vtop | FileCheck %s
// CHECK: All conditional loop-break combinations passed
module {}
