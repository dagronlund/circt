// RUN: circt-verilog %s | FileCheck %s
// RUN: circt-verilog --sroa %s | FileCheck %s
// REQUIRES: slang
// UNSUPPORTED: valgrind

// A compound assignment reads and writes the same packed-struct bit reference.
// CHECK-LABEL: hw.module @top(
// CHECK: hw.output
module top(input logic [3:0] data, input logic [1:0] shift,
           output logic [3:0] result);
  typedef struct packed {logic [2:0] fraction; logic sticky;} word_t;

  function automatic word_t sticky_shift(word_t value, logic [1:0] amount);
    word_t shifted[4];
    for (int i = 0; i < 4; i++) begin
      shifted[i] = value >> i;
      for (int j = 0; j < i; j++)
        shifted[i][0] |= value[1+j];
    end
    return shifted[amount];
  endfunction

  assign result = sticky_shift(data, shift);
endmodule

// Also read and update a slice spanning multiple struct fields.
// CHECK-LABEL: hw.module @crossing(
// CHECK: hw.output
module crossing(input logic [7:0] data, input logic [3:0] mask,
                output logic [7:0] result);
  typedef struct packed {logic [3:0] upper, lower;} word_t;
  word_t value;
  always_comb begin
    value = word_t'(data);
    value[5:2] ^= mask;
  end
  assign result = value;
endmodule
