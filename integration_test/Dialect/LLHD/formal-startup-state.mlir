// REQUIRES: slang, verilator
// RUN: circt-verilog --detect-memories=false --ir-hw %CIRCT_SOURCE%/test/circt-verilog/formal-startup-state.sv -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued -o %t.two-valued.mlir
// RUN: circt-opt %t.two-valued.mlir --lower-llhd-formal-to-core -o %t.formal.mlir
// RUN: circt-opt %t.formal.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.model %t.sv %S/Inputs/startup-state-driver.cpp > %t.build.log 2>&1
// RUN: %t.model/Vtop | FileCheck %s
// RUN: circt-verilog --ir-llhd %CIRCT_SOURCE%/test/circt-verilog/formal-startup-state.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-opt %t.direct.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.direct.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.direct.model %t.direct.sv %S/Inputs/startup-state-driver.cpp > %t.direct.build.log 2>&1
// RUN: %t.direct.model/Vtop | FileCheck %s
// CHECK: Startup value 0x5B and 1024 enabled feedback cycles passed
module {}
