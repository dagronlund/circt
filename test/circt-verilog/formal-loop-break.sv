// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=seq.
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=seq.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=seq.
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=seq.
// REQUIRES: slang

// A bounded loop with an early exit implements a priority grant. Each break
// must use the counter from the iteration that took it, including in blocks
// outside the natural loop that perform a partial write before exiting.
// CHECK-LABEL: hw.module @top(in %request : i2, out grant : i2)
// CHECK: hw.output {{.*}} : i2
module top(input logic [1:0] request, output logic [1:0] grant);
  always_comb begin
    grant = '0;
    for (logic [1:0] i = 0; i < 2; i++) begin
      if (request[i]) begin
        grant[i] = 1'b1;
        break;
      end
    end
  end
endmodule
