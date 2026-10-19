// REQUIRES: slang, libz3, circt-bmc-jit
// RUN: split-file %s %t
// RUN: circt-verilog --ir-hw --top=checks %CIRCT_SOURCE%/test/circt-verilog/formal-packed-cast.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core --hw-aggregate-to-comb --canonicalize --cse -o %t.formal.mlir
// RUN: circt-bmc %t.formal.mlir --module=checks -b 5 --shared-libs=%libz3 | FileCheck %s
// RUN: circt-verilog --ir-llhd --top=checks %CIRCT_SOURCE%/test/circt-verilog/formal-packed-cast.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core --hw-aggregate-to-comb --canonicalize --cse -o %t.direct.mlir
// RUN: circt-bmc %t.direct.mlir --module=checks -b 5 --shared-libs=%libz3 | FileCheck %s
// CHECK: Bound reached with no violations!

//--- checks.sv
// Check every initial state and mask history against the three-bit recurrence.
module checks(input logic clk, input logic [2:0] mask);
  wire [2:0] q;
  top dut(.*);
  logic [2:0] previous, previous_mask;
  bit valid = 0;
  always @(posedge clk) begin
    previous <= q;
    previous_mask <= mask;
    valid <= 1;
  end
  always_comb assert(!valid || q == (previous | previous_mask));
endmodule
