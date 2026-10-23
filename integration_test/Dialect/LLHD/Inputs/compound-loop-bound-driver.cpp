// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include "Vtop.h"
#include "verilated.h"
#include <iostream>

#ifndef MAX_BITS
#define MAX_BITS 3
#endif

int main(int argc, char **argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  Vtop dut{&context};
  auto check = [&](unsigned data) {
    dut.data = data;
    dut.eval();
    unsigned expected = 0;
    while (expected < MAX_BITS && (data & (1u << expected)))
      ++expected;
    if (dut.count == expected)
      return true;
    std::cerr << "data=" << data << ": expected " << expected << ", got "
              << unsigned(dut.count) << '\n';
    return false;
  };
  for (unsigned previous = 0; previous < 16; ++previous)
    for (unsigned next = 0; next < 16; ++next)
      if (!check(previous) || !check(next))
        return 1;
  dut.final();
  std::cout << "All compound-bound input combinations and transitions passed\n";
}
