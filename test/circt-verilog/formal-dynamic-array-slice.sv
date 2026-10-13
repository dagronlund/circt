// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --detect-memories=false --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// REQUIRES: slang

// A dynamic two-element write is a masked update of the whole register. Keep
// all initial state unconstrained, including the never-written high element.
// CHECK-LABEL: hw.module @top(
// CHECK-DAG: [[OLD:%.+]] = hw.bitcast [[STATE:%.+]] : (!hw.array<4xi8>) -> i32
// CHECK-DAG: [[D:%.+]] = hw.bitcast %d : (!hw.array<2xi8>) -> i16
// CHECK-DAG: [[OFFSET:%.+]] = comb.concat {{%.+}}, %offset, {{%.+}} : i28, i1, i3
// CHECK: comb.shl {{(bin )?}}{{%.+}}, [[OFFSET]] : i32
// CHECK: comb.and {{(bin )?}}[[OLD]], {{%.+}} : i32
// CHECK: comb.shl {{(bin )?}}{{%.+}}, [[OFFSET]] : i32
// CHECK: [[NEXT:%.+]] = hw.bitcast {{%.+}} : (i32) -> !hw.array<4xi8>
// CHECK: [[HOLD:%.+]] = comb.mux bin %enable, [[NEXT]], [[STATE]] : !hw.array<4xi8>
// CHECK-NEXT: [[STATE]] = seq.firreg [[HOLD]] clock {{%.+}}{{.*}} : !hw.array<4xi8>
// CHECK-NEXT: hw.output [[STATE]] : !hw.array<4xi8>
module top(input logic clk, enable, offset, input logic [1:0][7:0] d,
           output logic [3:0][7:0] q);
  logic [3:0][7:0] data;
  always_ff @(posedge clk) if (enable) data[offset +: 2] <= d;
  always_comb q = data;
endmodule

// Successive nonblocking writes must compose, with the later slice taking
// priority on overlapping elements while retaining the earlier disjoint ones.
// CHECK-LABEL: hw.module @multiple_slices(
// CHECK: comb.shl
// CHECK: [[HOLD:%.+]] = comb.mux bin %enable, {{%.+}}, [[STATE:%.+]] : !hw.array<4xi8>
// CHECK-NEXT: [[STATE]] = seq.firreg [[HOLD]] clock {{%.+}}{{.*}} : !hw.array<4xi8>
// CHECK-NEXT: hw.output [[STATE]] : !hw.array<4xi8>
module multiple_slices(input logic clk, enable, offset,
                       input logic [1:0][7:0] d, output logic [3:0][7:0] q);
  logic [3:0][7:0] data;
  always_ff @(posedge clk) if (enable) begin
    data[offset +: 2] <= d;
    data[1 +: 2] <= ~d;
  end
  always_comb q = data;
endmodule

// Ascending array indices must retain their frontend-defined physical order.
// CHECK-LABEL: hw.module @ascending(
// CHECK: [[HOLD:%.+]] = comb.mux bin %enable, {{%.+}}, [[STATE:%.+]] : !hw.array<4xi8>
// CHECK-NEXT: [[STATE]] = seq.firreg [[HOLD]] clock {{%.+}}{{.*}} : !hw.array<4xi8>
// CHECK-NEXT: hw.output [[STATE]] : !hw.array<4xi8>
module ascending(input logic clk, enable, offset,
                 input logic [1:0][7:0] d, output logic [0:3][7:0] q);
  logic [0:3][7:0] data;
  always_ff @(posedge clk) if (enable) data[offset +: 2] <= d;
  always_comb q = data;
endmodule

// Neither the array length nor the element width must be a power of two.
// CHECK-LABEL: hw.module @small_array(
// CHECK: comb.mul {{.*}} : i15
// CHECK: [[HOLD:%.+]] = comb.mux bin %enable, {{%.+}}, [[STATE:%.+]] : !hw.array<5xi3>
// CHECK-NEXT: [[STATE]] = seq.firreg [[HOLD]] clock {{%.+}}{{.*}} : !hw.array<5xi3>
// CHECK-NEXT: hw.output [[STATE]] : !hw.array<5xi3>
module small_array(input logic clk, enable, input logic [1:0] offset,
                   input logic [1:0][2:0] d, output logic [4:0][2:0] q);
  logic [4:0][2:0] data;
  always_ff @(posedge clk) if (enable) data[offset +: 2] <= d;
  always_comb q = data;
endmodule
