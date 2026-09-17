// RUN: circt-verilog %s | FileCheck %s --check-prefix=DEFAULT
// RUN: circt-verilog --sroa %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=moore.
// REQUIRES: slang
// UNSUPPORTED: valgrind

// Repeated calls expand the dynamic struct writes into chains of diamonds.
// Process lowering must not merge these into exponentially large argument lists.
// DEFAULT-LABEL: hw.module @top(
// DEFAULT-NOT: llhd.process
// DEFAULT: hw.output
// CHECK-LABEL: hw.module @top(
// CHECK-SAME: in %state : i2, in %data : i6, in %valid : i1, out a : i1, out b : i1, out c : i1
// CHECK: hw.output {{.*}} : i1, i1, i1
module top(input logic [1:0] state, input logic [5:0] data, input logic valid,
           output logic a, b, c);
  typedef struct packed {logic [5:0] x, y, z;} header_t;
  function automatic header_t insert(logic [5:0] word, int index);
    insert = 'x;
    insert[6 * index +: 6] = word;
  endfunction
  header_t header;
  always_comb begin
    header = 'x;
    a = 0;
    b = 0;
    c = 0;
    case (state)
      0: begin header = insert(data, 0); a = valid; end
      1: begin header = insert(data, 1); b = valid; end
      2: begin header = insert(data, 2); c = valid; end
      default: ;
    endcase
  end
endmodule
