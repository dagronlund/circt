// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=seq.
// REQUIRES: slang

// Whole-struct read-modify-write drives hide disjoint field assignments, and
// the updates to b contain another level of padding around individual bits.
// CHECK-LABEL: hw.module @top(in %data : i2, out q : i5)
// CHECK-DAG: [[PARITY:%.+]] = comb.parity{{( bin)?}} %data : i2
// CHECK-DAG: [[S:%.+]] = hw.struct_create ([[PARITY]], %data, %data) : !hw.struct<a: i1, b: i2, c: i2>
// CHECK-DAG: [[Q:%.+]] = hw.bitcast [[S]] : (!hw.struct<a: i1, b: i2, c: i2>) -> i5
// CHECK: hw.output [[Q]] : i5
module top(input logic [1:0] data, output logic [4:0] q);
  typedef struct packed {
    logic a;
    logic [1:0] b;
    logic [1:0] c;
  } struct_t;
  struct_t s;
  always_comb s.c = data;
  for (genvar i = 0; i < 2; i++) begin: gen_b
    always_comb s.b[i] = data[i];
  end
  always_comb s.a = ^data;
  always_comb q = s;
endmodule

// Continue through nested fields, using distinct data bits to check ordering.
// CHECK-LABEL: hw.module @nested_fields(in %data : i4, out q : i4)
// CHECK-DAG: [[A:%.+]] = comb.extract %data from 3 : (i4) -> i1
// CHECK-DAG: [[B:%.+]] = comb.extract %data from 0 : (i4) -> i2
// CHECK-DAG: [[C:%.+]] = comb.extract %data from 2 : (i4) -> i1
// CHECK-DAG: [[INNER:%.+]] = hw.struct_create ([[B]], [[C]]) : !hw.struct<b: i2, c: i1>
// CHECK-DAG: [[OUTER:%.+]] = hw.struct_create ([[A]], [[INNER]]) : !hw.struct<a: i1, inner: !hw.struct<b: i2, c: i1>>
// CHECK-DAG: [[Q:%.+]] = hw.bitcast [[OUTER]] : (!hw.struct<a: i1, inner: !hw.struct<b: i2, c: i1>>) -> i4
// CHECK: hw.output [[Q]] : i4
module nested_fields(input logic [3:0] data, output logic [3:0] q);
  typedef struct packed {
    logic [1:0] b;
    logic c;
  } inner_t;
  typedef struct packed {
    logic a;
    inner_t inner;
  } outer_t;
  outer_t s;
  for (genvar i = 0; i < 2; i++) begin: gen_b
    always_comb s.inner.b[i] = data[i];
  end
  always_comb s.inner.c = data[2];
  always_comb s.a = data[3];
  always_comb q = s;
endmodule
