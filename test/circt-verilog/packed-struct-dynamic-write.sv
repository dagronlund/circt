// RUN: circt-verilog %s | FileCheck %s --check-prefix=DEFAULT
// RUN: circt-verilog --sroa %s | FileCheck %s
// REQUIRES: slang
// UNSUPPORTED: valgrind

// Dynamic writes must lower all the way to hardware, including when a slice
// crosses the boundary between struct fields.
// DEFAULT-LABEL: hw.module @clocked(
// CHECK-LABEL: hw.module @clocked(
// CHECK-NOT: llhd.
// CHECK: seq.firreg
// CHECK-NOT: llhd.
// CHECK: hw.output
module clocked(input logic clk, input logic [1:0] index,
               input logic [7:0] data, output logic [31:0] result);
  typedef struct packed {logic [15:0] upper; logic [15:0] lower;} word_t;
  word_t word_value;
  always @(posedge clk) word_value[index * 8 +: 8] <= data;
  assign result = word_value;
endmodule

// DEFAULT-LABEL: hw.module @combinational(
// CHECK-LABEL: hw.module @combinational(
// CHECK-NOT: llhd.
// CHECK-NOT: seq.
// CHECK: hw.output
module combinational(input logic [1:0] index, input logic [7:0] data,
                     output logic [31:0] result);
  typedef struct packed {logic [15:0] upper; logic [15:0] lower;} word_t;
  word_t word_value;
  always_comb begin
    word_value = '0;
    word_value[index * 8 +: 8] = data;
  end
  assign result = word_value;
endmodule

// DEFAULT-LABEL: hw.module @crossing(
// CHECK-LABEL: hw.module @crossing(
// CHECK-NOT: llhd.
// CHECK-NOT: seq.
// CHECK: hw.output
module crossing(input logic [4:0] index, input logic [7:0] data,
                input logic [31:0] initial_value, output logic [31:0] result);
  typedef struct packed {logic [15:0] upper; logic [15:0] lower;} word_t;
  word_t word_value;
  always_comb begin
    word_value = word_t'(initial_value);
    word_value[index +: 8] = data;
  end
  assign result = word_value;
endmodule

// Nested structs and packed arrays must both be flattened to integer leaves.
// DEFAULT-LABEL: hw.module @nested_insert(
// CHECK-LABEL: hw.module @nested_insert(
// CHECK-NOT: llhd.
// CHECK-NOT: seq.
// CHECK: hw.output
module nested_insert(input logic [31:0] data, input int index,
                     output logic [95:0] result);
  typedef struct packed {logic [15:0] upper, lower;} inner_t;
  typedef struct packed {inner_t a; inner_t b; logic [3:0][7:0] c;} word_t;
  function automatic word_t insert_word(logic [31:0] value, int offset);
    insert_word = 'x;
    insert_word[offset * 32 +: 32] = value;
  endfunction
  assign result = insert_word(data, index);
endmodule
