// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// REQUIRES: slang

// Ordinary register extraction pads each bit assignment with the other bit's
// old value. Recover the two independent registers from whole-integer drives.
// CHECK-LABEL: hw.module @packed_bits(in %clk : i1, in %d : i2
// CHECK-DAG: [[LOW:%.+]] = comb.extract %d from 0 : (i2) -> i1
// CHECK-DAG: [[HIGH:%.+]] = comb.extract %d from 1 : (i2) -> i1
// CHECK-DAG: [[CLK:%.+]] = seq.to_clock %clk
// CHECK-DAG: seq.firreg [[LOW]] clock [[CLK]] {{.*}}: i1
// CHECK-DAG: seq.firreg [[HIGH]] clock [[CLK]] {{.*}}: i1
// CHECK: hw.output {{%.+}} : i2
module packed_bits(input logic clk, input logic [1:0] d,
                   output logic [1:0] q);
  logic [1:0] value;
  for (genvar i = 0; i < 2; i++) begin: gen_value
    always_ff @(posedge clk) value[i] <= d[i];
  end
  always_comb q = value;
endmodule

// Whole-subarray and element assignments in different branches belong to one
// combinational driver, including after the frontend has lowered processes.
// CHECK-LABEL: hw.module @nested_branches(in %select : i1, in %a : i16, in %b : i16
// CHECK-NOT: seq.
// CHECK: comb.mux
// CHECK-NOT: seq.
// CHECK: hw.output {{%.+}} : !hw.array<2xarray<2xi8>>
module nested_branches(input logic select, input logic [15:0] a, b,
                       output logic [1:0][1:0][7:0] q);
  logic [1:0][1:0][7:0] data;
  always_comb begin
    data[0][0] = a[7:0];
    if (select) begin
      data[0][1] = b[7:0];
      data[1] = a;
    end else begin
      data[0][1] = a[15:8];
      data[1][0] = b[7:0];
      data[1][1] = b[15:8];
    end
  end
  always_comb q = data;
endmodule
