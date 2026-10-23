// REQUIRES: slang, verilator
// RUN: circt-verilog --top top --ir-hw --lower-llhd-formal-to-core %CIRCT_SOURCE%/test/circt-verilog/formal-hierarchical-read.sv -o %t.frontend.mlir
// RUN: circt-opt %t.frontend.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.frontend.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.frontend.model %t.frontend.sv %S/Inputs/hierarchical-read-driver.cpp > %t.frontend.build.log 2>&1
// RUN: %t.frontend.model/Vtop | FileCheck %s
// RUN: circt-verilog --top top --ir-llhd %CIRCT_SOURCE%/test/circt-verilog/formal-hierarchical-read.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-opt %t.direct.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.direct.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.direct.model %t.direct.sv %S/Inputs/hierarchical-read-driver.cpp > %t.direct.build.log 2>&1
// RUN: %t.direct.model/Vtop | FileCheck %s
// RUN: circt-verilog --top nested_top --ir-hw --lower-llhd-formal-to-core %CIRCT_SOURCE%/test/circt-verilog/formal-hierarchical-read.sv -o %t.nested.mlir
// RUN: circt-opt %t.nested.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.nested.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module nested_top --prefix Vtop -CFLAGS -DDATA_WIDTH=2 --Mdir %t.nested.model %t.nested.sv %S/Inputs/hierarchical-read-driver.cpp > %t.nested.build.log 2>&1
// RUN: %t.nested.model/Vtop | FileCheck %s
// CHECK: All hierarchical register traces passed
module {}
