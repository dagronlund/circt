// RUN: circt-verilog --ir-moore %s | circt-opt --verify-roundtrip | FileCheck %s
// RUN: circt-verilog --ir-llhd %s | circt-opt --verify-roundtrip | FileCheck %s --check-prefix=CORE
// RUN: circt-verilog --ir-hw %s | circt-opt --verify-roundtrip | FileCheck %s --check-prefix=CORE
// REQUIRES: slang

// CORE-NOT: moore.
// CORE: hw.module @top
// CORE-NOT: moore.
// CORE: hw.module @constructor_inputs
// CORE-NOT: moore.

// CHECK-LABEL: moore.module @top
module top;
  covergroup cg with function sample(int value);
    coverpoint value;
  endgroup
  // CHECK: moore.covergroup.new : <@"top::cg">
  cg coverage = new();
  // CHECK: moore.covergroup.sample {{.*}}({{.*}}) : <@"top::cg">(!moore.i32)
  initial coverage.sample(1);
endmodule

// CHECK-LABEL: moore.covergroup.decl @"top::cg"
// CHECK: ^bb0(%{{.*}}: !moore.i32):
// CHECK: moore.coverpoint "value" {{.*}} if {{.*}} {isSigned} : l32

// CHECK-LABEL: moore.module @multiple
module multiple;
  covergroup cg with function sample(bit [3:0] a, bit enabled);
    cp: coverpoint (a + 4'd1) iff (enabled);
    other: coverpoint a;
  endgroup
  // CHECK: moore.covergroup.new : <@"multiple::cg">
  cg first = new();
  // CHECK: moore.covergroup.new : <@"multiple::cg">
  cg second = new();
  initial begin
    // CHECK: moore.covergroup.sample
    first.sample(2, 1);
    // CHECK: moore.covergroup.sample
    second.sample(3, 0);
    // CHECK: moore.covergroup.sample
    first.sample(4, 1);
  end
endmodule

// CHECK-LABEL: moore.covergroup.decl @"multiple::cg"
// CHECK: ^bb0(%{{.*}}: !moore.i4, %{{.*}}: !moore.i1):
// CHECK: moore.add
// CHECK: moore.coverpoint "cp" {{.*}} if {{.*}} : l4
// CHECK: moore.coverpoint "other" {{.*}} if {{.*}} : l4

// CHECK-LABEL: moore.module @handles
module handles;
  covergroup cg with function sample(int value = 7);
    coverpoint value;
  endgroup
  cg coverage;
  cg alias_handle;
  initial begin
    // CHECK: moore.covergroup.new
    coverage = new();
    alias_handle = coverage;
    // CHECK: moore.covergroup.sample
    alias_handle.sample();
    // CHECK: moore.covergroup.null
    coverage = null;
  end
endmodule

// CHECK-LABEL: moore.covergroup.decl @"handles::cg"
// CHECK: moore.coverpoint "value"

// CHECK-LABEL: moore.module @constant_point
module constant_point;
  covergroup cg;
    coverpoint (1 + 2);
  endgroup
  cg coverage = new();
  // CHECK: moore.covergroup.sample {{.*}}() : <@"constant_point::cg">
  initial coverage.sample();
endmodule

// CHECK-LABEL: moore.covergroup.decl @"constant_point::cg"
// CHECK: moore.coverpoint "$coverpoint0"

// CHECK-LABEL: moore.module @constructor_inputs
module constructor_inputs;
  covergroup cg(int limit = 4) with function sample(int value);
    coverpoint value;
  endgroup
  // CHECK: moore.covergroup.new : <@"constructor_inputs::cg">
  cg coverage = new(4);
  int calls;
  function int next_limit();
    calls++;
    return calls;
  endfunction
  initial begin
    // CHECK: moore.covergroup.sample {{.*}}({{.*}}) : <@"constructor_inputs::cg">(!moore.i32)
    coverage.sample(1);
    // CHECK: func.call @next_limit(
    // CHECK: moore.covergroup.new : <@"constructor_inputs::cg">
    coverage = new(next_limit());
    // CHECK: moore.covergroup.new : <@"constructor_inputs::cg">
    coverage = new();
  end
endmodule

// CHECK-LABEL: moore.covergroup.decl @"constructor_inputs::cg"
// CHECK-NEXT: ^bb0(%{{[^:]+}}: !moore.i32):
// CHECK: moore.coverpoint "value"
