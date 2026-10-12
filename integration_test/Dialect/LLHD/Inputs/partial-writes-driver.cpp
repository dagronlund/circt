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
    std::cerr << "read_enable=" << unsigned(dut.read_enable)
              << " write_enable=" << unsigned(dut.write_enable)
              << " old_data=" << unsigned(dut.old_data)
              << " write_data=" << unsigned(dut.write_data) << ": expected "
              << expected << ", got " << unsigned(dut.q) << '\n';
    return false;
  };

  // Establish known state through a read, without assuming an initial value.
  dut.clk = 0;
  dut.read_enable = 1;
  dut.write_enable = 0;
  dut.old_data = 0;
  dut.write_data = 0;
  dut.eval();
  dut.clk = 1;
  dut.eval();
  if (!check())
    return 1;

  for (unsigned enables = 0; enables < 4; ++enables)
    for (unsigned oldData = 0; oldData < 256; ++oldData)
      for (unsigned writeData = 0; writeData < 256; ++writeData) {
        dut.clk = 0;
        dut.read_enable = 1;
        dut.write_enable = enables;
        dut.old_data = oldData;
        dut.write_data = writeData;
        dut.eval();
        if (!check())
          return 1;
        unsigned mask = (enables & 1 ? 0x0f : 0) | (enables & 2 ? 0xf0 : 0);
        expected = (oldData & ~mask) | (writeData & mask);
        dut.clk = 1;
        dut.eval();
        if (!check())
          return 1;

        // Inputs may change while the clock is high. Disabling the read must
        // also hold the register through the falling and next rising edge.
        dut.read_enable = 0;
        dut.write_enable = enables ^ 3;
        dut.old_data = oldData ^ 255;
        dut.write_data = writeData ^ 255;
        dut.eval();
        if (!check())
          return 1;
        dut.clk = 0;
        dut.eval();
        if (!check())
          return 1;
        dut.clk = 1;
        dut.eval();
        if (!check())
          return 1;
      }
  dut.final();
  std::cout
      << "262144 partial-write combinations and register hold checks passed\n";
}
