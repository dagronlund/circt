// RUN: circt-verilog --ir-moore %s | circt-opt --verify-roundtrip | FileCheck %s
// RUN: circt-verilog --ir-llhd %s | FileCheck %s --check-prefix=CORE
// RUN: circt-verilog --ir-hw %s | FileCheck %s --check-prefix=HW
// REQUIRES: slang

// HW-NOT: moore.
// HW: hw.module @top
// HW: call @abort
// HW: llvm.store
// HW: call @abort
// HW-NOT: moore.

// CORE-NOT: moore.
// CORE: hw.module @top
// CORE-NOT: moore.
// CORE: func.func private @"top::cg::sample"
// CORE: scf.if
// CORE: call @abort
// CORE: llvm.store
// CORE: scf.if
// CORE: call @abort
// CORE-NOT: moore.

// CHECK-LABEL: moore.module @top
module top;
  bit value;
  covergroup cg;
    coverpoint value {
      bins zero = {0};
      illegal_bins one = {1};
    }
  endgroup
  cg coverage = new;
  initial begin
    value = 0;
    // CHECK: moore.read
    // CHECK: moore.covergroup.sample {{.*}}({{.*}}) : <@"top::cg">(!moore.i1)
    coverage.sample();
    value = 1;
    // CHECK: moore.read
    // CHECK: moore.covergroup.sample {{.*}}({{.*}}) : <@"top::cg">(!moore.i1)
    coverage.sample();
  end
endmodule

// CHECK-LABEL: moore.covergroup.decl @"top::cg"
// CHECK: moore.case_eq
// CHECK: moore.and
// CHECK: moore.coverbin "value" "zero" if
// CHECK: moore.case_eq
// CHECK: moore.and
// CHECK: moore.coverbin "value" "one" if {{.*}} {illegal}

// CHECK-LABEL: moore.module @multiple_values
module multiple_values;
  covergroup cg with function sample(bit [3:0] value, bit enabled);
    cp: coverpoint value iff (enabled) {
      bins valid = {0, 2, 4};
      illegal_bins bad = {1, 3};
    }
  endgroup
  cg coverage = new;
  initial coverage.sample(2, 1);
endmodule
// CHECK-LABEL: moore.covergroup.decl @"multiple_values::cg"
// CHECK: moore.or
// CHECK: moore.or
// CHECK: moore.and
// CHECK: moore.coverbin "cp" "valid" if
// CHECK: moore.or
// CHECK: moore.and
// CHECK: moore.coverbin "cp" "bad" if {{.*}} {illegal}
