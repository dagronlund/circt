// REQUIRES: slang, libz3, circt-bmc-jit
// RUN: split-file %s %t
// RUN: circt-verilog --ir-hw --top=initial_correct %CIRCT_SOURCE%/test/circt-verilog/formal-symbolic-startup-state.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core -o %t.ir-hw.initial_correct.mlir
// RUN: circt-bmc %t.ir-hw.initial_correct.mlir --module=initial_correct -b 1 --shared-libs=%libz3 | FileCheck %s --check-prefix=PASS
// RUN: circt-verilog --ir-hw --top=feedback %CIRCT_SOURCE%/test/circt-verilog/formal-symbolic-startup-state.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core -o %t.ir-hw.feedback.mlir
// RUN: circt-bmc %t.ir-hw.feedback.mlir --module=feedback -b 5 --shared-libs=%libz3 | FileCheck %s --check-prefix=PASS
// RUN: circt-verilog --ir-hw --top=initial_not_constant %CIRCT_SOURCE%/test/circt-verilog/formal-symbolic-startup-state.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core -o %t.ir-hw.initial_not_constant.mlir
// RUN: circt-bmc %t.ir-hw.initial_not_constant.mlir --module=initial_not_constant -b 1 --shared-libs=%libz3 | FileCheck %s --check-prefix=FAIL
// RUN: circt-verilog --ir-hw --top=changing_input %CIRCT_SOURCE%/test/circt-verilog/formal-symbolic-startup-state.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core -o %t.ir-hw.changing_input.mlir
// RUN: circt-bmc %t.ir-hw.changing_input.mlir --module=changing_input -b 3 --shared-libs=%libz3 | FileCheck %s --check-prefix=FAIL
// RUN: circt-verilog --ir-llhd --top=initial_correct %CIRCT_SOURCE%/test/circt-verilog/formal-symbolic-startup-state.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core -o %t.ir-llhd.initial_correct.mlir
// RUN: circt-bmc %t.ir-llhd.initial_correct.mlir --module=initial_correct -b 1 --shared-libs=%libz3 | FileCheck %s --check-prefix=PASS
// RUN: circt-verilog --ir-llhd --top=feedback %CIRCT_SOURCE%/test/circt-verilog/formal-symbolic-startup-state.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core -o %t.ir-llhd.feedback.mlir
// RUN: circt-bmc %t.ir-llhd.feedback.mlir --module=feedback -b 5 --shared-libs=%libz3 | FileCheck %s --check-prefix=PASS
// RUN: circt-verilog --ir-llhd --top=initial_not_constant %CIRCT_SOURCE%/test/circt-verilog/formal-symbolic-startup-state.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core -o %t.ir-llhd.initial_not_constant.mlir
// RUN: circt-bmc %t.ir-llhd.initial_not_constant.mlir --module=initial_not_constant -b 1 --shared-libs=%libz3 | FileCheck %s --check-prefix=FAIL
// RUN: circt-verilog --ir-llhd --top=changing_input %CIRCT_SOURCE%/test/circt-verilog/formal-symbolic-startup-state.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core -o %t.ir-llhd.changing_input.mlir
// RUN: circt-bmc %t.ir-llhd.changing_input.mlir --module=changing_input -b 3 --shared-libs=%libz3 | FileCheck %s --check-prefix=FAIL
// PASS: Bound reached with no violations!
// FAIL: Assertion can be violated!

//--- checks.sv
// The initial constraint must preserve the startup input relationship.
module initial_correct(input logic clk, enable, input bit [7:0] init_value);
  wire [7:0] q;
  top dut(.*);
  bit started = 0;
  always @(posedge clk) started <= 1;
  always_comb assert(started || q == (8'h01 ^ init_value));
endmodule

// Removing the declaration preset must leave all 256 startup inputs feasible.
module initial_not_constant(input logic clk, input bit [7:0] init_value);
  wire [7:0] q;
  top dut(.clk, .enable(1'b0), .init_value, .q);
  always_comb assert(init_value == 0);
endmodule

// With enable low, changing the input after the first edge must be feasible
// without changing the state. A continuing equality would suppress this failure.
module changing_input(input logic clk, input bit [7:0] init_value);
  wire [7:0] q;
  top dut(.clk, .enable(1'b0), .init_value, .q);
  always_comb assert(q == (8'h01 ^ init_value));
endmodule

// Check enabled transitions against an independent expression of the LFSR.
module feedback(input logic clk, enable, input bit [7:0] init_value);
  wire [7:0] q;
  top dut(.*);
  bit valid = 0;
  logic previous_enable;
  logic [7:0] previous;
  always @(posedge clk) begin
    previous <= q;
    previous_enable <= enable;
    valid <= 1;
  end
  wire [7:0] next_value = (previous << 1) | {7'b0, ^(previous & 8'ha0)};
  always_comb
    assert(!valid || q == (previous_enable ? next_value : previous));
endmodule
