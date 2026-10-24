//===- bounded-loop-patterns-driver.cpp
//------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "Vtop.h"
#include "verilated.h"
#include <cstdio>

static unsigned bit(unsigned a, unsigned i) { return (a >> i) & 1; }
static unsigned popcount(unsigned a) { return __builtin_popcount(a); }
static unsigned weighted(unsigned a, unsigned limit) {
  unsigned sum = 0;
  for (unsigned i = 0; i < limit; ++i)
    sum += bit(a, i) * (i + 1);
  return sum;
}
static unsigned firstPair(unsigned a) {
  unsigned pairs = a & (a >> 1) & 0xf;
  return pairs ? __builtin_ctz(pairs) + 1 : 4;
}

static unsigned caseCount(unsigned a) {
  static const unsigned counts[] = {1, 2, 3, 3};
  unsigned sum = 0;
  for (unsigned i = 0; i < 4; ++i)
    sum += counts[(a >> i) & 3];
  return sum;
}

static bool check(Vtop &dut, unsigned a) {
  dut.a = a;
  dut.eval();
#define CHECK_CASE(name, expected)                                             \
  if (dut.q_##name != unsigned(expected)) {                                    \
    std::fprintf(stderr, #name ": a=%u: expected %u, got %u\n", a,             \
                 unsigned(expected), unsigned(dut.q_##name));                  \
    return false;                                                              \
  }
  CHECK_CASE(unsigned_lt, popcount(a & 0xf));
  CHECK_CASE(unsigned_le, popcount(a & 0xf));
  CHECK_CASE(unsigned_down_gt, popcount(a & 0xf));
  CHECK_CASE(unsigned_down_ge, popcount((a >> 1) & 7));
  CHECK_CASE(signed_down, popcount(a & 0xf));
  CHECK_CASE(signed_ne, popcount(a & 0xf));
  CHECK_CASE(unsigned_ne, popcount(a & 0xf));
  CHECK_CASE(signed_step, popcount(a & 0x55));
  CHECK_CASE(unsigned_step, popcount(a & 0x55));
  CHECK_CASE(signed_narrow, popcount(a & 0xf));
  CHECK_CASE(signed_narrow_negative, popcount(a & 0xf));
  CHECK_CASE(unsigned_narrow_down, popcount(a & 0xf));
  CHECK_CASE(unsigned_narrow_ne, popcount(a & 0xf));
  CHECK_CASE(reversed_lt, popcount(a & 0xf));
  CHECK_CASE(reversed_down, popcount(a & 0xf));
  CHECK_CASE(while_up, popcount(a & 0xf));
  CHECK_CASE(do_up, popcount(a & 0xf));
  CHECK_CASE(do_once, a & 1);
  CHECK_CASE(do_break, (a & 0xf) != 0);
  CHECK_CASE(repeat_const, 4 * (a & 1));
  CHECK_CASE(repeat_zero, 0);
  CHECK_CASE(foreach_packed, popcount(a));
  CHECK_CASE(continue, weighted(a, 4));
  CHECK_CASE(continue_break, weighted(a, firstPair(a)));
  CHECK_CASE(nested,
             bit(a, 0) + 2 * (bit(a, 1) + bit(a, 2) + bit(a, 3)) + bit(a, 4));
  CHECK_CASE(triangular,
             bit(a, 1) + bit(a, 2) + 2 * bit(a, 3) + bit(a, 4) + bit(a, 5));
  CHECK_CASE(compound_or, popcount(a & 0xf));
  CHECK_CASE(compound_or_ranges, popcount(a & 0xf));
  CHECK_CASE(neq_step, popcount(a & 0x15));
  CHECK_CASE(countdown_ne, popcount(a & 0xf));
  CHECK_CASE(mul_step, popcount(a & 0x16));
  CHECK_CASE(shift_step, popcount(a & 0x16));
  CHECK_CASE(divide_step, popcount(a & 0x8b));
  CHECK_CASE(body_increment, popcount(a & 0xf));
  CHECK_CASE(do_continue, weighted(a, 4));
  CHECK_CASE(repeat_break, (bit(a, 1) ? 1 : 4) * bit(a, 0));
  CHECK_CASE(repeat_continue, bit(a, 1) ? 0 : 4 * bit(a, 0));
  CHECK_CASE(case_body, caseCount(a));
  CHECK_CASE(nested_break,
             popcount(a & 0xf) + (bit(a, 0) ? 0 : popcount((a >> 1) & 0xf)));
  CHECK_CASE(multiple_counters, 4 * bit(a, 3));
  CHECK_CASE(multiple_counter_bound, 2 * bit(a, 4));
  CHECK_CASE(wrap_exit, popcount(a & 0xc1));
  CHECK_CASE(signed_wrap_exit, popcount(a & 0x3c));
  CHECK_CASE(descending_shift, popcount(a & 0x8b));
  CHECK_CASE(signed_negative_down, popcount(a & 0xf));
  CHECK_CASE(equality, bit(a, 0));
  CHECK_CASE(bitmask_condition, popcount(a & 0xf));
  CHECK_CASE(logical_not, popcount(a & 0xf));
  CHECK_CASE(do_compound_guard,
             bit(a, 0) + (bit(a, 1) ? 1 + (bit(a, 2) ? 1 + bit(a, 3) : 0) : 0));
  CHECK_CASE(repeat_nested, 4 * bit(a, 0));
  CHECK_CASE(param_bound, popcount(a & 0xf));
  CHECK_CASE(divide_signed, popcount(a & 0x8b));
  CHECK_CASE(nonlinear_add, popcount(a & 0xb));
  CHECK_CASE(xor_update, popcount(a & 0xee));
#undef CHECK_CASE
  return true;
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  Vtop dut;
  // Exhaust every input pair to check that no state survives between
  // evaluations.
  for (unsigned before = 0; before < 256; ++before)
    for (unsigned after = 0; after < 256; ++after)
      if (!check(dut, before) || !check(dut, after))
        return 1;
  std::puts("All bounded-loop combinations and transitions passed");
  return 0;
}
