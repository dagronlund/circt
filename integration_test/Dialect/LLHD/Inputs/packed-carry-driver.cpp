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
    unsigned actual = (unsigned(dut.cout) << 2) | dut.sum;
    if (actual == expected)
      return true;
    std::cerr << "clear=" << unsigned(dut.clear) << " cin=" << unsigned(dut.cin)
              << " a=" << unsigned(dut.a) << " b=" << unsigned(dut.b)
              << ": expected " << expected << ", got " << actual << '\n';
    return false;
  };

  // Establish known state through a synchronous clear.
  dut.clk = 0;
  dut.clear = 1;
  dut.cin = 0;
  dut.a = 0;
  dut.b = 0;
  dut.eval();
  dut.clk = 1;
  dut.eval();
  if (!check())
    return 1;
  for (unsigned clear = 0; clear < 2; ++clear)
    for (unsigned cin = 0; cin < 2; ++cin)
      for (unsigned a = 0; a < 4; ++a)
        for (unsigned b = 0; b < 4; ++b) {
          dut.clk = 0;
          dut.clear = clear;
          dut.cin = cin;
          dut.a = a;
          dut.b = b;
          dut.eval();
          if (!check())
            return 1;
          expected = clear ? 0 : a + b + cin;
          dut.clk = 1;
          dut.eval();
          if (!check())
            return 1;
          // Neither input changes nor a falling edge may change the outputs.
          dut.clear = !clear;
          dut.cin = !cin;
          dut.a = a ^ 3;
          dut.b = b ^ 3;
          dut.eval();
          if (!check())
            return 1;
          dut.clk = 0;
          dut.eval();
          if (!check())
            return 1;
        }
  dut.final();
  std::cout << "64 carry combinations and synchronous timing checks passed\n";
}
