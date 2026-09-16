// RUN: circt-verilog --import-only %s | FileCheck %s
// RUN: circt-verilog --import-only %s | circt-opt --convert-moore-to-core --canonicalize | FileCheck %s --check-prefix=CORE
// RUN: circt-verilog --ir-hw --top=live %s | FileCheck %s --check-prefix=LIVE
// REQUIRES: slang
// UNSUPPORTED: valgrind

// CHECK-LABEL: func.func private @get_value(
// CHECK: [[SUFFIX:%.*]] = moore.int_to_string %{{.*}} : i24
// CHECK: [[FORMAT:%.*]] = moore.string.concat (%arg0, [[SUFFIX]])
// CHECK: [[FOUND:%.*]], [[RESULT:%.*]] = moore.builtin.plusargs_value_dynamic [[FORMAT]] : i1, i32
// CHECK: [[COND:%.*]] = moore.to_builtin_int [[FOUND]] : i1
// CHECK-NEXT: cf.cond_br [[COND]], ^[[ASSIGN:bb[0-9]+]], ^[[CONT:bb[0-9]+]]
// CHECK: ^[[ASSIGN]]:
// CHECK-NEXT: moore.blocking_assign %arg1, [[RESULT]] : i32
// CHECK-NEXT: cf.br ^[[CONT]]
// CHECK: ^[[CONT]]:
// CHECK: moore.zext [[FOUND]] : i1 -> i32
// CORE-LABEL: func.func private @get_value(
// CORE: [[FORMAT:%.*]] = sim.string.concat (%arg0, %{{.*}})
// CORE: [[FOUND:%.*]], [[RESULT:%.*]] = sim.plusargs.value_dynamic [[FORMAT]] : i32
// CORE: cf.cond_br [[FOUND]]
// CORE: llhd.drv %arg1, [[RESULT]]
function automatic int get_value(string name, ref int value);
  return $value$plusargs({name, "=%d"}, value);
endfunction

// CHECK-LABEL: func.func private @test_value(
// CHECK: [[FORMAT:%.*]] = moore.string.concat (%arg0, %{{.*}})
// CHECK: [[FOUND:%.*]] = moore.builtin.plusargs_test_dynamic [[FORMAT]] : i1
// CHECK: moore.zext [[FOUND]] : i1 -> i32
// CORE-LABEL: func.func private @test_value(
// CORE: sim.plusargs.test_dynamic
function automatic int test_value(string name);
  return $test$plusargs({name, "="});
endfunction

// Expression-valued constant arguments must also work without being literals.
// CHECK-LABEL: func.func private @constant_plusargs(
// CHECK: moore.builtin.plusargs_test_dynamic
// CHECK: moore.builtin.plusargs_value_dynamic
function automatic void constant_plusargs();
  localparam string prefix = "foo";
  int value;
  void'($test$plusargs(prefix));
  void'($value$plusargs({prefix, "=%d"}, value));
endfunction

// Literal calls retain the existing operations and return integer 0 or 1,
// rather than sign-extending a true one-bit result to -1.
// CHECK-LABEL: func.func private @literal_test_status(
// CHECK: [[FOUND:%.*]] = moore.builtin.plusargs_test "foo" : i1
// CHECK: moore.zext [[FOUND]] : i1 -> i32
function automatic int literal_test_status();
  return $test$plusargs("foo");
endfunction

// CHECK-LABEL: func.func private @literal_value_status(
// CHECK: [[FOUND:%.*]], %{{.*}} = moore.builtin.plusargs_value "foo=%d" : i1, i32
// CHECK: moore.zext [[FOUND]] : i1 -> i32
function automatic int literal_value_status(ref int value);
  return $value$plusargs("foo=%d", value);
endfunction

// A computed format is evaluated once, including side effects.
function automatic string make_format(ref int calls);
  calls++;
  return "foo=%d";
endfunction

// CHECK-LABEL: func.func private @call_format(
// CHECK: [[FORMAT:%.*]] = call @make_format(%arg0)
// CHECK-NOT: call @make_format
// CHECK: moore.builtin.plusargs_value_dynamic [[FORMAT]]
function automatic int call_format(ref int calls, ref int value);
  return $value$plusargs(make_format(calls), value);
endfunction

module top;
endmodule

// Exercise the normal lowering pipeline with a live procedural call.
// LIVE-LABEL: hw.module @live(
// LIVE: llhd.combinational
// LIVE: [[FORMAT:%.*]] = sim.string.concat
// LIVE: [[FOUND:%.*]], [[RESULT:%.*]] = sim.plusargs.value_dynamic [[FORMAT]] : i32
// LIVE: comb.mux [[FOUND]], [[RESULT]]
module live(input int index, output int value, output int found);
  string name;
  always_comb begin
    name = $sformatf("arg%0d", index);
    found = $value$plusargs({name, "=%d"}, value);
  end
endmodule
