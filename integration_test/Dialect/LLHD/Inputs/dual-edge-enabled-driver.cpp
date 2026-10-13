// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include "Venabled.h"
#include "verilated.h"
#include <iostream>

int main(int argc, char **argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  Venabled dut{&context};
  unsigned expected = 5;
  auto check = [&]() {
    if (dut.q == expected)
      return true;
    std::cerr << "clk=" << unsigned(dut.clk)
              << " enable=" << unsigned(dut.enable) << " d=" << unsigned(dut.d)
              << ": expected " << expected << ", got " << unsigned(dut.q)
              << '\n';
    return false;
  };
  dut.clk = 0;
  dut.enable = 0;
  dut.d = 0;
  dut.eval();
  if (!check())
    return 1;
  // Sweep all data and enable values on both polarities, with repeated holds.
  for (unsigned round = 0; round < 16; ++round)
    for (unsigned d = 0; d < 8; ++d)
      for (unsigned enable = 0; enable < 2; ++enable)
        for (unsigned edge = 0; edge < 2; ++edge) {
          dut.enable = enable;
          dut.d = d ^ (round & 7);
          dut.eval();
          if (!check())
            return 1;
          if (enable)
            expected = dut.d;
          dut.clk = !dut.clk;
          dut.eval();
          if (!check())
            return 1;
          dut.enable = !enable;
          dut.d ^= 7;
          dut.eval();
          if (!check())
            return 1;
        }
  dut.final();
  std::cout << "512 enabled dual-edge updates and hold checks passed\n";
}
