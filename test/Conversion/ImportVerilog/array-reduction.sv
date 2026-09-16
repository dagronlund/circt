// RUN: circt-verilog --ir-moore %s | FileCheck %s
// RUN: circt-verilog --ir-hw %s > /dev/null
// REQUIRES: slang

// The reduction operates on whole elements at their original width.
// CHECK-LABEL: @sum_array
// CHECK: %[[A:.*]] = moore.extract %a from 2 : uarray<3 x i8> -> i8
// CHECK: %[[B:.*]] = moore.extract %a from 1
// CHECK: %[[AB:.*]] = moore.add %[[A]], %[[B]] : i8
// CHECK: %[[C:.*]] = moore.extract %a from 0
// CHECK: %[[ABC:.*]] = moore.add %[[AB]], %[[C]] : i8
module sum_array(input bit [7:0] a[2:4], output bit [7:0] result);
  assign result = a.sum();
endmodule

// The reduction operates on whole elements at their original width.
// CHECK-LABEL: @product_array
// CHECK: %[[A:.*]] = moore.extract %a from 2 : uarray<3 x l8> -> l8
// CHECK: %[[B:.*]] = moore.extract %a from 1
// CHECK: %[[AB:.*]] = moore.mul %[[A]], %[[B]] : l8
// CHECK: %[[C:.*]] = moore.extract %a from 0
// CHECK: %[[ABC:.*]] = moore.mul %[[AB]], %[[C]] : l8
module product_array(input logic [7:0] a[4:2], output logic [7:0] result);
  assign result = a.product();
endmodule

// The reduction operates on whole elements at their original width.
// CHECK-LABEL: @and_array
// CHECK: %[[A:.*]] = moore.extract %a from 2 : uarray<3 x l8> -> l8
// CHECK: %[[B:.*]] = moore.extract %a from 1
// CHECK: %[[AB:.*]] = moore.and %[[A]], %[[B]] : l8
// CHECK: %[[C:.*]] = moore.extract %a from 0
// CHECK: %[[ABC:.*]] = moore.and %[[AB]], %[[C]] : l8
module and_array(input logic [7:0] a[3], output logic [7:0] result);
  assign result = a.and();
endmodule

// The reduction operates on whole elements at their original width.
// CHECK-LABEL: @or_array
// CHECK: %[[A:.*]] = moore.extract %a from 2 : uarray<3 x i8> -> i8
// CHECK: %[[B:.*]] = moore.extract %a from 1
// CHECK: %[[AB:.*]] = moore.or %[[A]], %[[B]] : i8
// CHECK: %[[C:.*]] = moore.extract %a from 0
// CHECK: %[[ABC:.*]] = moore.or %[[AB]], %[[C]] : i8
module or_array(input bit [7:0] a[3], output bit [7:0] result);
  assign result = a.or();
endmodule

// The reduction operates on whole elements at their original width.
// CHECK-LABEL: @xor_array
// CHECK: %[[A:.*]] = moore.extract %a from 2 : uarray<3 x l8> -> l8
// CHECK: %[[B:.*]] = moore.extract %a from 1
// CHECK: %[[AB:.*]] = moore.xor %[[A]], %[[B]] : l8
// CHECK: %[[C:.*]] = moore.extract %a from 0
// CHECK: %[[ABC:.*]] = moore.xor %[[AB]], %[[C]] : l8
module xor_array(input logic signed [7:0] a[3], output logic signed [7:0] result);
  assign result = a.xor();
endmodule

// A wider assignment must not change the width of the sum.
// CHECK-LABEL: @narrow_sum
// CHECK: moore.add {{.*}} : i8
// CHECK: moore.zext {{.*}} : i8 -> i32
module narrow_sum(input bit [7:0] a[2], output int unsigned result);
  assign result = a.sum();
endmodule

// A with expression controls the width of each reduction step.
// CHECK-LABEL: @wide_sum
// CHECK: moore.zext {{.*}} : i8 -> i32
// CHECK: moore.zext {{.*}} : i8 -> i32
// CHECK: moore.add {{.*}} : i32
module wide_sum(input bit [7:0] a[2], output int result);
  always_comb result = a.sum() with (int'(item));
endmodule

// A single-element reduction returns that element for every method.
// CHECK-LABEL: @singleton
// CHECK-NOT: moore.add
// CHECK-NOT: moore.mul
// CHECK-NOT: moore.and
// CHECK-NOT: moore.or
// CHECK-NOT: moore.xor
// CHECK: moore.output
module singleton(input bit [7:0] a[1],
                 output bit [7:0] s, p, a_result, o, x);
  assign s = a.sum();
  assign p = a.product();
  assign a_result = a.and();
  assign o = a.or();
  assign x = a.xor();
endmodule

// CHECK-LABEL: @product_with
// CHECK: moore.zext {{.*}} : i8 -> i32
// CHECK: moore.zext {{.*}} : i8 -> i32
// CHECK: moore.mul {{.*}} : i32
module product_with(input bit [7:0] a[2], output int result);
  always_comb result = a.product(element) with (int'(element));
endmodule

// CHECK-LABEL: @and_with
// CHECK: moore.zext {{.*}} : i8 -> i32
// CHECK: moore.zext {{.*}} : i8 -> i32
// CHECK: moore.and {{.*}} : i32
module and_with(input bit [7:0] a[2], output int result);
  always_comb result = a.and(element) with (int'(element));
endmodule

// CHECK-LABEL: @or_with
// CHECK: moore.zext {{.*}} : i8 -> i32
// CHECK: moore.zext {{.*}} : i8 -> i32
// CHECK: moore.or {{.*}} : i32
module or_with(input bit [7:0] a[2], output int result);
  always_comb result = a.or(element) with (int'(element));
endmodule

// CHECK-LABEL: @xor_with
// CHECK: moore.zext {{.*}} : i8 -> i32
// CHECK: moore.zext {{.*}} : i8 -> i32
// CHECK: moore.xor {{.*}} : i32
module xor_with(input bit [7:0] a[2], output int result);
  always_comb result = a.xor(element) with (int'(element));
endmodule

// Signed elements are sign-extended after the reduction.
// CHECK-LABEL: @signed_sum
// CHECK: moore.add {{.*}} : i8
// CHECK: moore.sext {{.*}} : i8 -> i32
module signed_sum(input bit signed [7:0] a[2], output int result);
  assign result = a.sum();
endmodule

// Packed integral elements must be converted to bit vectors for arithmetic.
typedef struct packed { bit [3:0] hi; bit [3:0] lo; } pair_t;
// CHECK-LABEL: @struct_sum
// CHECK: moore.packed_to_sbv
// CHECK: moore.packed_to_sbv
// CHECK: moore.add {{.*}} : i8
module struct_sum(input pair_t a[2], output pair_t result);
  assign result = a.sum();
endmodule
