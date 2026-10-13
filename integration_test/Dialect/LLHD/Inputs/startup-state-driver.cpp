// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include "Vtop.h"
#include "verilated.h"
#include <iostream>

int main(int argc, char **argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  Vtop dut{&context};
  unsigned expected = 0x5B;
  auto check = [&]() {
    if (dut.q == expected)
      return true;
    std::cerr << "expected " << expected << ", got " << unsigned(dut.q) << '\n';
    return false;
  };
  dut.clk = 0;
  dut.enable = 0;
  dut.eval();
  if (!check())
    return 1;
  for (unsigned cycle = 0; cycle < 1024; ++cycle) {
    dut.clk = 0;
    dut.enable = cycle % 3 != 0;
    dut.eval();
    if (!check())
      return 1;
    if (dut.enable)
      expected =
          ((expected << 1) | (((expected >> 7) ^ (expected >> 5)) & 1)) & 255;
    dut.clk = 1;
    dut.eval();
    if (!check())
      return 1;
    // Changing enable or observing a falling edge must not change state.
    dut.enable = !dut.enable;
    dut.eval();
    if (!check())
      return 1;
    dut.clk = 0;
    dut.eval();
    if (!check())
      return 1;
  }
  dut.final();
  std::cout << "Startup value 0x5B and 1024 enabled feedback cycles passed\n";
}
