// RUN: circt-verilog %s | FileCheck %s
// REQUIRES: slang
// UNSUPPORTED: valgrind

// A compound assignment reads and writes the same dynamic struct bit reference.
// CHECK-LABEL: hw.module @top
// CHECK: hw.output
module top(input logic [1:0] data, input logic index,
           output logic [1:0] result);
  struct packed { logic a; logic b; } value;
  always_comb begin
    value = '0;
    value[index] |= data[index];
  end
  assign result = value;
endmodule
