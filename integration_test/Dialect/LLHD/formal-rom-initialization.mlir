// REQUIRES: slang, verilator
// RUN: circt-verilog --ir-hw %CIRCT_SOURCE%/test/circt-verilog/formal-rom-initialization.sv | circt-opt --lower-llhd-formal-to-core -o %t.formal.mlir
// RUN: circt-opt %t.formal.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.model %t.sv %S/Inputs/rom-initialization-driver.cpp > %t.build.log 2>&1
// RUN: %t.model/Vtop | FileCheck %s
// RUN: circt-verilog --ir-llhd %CIRCT_SOURCE%/test/circt-verilog/formal-rom-initialization.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-opt %t.direct.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.direct.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.direct.model %t.direct.sv %S/Inputs/rom-initialization-driver.cpp > %t.direct.build.log 2>&1
// RUN: %t.direct.model/Vtop | FileCheck %s
// CHECK: All four ROM entries and address transitions passed
module {}
