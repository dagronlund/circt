// RUN: circt-verilog %s | FileCheck %s --check-prefix=DEFAULT
// RUN: circt-verilog --sroa %s | FileCheck %s --check-prefix=SROA
// REQUIRES: slang
// UNSUPPORTED: valgrind

module source_bit(input logic value, output logic result);
  assign result = value;
endmodule

// A procedural read-modify-write must preserve the separate instance driver.
// DEFAULT-LABEL: hw.module @top
// DEFAULT-NEXT: %[[ZERO:.*]] = hw.constant false
// DEFAULT-NEXT: %[[LOW:.*]] = comb.concat %[[ZERO]], %[[U:.*]] : i1, i1
// DEFAULT-NEXT: %[[HIGH:.*]] = comb.concat %b, %[[ZERO]] : i1, i1
// DEFAULT-NEXT: %[[RESULT:.*]] = comb.or %[[HIGH]], %[[LOW]] : i2
// DEFAULT-NEXT: %[[U]] = hw.instance "u" @source_bit(value: %a: i1) -> (result: i1)
// DEFAULT-NEXT: hw.output %[[RESULT]] : i2
// SROA-LABEL: hw.module @top(in %a : i1, in %b : i1, out result : i2)
// SROA-NEXT: %[[U:.*]] = hw.instance "u" @source_bit(value: %a: i1) -> (result: i1)
// SROA-NEXT: %[[RESULT:.*]] = comb.concat %b, %[[U]] : i1, i1
// SROA-NEXT: hw.output %[[RESULT]] : i2
module top(input logic a, b, output logic [1:0] result);
  source_bit u(.value(a), .result(result[0]));
  always_comb result[1] = b;
endmodule

// Also cover preserved bits on both sides of a procedural slice.
// DEFAULT-LABEL: hw.module @middle
// DEFAULT-NEXT: %[[ZERO3:.*]] = hw.constant 0 : i3
// DEFAULT-NEXT: %[[ZERO2:.*]] = hw.constant 0 : i2
// DEFAULT-NEXT: %[[ZERO:.*]] = hw.constant false
// DEFAULT-NEXT: %[[MID:.*]] = comb.concat %b, %[[ZERO]] : i2, i1
// DEFAULT-NEXT: %[[LOW:.*]] = comb.concat %[[ZERO2]], %[[LO:.*]] : i2, i1
// DEFAULT-NEXT: %[[LOWMID:.*]] = comb.or %[[MID]], %[[LOW]] : i3
// DEFAULT-NEXT: %[[PAD:.*]] = comb.concat %[[ZERO]], %[[LOWMID]] : i1, i3
// DEFAULT-NEXT: %[[HIGH:.*]] = comb.concat %[[HI:.*]], %[[ZERO3]] : i1, i3
// DEFAULT-NEXT: %[[RESULT:.*]] = comb.or %[[HIGH]], %[[PAD]] : i4
// DEFAULT-NEXT: %[[LO]] = hw.instance "lo" @source_bit(value: %a: i1) -> (result: i1)
// DEFAULT-NEXT: %[[HI]] = hw.instance "hi" @source_bit(value: %c: i1) -> (result: i1)
// DEFAULT-NEXT: hw.output %[[RESULT]] : i4
// SROA-LABEL: hw.module @middle(in %a : i1, in %b : i2, in %c : i1, out result : i4)
// SROA-DAG: %[[LO:.*]] = hw.instance "lo" @source_bit(value: %a: i1) -> (result: i1)
// SROA-DAG: %[[HI:.*]] = hw.instance "hi" @source_bit(value: %c: i1) -> (result: i1)
// SROA: %[[RESULT:.*]] = comb.concat %[[HI]], %b, %[[LO]] : i1, i2, i1
// SROA-NEXT: hw.output %[[RESULT]] : i4
module middle(input logic a, input logic [1:0] b, input logic c,
              output logic [3:0] result);
  source_bit lo(.value(a), .result(result[0]));
  source_bit hi(.value(c), .result(result[3]));
  always_comb result[2:1] = b;
endmodule
