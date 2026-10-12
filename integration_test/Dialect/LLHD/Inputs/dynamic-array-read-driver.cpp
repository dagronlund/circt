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
  for (unsigned a = 0; a < 16; ++a)
    for (unsigned b = 0; b < 16; ++b)
      for (unsigned sel = 0; sel < 2; ++sel) {
        dut.a = a;
        dut.b = b;
        dut.sel = sel;
        dut.eval();
        unsigned expected = sel ? b : a;
        if (dut.q != expected) {
          std::cerr << "a=" << a << " b=" << b << " sel=" << sel
                    << ": expected " << expected << ", got " << unsigned(dut.q)
                    << '\n';
          return 1;
        }
      }
  dut.final();
  std::cout << "512 dynamic array read combinations passed\n";
}
