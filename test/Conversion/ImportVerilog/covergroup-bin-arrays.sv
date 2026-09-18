// RUN: circt-verilog --ir-moore %s | circt-opt --verify-roundtrip | FileCheck %s
// RUN: circt-verilog --ir-llhd %s | FileCheck %s --check-prefix=CORE
// RUN: circt-verilog --ir-hw %s | FileCheck %s --check-prefix=CORE
// REQUIRES: slang

// CORE-NOT: moore.
// CORE: hw.module @top
// CORE-NOT: moore.
// CORE-COUNT-2: llvm.store
// CORE-NOT: llvm.store
// CORE-NOT: moore.
// CORE: hw.module @signed_values
// CORE-NOT: moore.

module top(input bit clk, input bit [1:0] value);
  covergroup cg @(posedge clk);
    coverpoint value {
      bins values[] = {[1:2]};
    }
  endgroup
  cg coverage = new;
endmodule
// CHECK-LABEL: moore.covergroup.decl @"top::cg"
// CHECK-DAG: %[[ONE:.*]] = moore.constant 1 : l2
// CHECK-DAG: %[[TWO:.*]] = moore.constant -2 : l2
// CHECK: %[[EQ:.*]] = moore.case_eq {{.*}}, %[[ONE]] : l2
// CHECK: %[[HIT:.*]] = moore.and %[[EQ]], {{.*}} : i1
// CHECK: moore.coverbin "value" "values[0]" if %[[HIT]]
// CHECK: %[[EQ:.*]] = moore.case_eq {{.*}}, %[[TWO]] : l2
// CHECK: %[[HIT:.*]] = moore.and %[[EQ]], {{.*}} : i1
// CHECK: moore.coverbin "value" "values[1]" if %[[HIT]]
// CHECK-NOT: moore.coverbin

// Overlapping ranges and repeated singleton values denote a set. Signed ranges
// must enumerate through zero; a range ending at the maximum must not wrap.
module signed_values;
  covergroup cg with function sample(bit signed [2:0] value, bit enabled);
    cp: coverpoint value iff (enabled) {
      bins values[] = {[-1:1], 0, [1:3]};
    }
  endgroup
  cg coverage = new;
  initial coverage.sample(-1, 1);
endmodule
// CHECK-LABEL: moore.covergroup.decl @"signed_values::cg"
// CHECK-DAG: %[[V0:.*]] = moore.constant -1 : l3
// CHECK-DAG: %[[V1:.*]] = moore.constant 0 : l3
// CHECK-DAG: %[[V2:.*]] = moore.constant 1 : l3
// CHECK-DAG: %[[V3:.*]] = moore.constant 2 : l3
// CHECK-DAG: %[[V4:.*]] = moore.constant 3 : l3
// CHECK: moore.case_eq {{.*}}, %[[V0]] : l3
// CHECK: moore.coverbin "cp" "values[0]"
// CHECK: moore.case_eq {{.*}}, %[[V1]] : l3
// CHECK: moore.coverbin "cp" "values[1]"
// CHECK: moore.case_eq {{.*}}, %[[V2]] : l3
// CHECK: moore.coverbin "cp" "values[2]"
// CHECK: moore.case_eq {{.*}}, %[[V3]] : l3
// CHECK: moore.coverbin "cp" "values[3]"
// CHECK: moore.case_eq {{.*}}, %[[V4]] : l3
// CHECK: moore.coverbin "cp" "values[4]"
// CHECK-NOT: moore.coverbin

module wide_values;
  covergroup cg with function sample(bit [64:0] value);
    coverpoint value {
      bins values[] = {[65'h1fffffffffffffffe:65'h1ffffffffffffffff]};
    }
  endgroup
  cg coverage = new;
endmodule
// CHECK-LABEL: moore.covergroup.decl @"wide_values::cg"
// CHECK-DAG: %[[LOW:.*]] = moore.constant -2 : l65
// CHECK-DAG: %[[HIGH:.*]] = moore.constant -1 : l65
// CHECK: moore.case_eq {{.*}}, %[[LOW]] : l65
// CHECK: moore.coverbin "value" "values[0]"
// CHECK: moore.case_eq {{.*}}, %[[HIGH]] : l65
// CHECK: moore.coverbin "value" "values[1]"
// CHECK-NOT: moore.coverbin
