// RUN: circt-verilog --import-only %s | FileCheck %s
// RUN: circt-verilog %s -o /dev/null
// REQUIRES: slang
// UNSUPPORTED: valgrind

package p;
  property holds(logic clk, logic a);
    @(posedge clk) a;
  endproperty

  sequence value_is_set(logic a);
    a;
  endsequence

  property holds_sequence(logic clk, logic a);
    @(negedge clk) value_is_set(a);
  endproperty
endpackage

// Package declarations are expanded at the use site, with both the clock and
// the value bound to the actual arguments.
// CHECK-LABEL: moore.module @top(
// CHECK: [[CLK:%.*]] = moore.net name "clk"
// CHECK: [[A:%.*]] = moore.net name "a"
// CHECK: [[AR:%.*]] = moore.read [[A]]
// CHECK: [[AI:%.*]] = moore.logic_to_int [[AR]]
// CHECK: [[AB:%.*]] = moore.to_builtin_int [[AI]]
// CHECK: [[CR:%.*]] = moore.read [[CLK]]
// CHECK: [[CI:%.*]] = moore.logic_to_int [[CR]]
// CHECK: [[CB:%.*]] = moore.to_builtin_int [[CI]]
// CHECK: [[PROP:%.*]] = ltl.clock [[AB]], posedge [[CB]] : i1
// CHECK: verif.assert [[PROP]] : !ltl.sequence
module top(input logic clk, a);
  assert property (p::holds(clk, a));
endmodule

// Also cover imported names and a package sequence nested in a property. Use
// different actual argument names to check substitution through both instances.
// CHECK-LABEL: moore.module @nested(
// CHECK: [[CLK:%.*]] = moore.net name "clock"
// CHECK: [[A:%.*]] = moore.net name "value"
// CHECK: [[AR:%.*]] = moore.read [[A]]
// CHECK: [[AI:%.*]] = moore.logic_to_int [[AR]]
// CHECK: [[AB:%.*]] = moore.to_builtin_int [[AI]]
// CHECK: [[CR:%.*]] = moore.read [[CLK]]
// CHECK: [[CI:%.*]] = moore.logic_to_int [[CR]]
// CHECK: [[CB:%.*]] = moore.to_builtin_int [[CI]]
// CHECK: [[PROP:%.*]] = ltl.clock [[AB]], negedge [[CB]] : i1
// CHECK: verif.assert [[PROP]] : !ltl.sequence
module nested(input logic clock, value);
  import p::*;
  assert property (holds_sequence(clock, value));
endmodule
