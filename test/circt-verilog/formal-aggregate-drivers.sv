// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=preset
// REQUIRES: slang

// Each process updates a distinct nested array element. Factor the conditional
// whole-array updates before checking that each lane has a unique driver.
// CHECK-LABEL: hw.module @conditional_words
// CHECK-DAG: [[FALSE:%.+]] = hw.constant false
// CHECK-DAG: [[TRUE:%.+]] = hw.constant true
// CHECK-DAG: [[A0:%.+]] = hw.array_get %a{{.}}[[FALSE]]
// CHECK-DAG: [[B0:%.+]] = hw.array_get %b{{.}}[[FALSE]]
// CHECK-DAG: [[EN0:%.+]] = comb.extract %enable from 0 : (i2) -> i1
// CHECK-DAG: [[Q0:%.+]] = comb.mux{{( bin)?}} [[EN0]], [[B0]], [[A0]] : !hw.array<2xi8>
// CHECK-DAG: [[A1:%.+]] = hw.array_get %a{{.}}[[TRUE]]
// CHECK-DAG: [[B1:%.+]] = hw.array_get %b{{.}}[[TRUE]]
// CHECK-DAG: [[EN1:%.+]] = comb.extract %enable from 1 : (i2) -> i1
// CHECK-DAG: [[Q1:%.+]] = comb.mux{{( bin)?}} [[EN1]], [[B1]], [[A1]] : !hw.array<2xi8>
// CHECK-DAG: [[Q:%.+]] = hw.array_create [[Q1]], [[Q0]] : !hw.array<2xi8>
// CHECK: hw.output [[Q]] : !hw.array<2xarray<2xi8>>
module conditional_words(input logic [1:0] enable,
                         input logic [1:0][1:0][7:0] a, b,
                         output logic [1:0][1:0][7:0] q);
  for (genvar i = 0; i < 2; i++) begin: gen_word
    always_comb begin
      q[i] = a[i];
      if (enable[i])
        q[i] = b[i];
    end
  end
endmodule

// Ordinary extraction hides the disjoint word writes in whole-struct registers.
// Split through the struct, array, and inner structs to recover independent state.
// CHECK-LABEL: hw.module @struct_words
// CHECK: seq.firreg
// CHECK: hw.output {{%.+}} : i16
module struct_words(input logic clk, input logic [1:0][7:0] d,
                    output logic [15:0] q);
  typedef struct packed {logic [3:0] a, b;} s_t;
  typedef struct packed {s_t [1:0] words;} p_t;
  p_t p;
  for (genvar i = 0; i < 2; i++) begin: gen_word
    always_ff @(posedge clk) p.words[i] <= d[i];
  end
  always_comb q = p;
endmodule
