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
  for (unsigned request = 0; request < 4; ++request) {
    dut.request = request;
    dut.eval();
    unsigned expected = request & 1 ? 1 : request & 2;
    if (dut.grant != expected) {
      std::cerr << "request=" << request << ": expected " << expected
                << ", got " << unsigned(dut.grant) << '\n';
      return 1;
    }
  }
  dut.final();
  std::cout << "All priority-grant combinations passed\n";
}
