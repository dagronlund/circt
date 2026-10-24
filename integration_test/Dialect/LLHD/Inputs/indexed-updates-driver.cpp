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
    unsigned a = inputs >> 3;
    unsigned b = inputs & 7;
    dut.a = a;
    dut.b = b;
    dut.eval();
    bool upper = (a & 6) == 6;
    bool lower = (a & 3) == 3;
    unsigned expectedX = upper || lower;
    unsigned expectedY = upper ? b >> 1 : lower ? b & 3 : 0;
    if (dut.x == expectedX && dut.y == expectedY)
      return true;
    std::cerr << "a=" << a << " b=" << b << ": expected x=" << expectedX
              << " y=" << expectedY << ", got x=" << unsigned(dut.x)
              << " y=" << unsigned(dut.y) << '\n';
    return false;
  };
  for (unsigned previous = 0; previous < 64; ++previous)
    for (unsigned next = 0; next < 64; ++next)
      if (!check(previous) || !check(next))
        return 1;
  dut.final();
  std::cout << "All indexed-update combinations and transitions passed\n";
}
