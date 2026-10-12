// REQUIRES: slang, verilator
// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %CIRCT_SOURCE%/test/circt-verilog/formal-packed-carry.sv -o %t.frontend.mlir
// RUN: circt-opt %t.frontend.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.frontend.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.frontend.model %t.frontend.sv %S/Inputs/packed-carry-driver.cpp > %t.frontend.build.log 2>&1
// RUN: %t.frontend.model/Vtop | FileCheck %s
// RUN: circt-verilog --ir-llhd %CIRCT_SOURCE%/test/circt-verilog/formal-packed-carry.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-opt %t.direct.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.direct.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.direct.model %t.direct.sv %S/Inputs/packed-carry-driver.cpp > %t.direct.build.log 2>&1
// RUN: %t.direct.model/Vtop | FileCheck %s
// RUN: circt-verilog --ir-hw %CIRCT_SOURCE%/test/circt-verilog/formal-packed-carry.sv | circt-opt --lower-llhd-formal-to-core -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.hw.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.hw.model %t.hw.sv %S/Inputs/packed-carry-driver.cpp > %t.hw.build.log 2>&1
// RUN: %t.hw.model/Vtop | FileCheck %s
// CHECK: 64 carry combinations and synchronous timing checks passed
module {}
