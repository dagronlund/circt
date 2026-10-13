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
  dut.clk = 0;
  dut.eval();
  unsigned expected = 1;
  auto check = [&]() {
    if (dut.clk_div == expected)
      return true;
    std::cerr << "clk=" << unsigned(dut.clk) << ": expected " << expected
              << ", got " << unsigned(dut.clk_div) << '\n';
    return false;
  };
  if (!check())
    return 1;
  for (unsigned edge = 0; edge < 256; ++edge) {
    // No event occurs when the clock value remains unchanged.
    dut.eval();
    if (!check())
      return 1;
    dut.clk = !dut.clk;
    expected ^= 1;
    dut.eval();
    if (!check())
      return 1;
    dut.eval();
    if (!check())
      return 1;
  }
  dut.final();
  std::cout << "Initial value 1 and 256 alternating clock edges passed\n";
}
