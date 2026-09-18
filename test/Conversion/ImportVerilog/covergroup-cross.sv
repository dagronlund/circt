// RUN: circt-verilog --ir-moore %s | circt-opt --verify-roundtrip | FileCheck %s
// RUN: circt-verilog --ir-llhd %s | circt-opt --verify-roundtrip | FileCheck %s --check-prefix=CORE
// RUN: circt-verilog --ir-hw %s | circt-opt --verify-roundtrip | FileCheck %s --check-prefix=CORE
// REQUIRES: slang

// CORE-NOT: moore.
// CORE: hw.module @top
// CORE: llvm.mlir.constant(132 : i64)
// CORE-COUNT-6: llvm.store
// CORE-NOT: llvm.store
// CORE-NOT: moore.
// CORE: hw.module @explicit_bins
// CORE-NOT: moore.

// The four cross bins must have independent counters, in addition to the
// original coverpoints, and be sampled on each rising edge.
// CHECK-LABEL: moore.module @top
module top(input bit clk, a, b);
  covergroup cg @(posedge clk);
    cp_a: coverpoint a;
    cp_b: coverpoint b;
    cross cp_a, cp_b;
  endgroup
  // CHECK: %[[OBJ:.*]] = moore.covergroup.new
  // CHECK: moore.procedure always
  // CHECK: moore.detect_event posedge
  // CHECK: moore.covergroup.sample %[[OBJ]]({{.*}}) : <@"top::cg">(!moore.i1, !moore.i1)
  cg coverage = new;
endmodule
// CHECK-LABEL: moore.covergroup.decl @"top::cg"
// CHECK-DAG: %[[ZERO:.*]] = moore.constant 0 : l1
// CHECK-DAG: %[[ONE:.*]] = moore.constant 1 : l1
// CHECK: moore.coverpoint "cp_a" %[[A:.*]] if
// CHECK: moore.coverpoint "cp_b" %[[B:.*]] if
// CHECK: %[[AZ:.*]] = moore.case_eq %[[A]], %[[ZERO]]
// CHECK: %[[A0:.*]] = moore.and %[[AZ]],
// CHECK: %[[AO:.*]] = moore.case_eq %[[A]], %[[ONE]]
// CHECK: %[[A1:.*]] = moore.and %[[AO]],
// CHECK: %[[P0:.*]] = moore.and %[[A0]],
// CHECK: %[[P1:.*]] = moore.and %[[A1]],
// CHECK: %[[BZ:.*]] = moore.case_eq %[[B]], %[[ZERO]]
// CHECK: %[[B0:.*]] = moore.and %[[BZ]],
// CHECK: %[[BO:.*]] = moore.case_eq %[[B]], %[[ONE]]
// CHECK: %[[B1:.*]] = moore.and %[[BO]],
// CHECK: %[[H00:.*]] = moore.and %[[P0]], %[[B0]]
// CHECK: %[[H01:.*]] = moore.and %[[P0]], %[[B1]]
// CHECK: %[[H10:.*]] = moore.and %[[P1]], %[[B0]]
// CHECK: %[[H11:.*]] = moore.and %[[P1]], %[[B1]]
// CHECK: moore.coverbin "$cross0" "auto[0]" if %[[H00]]
// CHECK: moore.coverbin "$cross0" "auto[1]" if %[[H01]]
// CHECK: moore.coverbin "$cross0" "auto[2]" if %[[H10]]
// CHECK: moore.coverbin "$cross0" "auto[3]" if %[[H11]]
// CHECK-NOT: moore.coverbin

// Explicit bins may overlap: every matching product must be recorded. Illegal
// bins are excluded, and each target's iff condition is part of its predicate.
// CHECK-LABEL: moore.module @explicit_bins
module explicit_bins;
  covergroup cg with function sample(bit [1:0] a, bit b, bit enabled);
    cp_a: coverpoint a iff (enabled) {
      bins low = {0, 1};
      bins high = {1, 2};
      illegal_bins bad = {3};
    }
    cp_b: coverpoint b;
    both: cross cp_a, cp_b;
  endgroup
  cg coverage = new;
  initial coverage.sample(1, 0, 1);
endmodule
// CHECK-LABEL: moore.covergroup.decl @"explicit_bins::cg"
// CHECK: %[[LOW:.*]] = moore.and
// CHECK: moore.coverbin "cp_a" "low" if %[[LOW]]
// CHECK: %[[HIGH:.*]] = moore.and
// CHECK: moore.coverbin "cp_a" "high" if %[[HIGH]]
// CHECK: moore.coverbin "cp_a" "bad" {{.*}} {illegal}
// CHECK: moore.coverpoint "cp_b"
// CHECK: moore.and %[[LOW]],
// CHECK: moore.and %[[HIGH]],
// CHECK: moore.coverbin "both" "auto[0]"
// CHECK: moore.coverbin "both" "auto[1]"
// CHECK: moore.coverbin "both" "auto[2]"
// CHECK: moore.coverbin "both" "auto[3]"
// CHECK-NOT: moore.coverbin

// Implicit coverpoints, multiple crosses, and wide signed automatic bins.
// CHECK-LABEL: moore.module @implicit_points
module implicit_points(input bit a, b, c);
  covergroup cg;
    cross a, b;
    cross a, b, c;
  endgroup
  cg coverage = new;
  initial coverage.sample();
endmodule
// CHECK-LABEL: moore.covergroup.decl @"implicit_points::cg"
// CHECK: moore.coverpoint "a"
// CHECK: moore.coverpoint "b"
// CHECK: moore.coverpoint "c"
// CHECK-COUNT-4: moore.coverbin "$cross0"
// CHECK-COUNT-8: moore.coverbin "$cross1"
// CHECK-NOT: moore.coverbin

// CHECK-LABEL: moore.module @wide
module wide;
  covergroup cg with function sample(logic signed [7:0] a, bit b);
    cp_a: coverpoint a;
    cp_b: coverpoint b;
    cross cp_a, cp_b;
  endgroup
  cg coverage = new;
  initial coverage.sample(-1, 1);
endmodule
// CHECK-LABEL: moore.covergroup.decl @"wide::cg"
// CHECK: moore.eq {{.*}} : l8
// CHECK: moore.extract {{.*}} from 2 : l8 -> l6
// CHECK-COUNT-128: moore.coverbin "$cross0"
// CHECK-NOT: moore.coverbin
