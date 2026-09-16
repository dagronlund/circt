// RUN: circt-verilog --import-only %s | FileCheck %s
// RUN: circt-verilog %s -o /dev/null
// REQUIRES: slang
// UNSUPPORTED: valgrind

// A named property may contain both its clock and its disable condition.
// CHECK-LABEL: moore.module @top(
// CHECK: [[RST:%.*]] = moore.net name "rst"
// CHECK: [[R:%.*]] = moore.read [[RST]]
// CHECK: [[NOT:%.*]] = moore.not [[R]]
// CHECK: [[INT:%.*]] = moore.logic_to_int [[NOT]]
// CHECK: [[ENABLE:%.*]] = moore.to_builtin_int [[INT]]
// CHECK: [[IMPL:%.*]] = ltl.implication
// CHECK: [[CLOCK:%.*]] = ltl.clock [[IMPL]], posedge
// CHECK: verif.assert [[CLOCK]] if [[ENABLE]] : !ltl.property
module top(input logic clk, rst, a, b);
  property p;
    @(posedge clk) disable iff(rst) a |-> b;
  endproperty
  assert property (p);
endmodule

// Slang expands property arguments in the body. Follow multiple aliases without
// losing that substitution or the clock on the original declaration.
// CHECK-LABEL: moore.module @aliases(
// CHECK: [[RST:%.*]] = moore.net name "rst"
// CHECK: [[R:%.*]] = moore.read [[RST]]
// CHECK: [[NOT:%.*]] = moore.not [[R]]
// CHECK: [[INT:%.*]] = moore.logic_to_int [[NOT]]
// CHECK: [[ENABLE:%.*]] = moore.to_builtin_int [[INT]]
// CHECK: [[IMPL:%.*]] = ltl.implication
// CHECK: [[CLOCK:%.*]] = ltl.clock [[IMPL]], negedge
// CHECK: verif.assume [[CLOCK]] if [[ENABLE]] : !ltl.property
module aliases(input logic clk, rst, a, b);
  property p(reset, x, y);
    @(negedge clk) disable iff(reset) x |-> y;
  endproperty
  property q(x, y);
    p(rst, x, y);
  endproperty
  property r;
    q(a, b);
  endproperty
  assume property (r);
endmodule

// The clock can instead be supplied at the assertion site.
// CHECK-LABEL: moore.module @outer_clock(
// CHECK: [[NOT:%.*]] = moore.not
// CHECK: [[INT:%.*]] = moore.logic_to_int [[NOT]]
// CHECK: [[ENABLE:%.*]] = moore.to_builtin_int [[INT]]
// CHECK: [[IMPL:%.*]] = ltl.implication
// CHECK: [[CLOCK:%.*]] = ltl.clock [[IMPL]], posedge
// CHECK: verif.assert [[CLOCK]] if [[ENABLE]] : !ltl.property
module outer_clock(input logic clk, rst, a, b);
  property p;
    disable iff(rst) a |-> b;
  endproperty
  assert property (@(posedge clk) p);
endmodule

// Keep supporting a disable condition at the assertion site and a clock in the
// property body, as well as a directly written property specification.
// CHECK-LABEL: moore.module @outer_disable(
// CHECK: [[NOT:%.*]] = moore.not
// CHECK: [[INT:%.*]] = moore.logic_to_int [[NOT]]
// CHECK: [[ENABLE:%.*]] = moore.to_builtin_int [[INT]]
// CHECK: [[IMPL:%.*]] = ltl.implication
// CHECK: [[CLOCK:%.*]] = ltl.clock [[IMPL]], posedge
// CHECK: verif.assert [[CLOCK]] if [[ENABLE]] : !ltl.property
// CHECK: [[NOT2:%.*]] = moore.not
// CHECK: [[INT2:%.*]] = moore.logic_to_int [[NOT2]]
// CHECK: [[ENABLE2:%.*]] = moore.to_builtin_int [[INT2]]
// CHECK: [[IMPL2:%.*]] = ltl.implication
// CHECK: [[CLOCK2:%.*]] = ltl.clock [[IMPL2]], posedge
// CHECK: verif.assert [[CLOCK2]] if [[ENABLE2]] : !ltl.property
module outer_disable(input logic clk, rst, a, b);
  property p;
    @(posedge clk) a |-> b;
  endproperty
  assert property (disable iff(rst) p);
  assert property (@(posedge clk) disable iff(rst) a |-> b);
endmodule

// Only transparent reference wrappers may be removed: sequence repetitions
// still have to be lowered, and properties without disable iff stay unguarded.
// CHECK-LABEL: moore.module @repetition(
// CHECK: [[REPEAT:%.*]] = ltl.repeat {{.*}}, 2
// CHECK: [[CLOCK:%.*]] = ltl.clock [[REPEAT]], posedge
// CHECK: verif.assert [[CLOCK]] : !ltl.sequence
module repetition(input logic clk, a);
  sequence s;
    a;
  endsequence
  assert property (@(posedge clk) s[*2]);
