// RUN: circt-verilog --ir-moore %s | circt-opt --verify-roundtrip | FileCheck %s
// RUN: circt-verilog --ir-llhd %s | circt-opt --verify-roundtrip | FileCheck %s --check-prefix=CORE
// RUN: circt-verilog --ir-hw %s | circt-opt --verify-roundtrip | FileCheck %s --check-prefix=CORE
// REQUIRES: slang

// CORE-NOT: moore.
// CORE: hw.module @top
// CORE-NOT: moore.
// CORE: hw.module @multiple
// CORE-NOT: moore.

// CHECK-LABEL: moore.module @top
module top(input logic clk, input logic value);
  covergroup cg @(posedge clk);
    coverpoint value;
  endgroup
  // CHECK: %[[OBJ:.*]] = moore.covergroup.new
  // CHECK: moore.procedure always {
  // CHECK: moore.wait_event {
  // CHECK: moore.detect_event posedge
  // CHECK: %[[VALUE:.*]] = moore.read %value
  // CHECK: moore.covergroup.sample %[[OBJ]](%[[VALUE]]) : <@"top::cg">(!moore.l1)
  cg coverage = new();
endmodule

// CHECK-LABEL: moore.covergroup.decl @"top::cg"
// CHECK-NEXT: ^bb0(%{{.*}}: !moore.l1):
// CHECK: moore.coverpoint "value"

// CHECK-LABEL: moore.module @multiple
module multiple(input bit clk, input bit enabled, input bit [3:0] value);
  covergroup cg @(negedge clk);
    cp: coverpoint (value + 4'd1) iff (enabled);
    other: coverpoint value;
  endgroup
  // CHECK: %[[FIRST:.*]] = moore.covergroup.new
  // CHECK: moore.procedure always
  // CHECK: moore.detect_event negedge
  // CHECK: moore.covergroup.sample %[[FIRST]]({{.*}}) : <@"multiple::cg">(!moore.i4, !moore.i1)
  cg first = new();
  // CHECK: %[[SECOND:.*]] = moore.covergroup.new
  // CHECK: moore.procedure always
  // CHECK: moore.detect_event negedge
  // CHECK: moore.covergroup.sample %[[SECOND]]({{.*}}) : <@"multiple::cg">(!moore.i4, !moore.i1)
  cg second = new();
  // Copying a handle does not create an additional automatic sampler.
  // CHECK-NOT: moore.procedure always
  cg alias_handle = first;
  // CHECK: moore.procedure initial
  // CHECK: moore.covergroup.sample {{.*}}({{.*}}) : <@"multiple::cg">(!moore.i4, !moore.i1)
  initial alias_handle.sample();
endmodule

// Captures are deduplicated across coverpoints and include iff expressions.
// CHECK-LABEL: moore.covergroup.decl @"multiple::cg"
// CHECK-NEXT: ^bb0(%{{[^:]+}}: !moore.i4, %{{[^:]+}}: !moore.i1):
// CHECK: moore.coverpoint "cp"
// CHECK: moore.coverpoint "other"
