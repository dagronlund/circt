// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Directed fill/stall/drain and replacement traffic followed by deterministic
// traffic respecting the producer stability assumptions. Every cover must hit.
#include "Vstream_stage_formal.h"
#include "verilated.h"
#include "verilated_cov.h"
#include <cstdint>
#include <iostream>

int main(int argc, char **argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  Vstream_stage_formal dut{&context};
  bool valid = false, hold = false;
  unsigned heldPayload = 0;
  uint32_t random = 42;
  for (unsigned cycle = 0; cycle < 10000; ++cycle) {
    unsigned inValid = 0, payload = 0, ready = 0;
    if (cycle == 1 || cycle == 6 || cycle == 7) {
      inValid = 1;
      payload = cycle;
    }
    if (cycle == 4 || cycle >= 6)
      ready = 1;
    if (cycle >= 9) {
      random = random * 1664525u + 1013904223u;
      ready = (random >> 17) & 1;
      inValid = hold || ((random >> 18) & 1);
      payload = hold ? heldPayload : (random >> 20) & 15;
    }
    dut.clk = 0;
    dut.rst = cycle == 0;
    dut.in_valid = inValid;
    dut.in_payload = payload;
    dut.out_ready = ready;
    dut.eval();
    context.timeInc(1);
    bool canPush = !valid || ready;
    bool push = inValid && canPush;
    hold = inValid && !canPush;
    heldPayload = payload;
    if (cycle == 0)
      valid = false;
    else if (push || ready)
      valid = push;
    dut.clk = 1;
    dut.eval();
    context.timeInc(1);
  }
  dut.final();
  context.coveragep()->write(argv[1]);
  std::cout << "10000 constrained stream-stage cycles passed\n";
}
