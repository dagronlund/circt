// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-verilog --ir-llhd %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=cf. --implicit-check-not=arith. --implicit-check-not=seq.
// REQUIRES: slang

// Exercise bounded recurrences, comparisons, and control flow through every
// formal entry point. The integration test checks all 256 input combinations.
// CHECK-LABEL: hw.module @top(
// CHECK: hw.output
module top (
  input logic [7:0] a,
  output logic [31:0] q_unsigned_lt,
  output logic [31:0] q_unsigned_le,
  output logic [31:0] q_unsigned_down_gt,
  output logic [31:0] q_unsigned_down_ge,
  output logic [31:0] q_signed_down,
  output logic [31:0] q_signed_ne,
  output logic [31:0] q_unsigned_ne,
  output logic [31:0] q_signed_step,
  output logic [31:0] q_unsigned_step,
  output logic [31:0] q_signed_narrow,
  output logic [31:0] q_signed_narrow_negative,
  output logic [31:0] q_unsigned_narrow_down,
  output logic [31:0] q_unsigned_narrow_ne,
  output logic [31:0] q_reversed_lt,
  output logic [31:0] q_reversed_down,
  output logic [31:0] q_while_up,
  output logic [31:0] q_do_up,
  output logic [31:0] q_do_once,
  output logic [31:0] q_do_break,
  output logic [31:0] q_repeat_const,
  output logic [31:0] q_repeat_zero,
  output logic [31:0] q_foreach_packed,
  output logic [31:0] q_continue,
  output logic [31:0] q_continue_break,
  output logic [31:0] q_nested,
  output logic [31:0] q_triangular,
  output logic [31:0] q_compound_or,
  output logic [31:0] q_compound_or_ranges,
  output logic [31:0] q_neq_step,
  output logic [31:0] q_countdown_ne,
  output logic [31:0] q_mul_step,
  output logic [31:0] q_shift_step,
  output logic [31:0] q_divide_step,
  output logic [31:0] q_body_increment,
  output logic [31:0] q_do_continue,
  output logic [31:0] q_repeat_break,
  output logic [31:0] q_repeat_continue,
  output logic [31:0] q_case_body,
  output logic [31:0] q_nested_break,
  output logic [31:0] q_multiple_counters,
  output logic [31:0] q_multiple_counter_bound,
  output logic [31:0] q_wrap_exit,
  output logic [31:0] q_signed_wrap_exit,
  output logic [31:0] q_descending_shift,
  output logic [31:0] q_signed_negative_down,
  output logic [31:0] q_equality,
  output logic [31:0] q_bitmask_condition,
  output logic [31:0] q_logical_not,
  output logic [31:0] q_do_compound_guard,
  output logic [31:0] q_repeat_nested,
  output logic [31:0] q_param_bound,
  output logic [31:0] q_divide_signed,
  output logic [31:0] q_nonlinear_add,
  output logic [31:0] q_xor_update
);

  always_comb begin
    q_unsigned_lt = '0;
    for (logic [31:0] i = 0; i < 4; i++) q_unsigned_lt += a[i];
  end

  always_comb begin
    q_unsigned_le = '0;
    for (logic [31:0] i = 0; i <= 3; i++) q_unsigned_le += a[i];
  end

  always_comb begin
    q_unsigned_down_gt = '0;
    for (logic [31:0] i = 4; i > 0; i--) q_unsigned_down_gt += a[i - 1];
  end

  always_comb begin
    q_unsigned_down_ge = '0;
    for (logic [31:0] i = 3; i >= 1; i--) q_unsigned_down_ge += a[i];
  end

  always_comb begin
    q_signed_down = '0;
    for (integer i = 3; i >= 0; i--) q_signed_down += a[i];
  end

  always_comb begin
    q_signed_ne = '0;
    for (integer i = 0; i != 4; i++) q_signed_ne += a[i];
  end

  always_comb begin
    q_unsigned_ne = '0;
    for (logic [31:0] i = 0; i != 4; i++) q_unsigned_ne += a[i];
  end

  always_comb begin
    q_signed_step = '0;
    for (integer i = 0; i < 8; i += 2) q_signed_step += a[i];
  end

  always_comb begin
    q_unsigned_step = '0;
    for (logic [31:0] i = 0; i < 8; i += 2) q_unsigned_step += a[i];
  end

  always_comb begin
    q_signed_narrow = '0;
    for (logic signed [3:0] i = 0; i < 4; i++) q_signed_narrow += a[i];
  end

  always_comb begin
    q_signed_narrow_negative = '0;
    for (logic signed [3:0] i = -3; i < 1; i++)
      q_signed_narrow_negative += a[i + 3];
  end

  always_comb begin
    q_unsigned_narrow_down = '0;
    for (logic [3:0] i = 4; i > 0; i--) q_unsigned_narrow_down += a[i - 1];
  end

  always_comb begin
    q_unsigned_narrow_ne = '0;
    for (logic [3:0] i = 0; i != 4; i++) q_unsigned_narrow_ne += a[i];
  end

  always_comb begin
    q_reversed_lt = '0;
    for (integer i = 0; 4 > i; i++) q_reversed_lt += a[i];
  end

  always_comb begin
    q_reversed_down = '0;
    for (integer i = 4; 0 < i; i--) q_reversed_down += a[i - 1];
  end

  always_comb begin
    integer i;
    q_while_up = '0;
    i = 0;
    while (i < 4) begin
      q_while_up += a[i];
      i++;
    end
  end

  always_comb begin
    integer i;
    q_do_up = '0;
    i = 0;
    do begin
      q_do_up += a[i];
      i++;
    end while (i < 4);
  end

  always_comb begin
    integer i;
    q_do_once = '0;
    i = 0;
    do begin
      q_do_once += a[i];
      i++;
    end while (i < 0);
  end

  always_comb begin
    integer i;
    q_do_break = '0;
    i = 0;
    do begin
      q_do_break += a[i];
      if (a[i]) break;
      i++;
    end while (i < 4);
  end

  always_comb begin
    q_repeat_const = '0;
    repeat (4) q_repeat_const += a[0];
  end

  always_comb begin
    q_repeat_zero = '0;
    repeat (0) q_repeat_zero += a[0];
  end

  always_comb begin
    q_foreach_packed = '0;
    foreach (a[i]) q_foreach_packed += a[i];
  end

  always_comb begin
    q_continue = '0;
    for (integer i = 0; i < 4; i++) begin
      if (!a[i]) continue;
      q_continue += i + 1;
    end
  end

  always_comb begin
    q_continue_break = '0;
    for (integer i = 0; i < 4; i++) begin
      if (!a[i]) continue;
      q_continue_break += i + 1;
      if (a[i + 1]) break;
    end
  end

  always_comb begin
    q_nested = '0;
    for (integer i = 0; i < 4; i++)
      for (integer j = 0; j < 2; j++) q_nested += a[i + j];
  end

  always_comb begin
    q_triangular = '0;
    for (integer i = 0; i < 4; i++)
      for (integer j = 0; j < i; j++) q_triangular += a[i + j];
  end

  always_comb begin
    q_compound_or = '0;
    for (integer i = 0; i < 2 || i < 4; i++) q_compound_or += a[i];
  end

  always_comb begin
    q_compound_or_ranges = '0;
    for (integer i = 0; (i >= 0 && i < 2) || (i >= 2 && i < 4); i++)
      q_compound_or_ranges += a[i];
  end

  always_comb begin
    q_neq_step = '0;
    for (integer i = 0; i != 6; i += 2) q_neq_step += a[i];
  end

  always_comb begin
    q_countdown_ne = '0;
    for (integer i = 4; i != 0; i--) q_countdown_ne += a[i - 1];
  end

  always_comb begin
    q_mul_step = '0;
    for (integer i = 1; i < 8; i *= 2) q_mul_step += a[i];
  end

  always_comb begin
    q_shift_step = '0;
    for (integer i = 1; i < 8; i <<= 1) q_shift_step += a[i];
  end

  always_comb begin
    q_divide_step = '0;
    for (integer i = 8; i > 0; i /= 2) q_divide_step += a[i - 1];
  end

  always_comb begin
    integer i;
    q_body_increment = '0;
    i = 0;
    while (i < 4) begin
      i++;
      q_body_increment += a[i - 1];
    end
  end

  always_comb begin
    integer i;
    q_do_continue = '0;
    i = 0;
    do begin
      i++;
      if (!a[i - 1]) continue;
      q_do_continue += i;
    end while (i < 4);
  end

  always_comb begin
    q_repeat_break = '0;
    repeat (4) begin
      q_repeat_break += a[0];
      if (a[1]) break;
    end
  end

  always_comb begin
    q_repeat_continue = '0;
    repeat (4) begin
      if (a[1]) continue;
      q_repeat_continue += a[0];
    end
  end

  always_comb begin
    q_case_body = '0;
    for (integer i = 0; i < 4; i++) begin
      case (a[i+:2])
        0: q_case_body += 1;
        1: q_case_body += 2;
        default: q_case_body += 3;
      endcase
    end
  end

  always_comb begin
    q_nested_break = '0;
    for (integer i = 0; i < 4; i++)
      for (integer j = 0; j < 2; j++) begin
        q_nested_break += a[i + j];
        if (a[j]) break;
      end
  end

  always_comb begin
    q_multiple_counters = '0;
    for (integer i = 0, j = 3; i < 4; i++, j--) q_multiple_counters += a[i + j];
  end

  always_comb begin
    q_multiple_counter_bound = '0;
    for (integer i = 0, j = 4; i < j; i++, j--)
      q_multiple_counter_bound += a[i + j];
  end

  always_comb begin
    q_wrap_exit = '0;
    for (logic [2:0] i = 6; i != 1; i++) q_wrap_exit += a[i];
  end

  always_comb begin
    q_signed_wrap_exit = '0;
    for (logic signed [2:0] i = 2; i != -2; i++)
      q_signed_wrap_exit += a[$unsigned(i)];
  end

  always_comb begin
    q_descending_shift = '0;
    for (integer i = 8; i != 0; i >>= 1) q_descending_shift += a[i - 1];
  end

  always_comb begin
    q_signed_negative_down = '0;
    for (logic signed [3:0] i = -1; i >= -4; i--)
      q_signed_negative_down += a[-i - 1];
  end

  always_comb begin
    q_equality = '0;
    for (integer i = 0; i == 0; i++) q_equality += a[0];
  end

  always_comb begin
    q_bitmask_condition = '0;
    for (integer i = 0; !(i & 4); i++) q_bitmask_condition += a[i];
  end

  always_comb begin
    q_logical_not = '0;
    for (integer i = 4; i; i--) q_logical_not += a[i - 1];
  end

  always_comb begin
    integer i;
    q_do_compound_guard = '0;
    i = 0;
    do begin
      q_do_compound_guard += a[i];
      i++;
    end while (i < 4 && a[i]);
  end

  always_comb begin
    q_repeat_nested = '0;
    repeat (2) repeat (2) q_repeat_nested += a[0];
  end

  always_comb begin
    q_param_bound = '0;
    for (integer i = 0; i < $bits(a) / 2; i++) q_param_bound += a[i];
  end

  always_comb begin
    q_divide_signed = '0;
    for (integer i = -8; i < 0; i /= 2) q_divide_signed += a[-i - 1];
  end

  always_comb begin
    q_nonlinear_add = '0;
    for (integer i = 0; i < 4; i = i * 2 + 1) q_nonlinear_add += a[i];
  end

  always_comb begin
    q_xor_update = '0;
    for (logic [2:0] i = 3'b001; i != 3'b100; i = {i[1:0], i[2] ^ i[0]})
      q_xor_update += a[i];
  end
endmodule
