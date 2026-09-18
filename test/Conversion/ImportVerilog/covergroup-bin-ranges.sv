// RUN: circt-verilog --ir-moore %s | circt-opt --verify-roundtrip | FileCheck %s
// RUN: circt-verilog --ir-llhd %s | FileCheck %s --check-prefix=CORE
// RUN: circt-verilog --ir-hw %s | FileCheck %s --check-prefix=CORE
// REQUIRES: slang

// CORE-NOT: moore.
// CORE: hw.module @top
// CORE-NOT: moore.
// CORE: hw.module @signed_ranges
// CORE-NOT: moore.
// CORE: hw.module @wide_ranges
// CORE-NOT: moore.

// The lower bound must not truncate to zero: no two-bit value can hit this bin.
module top(input bit clk, input bit [1:0] value);
  covergroup cg @(posedge clk);
    coverpoint value {
      illegal_bins above_limit = {[4:$]};
    }
  endgroup
  cg coverage = new;
endmodule
// CHECK-LABEL: moore.covergroup.decl @"top::cg"
// CHECK: %[[FOUR:.*]] = moore.constant 4 : l33
// CHECK: %[[VALUE:.*]] = moore.zext {{.*}} : l2 -> l33
// CHECK: %[[CMP:.*]] = moore.sge %[[VALUE]], %[[FOUR]] : l33
// CHECK: moore.logic_to_int %[[CMP]] : l1
// CHECK: moore.coverbin "value" "above_limit" if {{.*}} {illegal}

// Signed bounds, a lower unbounded endpoint, finite ranges, and a union of
// ranges and singleton values all use the same scalar-bin predicate.
module signed_ranges;
  covergroup cg with function sample(logic signed [2:0] value);
    coverpoint value {
      bins negative = {[$:-1]};
      bins middle = {[-1:1], 3};
      illegal_bins below_limit = {[$:-5]};
      bins positive = {[1:$]};
    }
  endgroup
  cg coverage = new;
  initial coverage.sample(-1);
endmodule
// CHECK-LABEL: moore.covergroup.decl @"signed_ranges::cg"
// CHECK-DAG: %[[MINUS_FIVE:.*]] = moore.constant -5 : l33
// CHECK-DAG: moore.constant -1 : l33
// CHECK: moore.sext {{.*}} : l3 -> l33
// CHECK: moore.sle {{.*}} : l33
// CHECK: moore.coverbin "value" "negative"
// CHECK: moore.sge {{.*}} : l33
// CHECK: moore.sle {{.*}} : l33
// CHECK: moore.case_eq
// CHECK: moore.or
// CHECK: moore.coverbin "value" "middle"
// CHECK: moore.sle {{.*}}, %[[MINUS_FIVE]] : l33
// CHECK: moore.coverbin "value" "below_limit" if {{.*}} {illegal}
// CHECK: moore.sge {{.*}} : l33
// CHECK: moore.coverbin "value" "positive"

// Scalar ranges must not enumerate their members or sign-extend unsigned bounds.
module wide_ranges;
  covergroup cg with function sample(bit [64:0] value);
    coverpoint value {
      bins all_values = {[0:65'h1ffffffffffffffff]};
    }
  endgroup
  cg coverage = new;
  initial coverage.sample(0);
endmodule
// CHECK-LABEL: moore.covergroup.decl @"wide_ranges::cg"
// CHECK: %[[MAX:.*]] = moore.constant 36893488147419103231 : l66
// CHECK: moore.zext {{.*}} : l65 -> l66
// CHECK: moore.sge {{.*}} : l66
// CHECK: moore.sle {{.*}}, %[[MAX]] : l66
// CHECK: moore.coverbin "value" "all_values"
