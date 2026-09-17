// RUN: circt-verilog --ir-moore %s | FileCheck %s
// RUN: circt-verilog --ir-hw %s > /dev/null
// REQUIRES: slang
// UNSUPPORTED: valgrind

interface bus_if;
  logic error;
endinterface

// Captures of locally expanded interface members must resolve at the call site
// after the interface's symbol scope has ended.
// CHECK-LABEL: moore.module @top(
// CHECK: [[RESULT:%.+]] = moore.variable : <l1>
// CHECK: [[ERROR:%.+]] = moore.variable : <l1>
// CHECK: moore.assign [[ERROR]], %error_in : l1
// CHECK: moore.call_coroutine @capture([[RESULT]], [[ERROR]])
module top(input logic clk, error_in, output logic result);
  bus_if bus();
  assign bus.error = error_in;

  task capture();
    result <= bus.error;
  endtask
  always_ff @(posedge clk) capture();
endmodule

// CHECK-LABEL: moore.coroutine private @capture(%arg0: !moore.ref<l1>, %arg1: !moore.ref<l1>)
// CHECK: [[READ:%.+]] = moore.read %arg1 : <l1>
// CHECK: moore.nonblocking_assign %arg0, [[READ]] : l1

// Also cover transitive captures and writes, with two instances of the same
// interface to ensure each capture resolves to the correct instance.
// CHECK-LABEL: moore.module @TransitiveCapture(
// CHECK: [[FIRST:%.+]] = moore.variable : <l1>
// CHECK: [[SECOND:%.+]] = moore.variable : <l1>
// CHECK: moore.assign [[FIRST]], %error_in : l1
// CHECK: moore.call_coroutine @forward([[FIRST]], [[SECOND]])
module TransitiveCapture(input logic clk, error_in, output logic result);
  bus_if first();
  bus_if second();
  assign first.error = error_in;
  assign result = second.error;

  task copy_error();
    second.error <= first.error;
  endtask
  task forward();
    copy_error();
  endtask
  always_ff @(posedge clk) forward();
endmodule

// CHECK-LABEL: moore.coroutine private @copy_error(%arg0: !moore.ref<l1>, %arg1: !moore.ref<l1>)
// CHECK: [[READ:%.+]] = moore.read %arg1 : <l1>
// CHECK: moore.nonblocking_assign %arg0, [[READ]] : l1
// CHECK-LABEL: moore.coroutine private @forward(%arg0: !moore.ref<l1>, %arg1: !moore.ref<l1>)
// CHECK: moore.call_coroutine @copy_error(%arg1, %arg0)
