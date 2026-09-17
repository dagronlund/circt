// RUN: circt-verilog %s | FileCheck %s
// REQUIRES: slang
// UNSUPPORTED: valgrind

// Simplifying the dead loop must terminate and leave only the live loop.
// CHECK-LABEL: hw.module @top(out result : i3)
// CHECK: [[RESULT:%.+]] = llhd.process -> i3
// CHECK: comb.icmp slt
// CHECK-NOT: comb.icmp slt
// CHECK: llhd.wait yield
// CHECK: hw.output [[RESULT]] : i3
module top(output logic [2:0] result);
  always_comb begin
    result = '0;
    if (0) begin
      for (int n = 0; n < 1; n++) result[2 + n] = 1'b1;
    end else begin
      for (int n = 0; n < 1; n++) result[2 + n] = 1'b1;
    end
  end
endmodule
