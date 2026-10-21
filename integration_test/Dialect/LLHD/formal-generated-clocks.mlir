// REQUIRES: slang, verilator
// RUN: split-file %s %t
// RUN: circt-verilog --ir-hw --top=checks %CIRCT_SOURCE%/test/circt-verilog/formal-generated-clocks.sv %t/checks.sv -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core -o %t.formal.mlir
// RUN: circt-opt %t.formal.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module checks --Mdir %t.model %t.sv %S/Inputs/generated-clocks.cpp > %t.build.log 2>&1
// RUN: %t.model/Vchecks | FileCheck %s
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core -o %t.two-valued.mlir
// RUN: circt-opt %t.two-valued.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.two-valued.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module checks --Mdir %t.two-valued.model %t.two-valued.sv %S/Inputs/generated-clocks.cpp > %t.two-valued.build.log 2>&1
// RUN: %t.two-valued.model/Vchecks | FileCheck %s
// RUN: circt-verilog --lower-llhd-formal-to-core --top=checks %CIRCT_SOURCE%/test/circt-verilog/formal-generated-clocks.sv %t/checks.sv -o %t.frontend.mlir
// RUN: circt-opt %t.frontend.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.frontend.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module checks --Mdir %t.frontend.model %t.frontend.sv %S/Inputs/generated-clocks.cpp > %t.frontend.build.log 2>&1
// RUN: %t.frontend.model/Vchecks | FileCheck %s
// RUN: circt-verilog --ir-llhd --top=checks %CIRCT_SOURCE%/test/circt-verilog/formal-generated-clocks.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-opt %t.direct.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.direct.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module checks --Mdir %t.direct.model %t.direct.sv %S/Inputs/generated-clocks.cpp > %t.direct.build.log 2>&1
// RUN: %t.direct.model/Vchecks | FileCheck %s
// CHECK: 65536 independent clock transitions and opposite-edge pipeline checks passed

//--- checks.sv
module checks(input logic clk, d, input logic [1:0] clocks,
              output logic phase_q, output logic [1:0] generated_q, initialized_q);
  wire q [2], initialized [2];
  opposite_edges phases(.clk(clk), .d(d), .q(phase_q));
  generated_clocks counters(.clk(clocks), .q(q));
  initialized_generated_clocks initialized_counters(.clk(clocks), .q(initialized));
  assign initialized_q = {initialized[1], initialized[0]};
  assign generated_q = {q[1], q[0]};
endmodule
