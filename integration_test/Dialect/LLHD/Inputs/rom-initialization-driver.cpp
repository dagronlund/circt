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
  // Independent source-level values, including the packed word cast and the
  // ascending unpacked index order.
  constexpr unsigned expected[] = {1, 2, 5, 10};
  for (unsigned round = 0; round < 16; ++round)
    for (unsigned i = 0; i < 4; ++i) {
      unsigned address = (3 * i + round) & 3;
      dut.address = address;
      dut.eval();
      if (dut.q != expected[address]) {
        std::cerr << "address=" << address << ": expected " << expected[address]
                  << ", got " << unsigned(dut.q) << '\n';
        return 1;
      }
    }
  dut.final();
  std::cout << "All four ROM entries and address transitions passed\n";
}
