// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include "Vtop.h"
#include "verilated.h"
#include <iostream>

#ifndef DATA_WIDTH
#define DATA_WIDTH 1
#endif

int main(int argc, char **argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  Vtop dut{&context};
  constexpr unsigned mask = (1u << DATA_WIDTH) - 1;
  unsigned expected = 0;
  auto check = [&]() {
    if (dut.y == expected)
      return true;
    std::cerr << "clk=" << unsigned(dut.clk) << " d=" << unsigned(dut.d)
              << ": expected " << expected << ", got " << unsigned(dut.y)
              << '\n';
    return false;
  };

  // Establish state through a clock edge, without assuming a startup value.
  dut.clk = 0;
  dut.d = 0;
  dut.eval();
  dut.clk = 1;
  dut.eval();
  if (!check())
    return 1;

  for (unsigned previous = 0; previous <= mask; ++previous)
    for (unsigned next = 0; next <= mask; ++next) {
      dut.clk = 0;
      dut.d = previous;
      dut.eval();
      if (!check())
        return 1;
      dut.clk = 1;
      dut.eval();
      expected = previous;
      if (!check())
        return 1;

      // Data changes and falling edges must not update the child registers.
      dut.d = next;
      dut.eval();
      if (!check())
        return 1;
      dut.clk = 0;
      dut.eval();
      if (!check())
        return 1;
      dut.d = next ^ mask;
      dut.eval();
      if (!check())
        return 1;
      dut.d = next;
      dut.eval();
      if (!check())
        return 1;
      dut.clk = 1;
      dut.eval();
      expected = next;
      if (!check())
        return 1;
      dut.d = next ^ mask;
      dut.eval();
      if (!check())
        return 1;
    }
  dut.final();
  std::cout << "All hierarchical register traces passed\n";
}
