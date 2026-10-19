// REQUIRES: slang, libz3, circt-bmc-jit
// RUN: split-file %s %t
// RUN: circt-verilog --ir-hw --top=checks %CIRCT_SOURCE%/test/circt-verilog/formal-startup-loop.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core -o %t.formal.mlir
// RUN: circt-bmc %t.formal.mlir --module=checks -b 5 --shared-libs=%libz3 | FileCheck %s
// RUN: circt-verilog --ir-llhd --top=checks %CIRCT_SOURCE%/test/circt-verilog/formal-startup-loop.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-bmc %t.direct.mlir --module=checks -b 5 --shared-libs=%libz3 | FileCheck %s
// CHECK: Bound reached with no violations!

//--- checks.sv
// Compare both startup values and every enabled/held transition against
// independent reference registers, using a different expression of the LFSR.
module checks(input logic clk, enable);
  wire [7:0] four, three;
  top dut_four(.clk, .enable, .q(four));
  three_iterations dut_three(.clk, .enable, .q(three));
  bit [7:0] expected_four = 8'h01;
  bit [7:0] expected_three = 8'hab;
  always @(posedge clk) if (enable) begin
    expected_four <= (expected_four << 1) | {7'b0, ^(expected_four & 8'ha0)};
    expected_three <= (expected_three << 1) | {7'b0, ^(expected_three & 8'ha0)};
  end
  always_comb assert(four == expected_four && three == expected_three);
endmodule
