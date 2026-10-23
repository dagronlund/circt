// REQUIRES: slang, verilator
// RUN: circt-verilog --top top --ir-hw --lower-llhd-formal-to-core %CIRCT_SOURCE%/test/circt-verilog/formal-compound-loop-bound.sv -o %t.frontend.mlir
// RUN: circt-opt %t.frontend.mlir --lower-hw-to-sv --export-verilog -o /dev/null > %t.frontend.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.frontend.model %t.frontend.sv %S/Inputs/compound-loop-bound-driver.cpp > %t.frontend.build.log 2>&1
// RUN: %t.frontend.model/Vtop | FileCheck %s
// RUN: circt-verilog --top top --ir-llhd %CIRCT_SOURCE%/test/circt-verilog/formal-compound-loop-bound.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-opt %t.direct.mlir --lower-hw-to-sv --export-verilog -o /dev/null > %t.direct.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.direct.model %t.direct.sv %S/Inputs/compound-loop-bound-driver.cpp > %t.direct.build.log 2>&1
// RUN: %t.direct.model/Vtop | FileCheck %s
// RUN: circt-verilog --top guarded --ir-hw --lower-llhd-formal-to-core %CIRCT_SOURCE%/test/circt-verilog/formal-compound-loop-bound.sv -o %t.guarded.mlir
// RUN: circt-opt %t.guarded.mlir --lower-hw-to-sv --export-verilog -o /dev/null > %t.guarded.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module guarded --prefix Vtop -CFLAGS -DMAX_BITS=4 --Mdir %t.guarded.model %t.guarded.sv %S/Inputs/compound-loop-bound-driver.cpp > %t.guarded.build.log 2>&1
// RUN: %t.guarded.model/Vtop | FileCheck %s
// CHECK: All compound-bound input combinations and transitions passed
module {}
