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
  unsigned expected = 0;
  auto check = [&]() {
    if (dut.q == expected)
      return true;
    std::cerr << "rst=" << unsigned(dut.rst)
              << " enable=" << unsigned(dut.enable) << " d=" << unsigned(dut.d)
              << ": expected " << expected << ", got " << unsigned(dut.q)
              << '\n';
    return false;
  };

  // Establish known state with synchronous reset.
  dut.clk = 0;
  dut.rst = 1;
  dut.enable = 0;
  dut.d = 0;
  dut.eval();
  dut.clk = 1;
  dut.eval();
  if (!check())
    return 1;
  for (unsigned previous = 0; previous < 16; ++previous)
    for (unsigned rst = 0; rst < 2; ++rst)
      for (unsigned enable = 0; enable < 2; ++enable)
        for (unsigned d = 0; d < 16; ++d) {
          // Start each case with a chosen stored value.
          dut.clk = 0;
          dut.rst = 0;
          dut.enable = 1;
          dut.d = previous;
          dut.eval();
          if (!check())
            return 1;
          expected = previous;
          dut.clk = 1;
          dut.eval();
          if (!check())
            return 1;
          dut.clk = 0;
          dut.rst = rst;
          dut.enable = enable;
          dut.d = d;
          dut.eval();
          if (!check())
            return 1;
          expected = rst ? 0 : enable ? d : previous;
          dut.clk = 1;
          dut.eval();
          if (!check())
            return 1;
          // Reset and input changes between edges must leave state unchanged.
          dut.rst = !rst;
          dut.enable = !enable;
          dut.d = d ^ 15;
          dut.eval();
          if (!check())
            return 1;
          dut.clk = 0;
          dut.eval();
          if (!check())
            return 1;
        }
  dut.final();
  std::cout << "1024 enabled array transitions and synchronous timing checks "
               "passed\n";
}
