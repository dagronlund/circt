// REQUIRES: slang, verilator
// RUN: split-file %s %t
// RUN: circt-verilog --ir-hw --top=checks %CIRCT_SOURCE%/test/circt-verilog/formal-aggregate-drivers.sv %t/checks.sv -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core -o %t.formal.mlir
// RUN: circt-opt %t.formal.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module checks --Mdir %t.model %t.sv %S/Inputs/aggregate-drivers.cpp > %t.build.log 2>&1
// RUN: %t.model/Vchecks | FileCheck %s
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core -o %t.two-valued.mlir
// RUN: circt-opt %t.two-valued.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.two-valued.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module checks --Mdir %t.two-valued.model %t.two-valued.sv %S/Inputs/aggregate-drivers.cpp > %t.two-valued.build.log 2>&1
// RUN: %t.two-valued.model/Vchecks | FileCheck %s
// RUN: circt-verilog --ir-llhd --top=checks %CIRCT_SOURCE%/test/circt-verilog/formal-aggregate-drivers.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-opt %t.direct.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.direct.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module checks --Mdir %t.direct.model %t.direct.sv %S/Inputs/aggregate-drivers.cpp > %t.direct.build.log 2>&1
// RUN: %t.direct.model/Vchecks | FileCheck %s
// CHECK: 262144 aggregate driver transitions and clock timing checks passed

//--- checks.sv
module checks(input logic clk, input logic [1:0] enable,
              input logic [31:0] a, b, input logic [15:0] d,
              output logic [31:0] comb_q, output logic [15:0] struct_q);
  conditional_words comb_dut(.enable(enable), .a(a), .b(b), .q(comb_q));
  struct_words struct_dut(.clk(clk), .d(d), .q(struct_q));
endmodule
