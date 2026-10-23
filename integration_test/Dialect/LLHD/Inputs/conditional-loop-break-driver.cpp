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
  auto check = [&](unsigned inputs) {
    dut.enable = inputs >> 1;
    dut.eop = inputs & 1;
    dut.eval();
    unsigned expected = dut.enable ? 1 : 0;
    if (dut.produce == expected)
      return true;
    std::cerr << "enable=" << unsigned(dut.enable)
              << " eop=" << unsigned(dut.eop) << ": expected " << expected
              << ", got " << dut.produce << '\n';
    return false;
  };
  // Exercise all input combinations and all transitions between them.
  for (unsigned previous = 0; previous < 4; ++previous)
    for (unsigned next = 0; next < 4; ++next)
      if (!check(previous) || !check(next))
        return 1;
  dut.final();
  std::cout << "All conditional loop-break combinations passed\n";
}
