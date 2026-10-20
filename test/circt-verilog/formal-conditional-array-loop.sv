// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// REQUIRES: slang

// Conditional writes in an unrolled loop must not leave aggregate feedback
// between iterations when every element is assigned on every control-flow path.
// CHECK-LABEL: hw.module @top(in %select_a : i1, in %a : !hw.array<2xi8>, in %b : !hw.array<2xi8>
// CHECK: [[Q:%.+]] = comb.mux{{( bin)?}} %select_a, %a, %b : !hw.array<2xi8>
// CHECK-NEXT: hw.output [[Q]] : !hw.array<2xi8>
module top(input logic select_a, input logic [1:0][7:0] a, b,
           output logic [1:0][7:0] q);
  always_comb begin
    for (logic [31:0] i = 0; i < 2; i++) begin
      if (select_a) begin
        q[i] = a[i];
      end else begin
        q[i] = b[i];
      end
    end
  end
endmodule
