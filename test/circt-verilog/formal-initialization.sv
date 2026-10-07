// RUN: circt-verilog --ir-hw %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd.
// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd.
// REQUIRES: slang
// An explicit initialization must survive the ordinary --ir-hw pipeline too.
// CHECK-LABEL: hw.module @initialization
// CHECK: seq.firreg {{.*}} preset 1 : i1
// CHECK: seq.firreg
// CHECK-NOT: preset
// CHECK: hw.output
module initialization(input bit clk, input bit d, output bit q, output bit r);
  bit state = 1'b1;
  assign q = state;
  always @(posedge clk) begin
    state <= d;
    r <= state;
  end
endmodule
