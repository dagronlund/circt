// REQUIRES: slang, verilator
// RUN: circt-verilog --detect-memories=false --ir-hw %CIRCT_SOURCE%/test/circt-verilog/formal-enabled-packed-array.sv -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core -o %t.formal.mlir
// RUN: circt-opt %t.formal.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.model %t.sv %S/Inputs/enabled-packed-array-driver.cpp > %t.build.log 2>&1
// RUN: %t.model/Vtop | FileCheck %s
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core -o %t.two-valued.mlir
// RUN: circt-opt %t.two-valued.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.two-valued.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.two-valued.model %t.two-valued.sv %S/Inputs/enabled-packed-array-driver.cpp > %t.two-valued.build.log 2>&1
// RUN: %t.two-valued.model/Vtop | FileCheck %s
// RUN: circt-verilog --ir-llhd %CIRCT_SOURCE%/test/circt-verilog/formal-enabled-packed-array.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-opt %t.direct.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.direct.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.direct.model %t.direct.sv %S/Inputs/enabled-packed-array-driver.cpp > %t.direct.build.log 2>&1
// RUN: %t.direct.model/Vtop | FileCheck %s
// CHECK: 524288 enabled packed array transitions and synchronous timing checks passed
module {}
