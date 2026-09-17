// RUN: circt-translate --import-verilog %s | FileCheck %s
// RUN: circt-verilog --ir-moore %s
// RUN: circt-verilog --ir-hw %s | FileCheck %s --check-prefix=HW
// REQUIRES: slang

// HW-LABEL: hw.module @top(in %clk : i1, in %d : i1, out q : i1)
// HW: [[PAST:%.+]] = ltl.past %d, 3 clk %clk : i1
// HW: [[CLK:%.+]] = seq.to_clock %clk
// HW: [[Q:%.+]] = seq.firreg [[PAST]] clock [[CLK]] : i1
// HW: hw.output [[Q]] : i1
// CHECK-LABEL: moore.module @top
module top(input logic clk, input logic d, output logic q);
  // CHECK: moore.procedure always_ff
  // CHECK: moore.detect_event posedge
  // CHECK: [[PAST:%.+]] = ltl.past {{%.+}}, 3 clk {{%.+}} : i1
  // CHECK: [[INT:%.+]] = moore.from_builtin_int [[PAST]] : i1
  // CHECK: [[LOGIC:%.+]] = moore.int_to_logic [[INT]] : i1
  // CHECK: moore.nonblocking_assign {{%.+}}, [[LOGIC]] : l1
  always_ff @(posedge clk) q <= $past(d, 3);
endmodule

// CHECK-LABEL: moore.module @PastConstantTicks
module PastConstantTicks(input logic clk, input logic [7:0] d,
                         output logic [7:0] q);
  localparam int TICKS = 2;
  // CHECK: ltl.past {{%.+}}, 4 clk {{%.+}} : i8
  always_ff @(posedge clk) q <= $past(d, TICKS + 2);
endmodule

// CHECK-LABEL: moore.module @PastDefaultTicks
module PastDefaultTicks(input logic clk, input logic d, output logic q);
  // CHECK: ltl.past {{%.+}}, 1 clk {{%.+}} : i1
  always_ff @(posedge clk) q <= $past(d, );
endmodule

// CHECK-LABEL: moore.module @PastAssertionTicks
module PastAssertionTicks(input logic clk, input logic d);
  // CHECK: ltl.past {{%.+}}, 3 clk {{%.+}} : i1
  assert property (@(posedge clk) d == $past(d, 3));
endmodule