endmodule

// Cover properties preserve the same clock, disable enable, and structure.

// A named property may contain both its clock and its disable condition.
// CHECK-LABEL: moore.module @cover_top(
// CHECK: [[RST:%.*]] = moore.net name "rst"
// CHECK: [[R:%.*]] = moore.read [[RST]]
// CHECK: [[NOT:%.*]] = moore.not [[R]]
// CHECK: [[INT:%.*]] = moore.logic_to_int [[NOT]]
// CHECK: [[ENABLE:%.*]] = moore.to_builtin_int [[INT]]
// CHECK: [[IMPL:%.*]] = ltl.implication
// CHECK: [[CLOCK:%.*]] = ltl.clock [[IMPL]], posedge
// CHECK: verif.cover [[CLOCK]] if [[ENABLE]] : !ltl.property
module cover_top(input logic clk, rst, a, b);
  property p;
    @(posedge clk) disable iff(rst) a |-> b;
  endproperty
  cover property (p);
endmodule

// Slang expands property arguments in the body. Follow multiple aliases without
// losing that substitution or the clock on the original declaration.
// CHECK-LABEL: moore.module @cover_aliases(
// CHECK: [[RST:%.*]] = moore.net name "rst"
// CHECK: [[R:%.*]] = moore.read [[RST]]
// CHECK: [[NOT:%.*]] = moore.not [[R]]
// CHECK: [[INT:%.*]] = moore.logic_to_int [[NOT]]
// CHECK: [[ENABLE:%.*]] = moore.to_builtin_int [[INT]]
// CHECK: [[IMPL:%.*]] = ltl.implication
// CHECK: [[CLOCK:%.*]] = ltl.clock [[IMPL]], negedge
// CHECK: verif.cover [[CLOCK]] if [[ENABLE]] : !ltl.property
module cover_aliases(input logic clk, rst, a, b);
  property p(reset, x, y);
    @(negedge clk) disable iff(reset) x |-> y;
  endproperty
  property q(x, y);
    p(rst, x, y);
  endproperty
  property r;
    q(a, b);
  endproperty
  cover property (r);
endmodule

// The clock can instead be supplied at the assertion site.
// CHECK-LABEL: moore.module @cover_outer_clock(
// CHECK: [[NOT:%.*]] = moore.not
// CHECK: [[INT:%.*]] = moore.logic_to_int [[NOT]]
// CHECK: [[ENABLE:%.*]] = moore.to_builtin_int [[INT]]
// CHECK: [[IMPL:%.*]] = ltl.implication
// CHECK: [[CLOCK:%.*]] = ltl.clock [[IMPL]], posedge
// CHECK: verif.cover [[CLOCK]] if [[ENABLE]] : !ltl.property
module cover_outer_clock(input logic clk, rst, a, b);
  property p;
    disable iff(rst) a |-> b;
  endproperty
  cover property (@(posedge clk) p);
endmodule

// Keep supporting a disable condition at the assertion site and a clock in the
// property body, as well as a directly written property specification.
// CHECK-LABEL: moore.module @cover_outer_disable(
// CHECK: [[NOT:%.*]] = moore.not
// CHECK: [[INT:%.*]] = moore.logic_to_int [[NOT]]
// CHECK: [[ENABLE:%.*]] = moore.to_builtin_int [[INT]]
// CHECK: [[IMPL:%.*]] = ltl.implication
// CHECK: [[CLOCK:%.*]] = ltl.clock [[IMPL]], posedge
// CHECK: verif.cover [[CLOCK]] if [[ENABLE]] : !ltl.property
// CHECK: [[NOT2:%.*]] = moore.not
// CHECK: [[INT2:%.*]] = moore.logic_to_int [[NOT2]]
// CHECK: [[ENABLE2:%.*]] = moore.to_builtin_int [[INT2]]
// CHECK: [[IMPL2:%.*]] = ltl.implication
// CHECK: [[CLOCK2:%.*]] = ltl.clock [[IMPL2]], posedge
// CHECK: verif.cover [[CLOCK2]] if [[ENABLE2]] : !ltl.property
module cover_outer_disable(input logic clk, rst, a, b);
  property p;
    @(posedge clk) a |-> b;
  endproperty
  cover property (disable iff(rst) p);
  cover property (@(posedge clk) disable iff(rst) a |-> b);
endmodule

// Only transparent reference wrappers may be removed: sequence repetitions
// still have to be lowered, and properties without disable iff stay unguarded.
// CHECK-LABEL: moore.module @cover_repetition(
// CHECK: [[REPEAT:%.*]] = ltl.repeat {{.*}}, 2
// CHECK: [[CLOCK:%.*]] = ltl.clock [[REPEAT]], posedge
// CHECK: verif.cover [[CLOCK]] : !ltl.sequence
module cover_repetition(input logic clk, a);
  sequence s;
    a;
  endsequence
  cover property (@(posedge clk) s[*2]);
endmodule
