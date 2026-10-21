//===- aggregate-drivers.cpp - Check independently driven aggregates
//--------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "Vchecks.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  Vchecks model;
  unsigned transitions = 0;
  uint16_t previous = 0;
  bool valid = false;
  for (unsigned enable = 0; enable < 4; ++enable) {
    for (unsigned data = 0; data < 65536; ++data) {
      model.clk = 0;
      model.enable = enable;
      model.a = data | ((data ^ 0xa55au) << 16);
      model.b = ~model.a;
      model.d = data;
      model.eval();
      uint32_t expectedComb = ((enable & 1 ? model.b : model.a) & 0xffffu) |
                              ((enable & 2 ? model.b : model.a) & 0xffff0000u);
      if (model.comb_q != expectedComb ||
          (valid && model.struct_q != previous)) {
        std::fprintf(stderr, "Incorrect aggregate output before rising edge\n");
        return 1;
      }
      model.clk = 1;
      model.eval();
      if (model.struct_q != data) {
        std::fprintf(stderr, "Incorrect word order or rising-edge update\n");
        return 1;
      }
      // Input changes while the clock is high must not reach the registers.
      model.d = data ^ 0xffffu;
      model.eval();
      if (model.struct_q != data) {
        std::fprintf(stderr, "Register changed without a rising edge\n");
        return 1;
      }
      model.clk = 0;
      model.eval();
      if (model.struct_q != data) {
        std::fprintf(stderr, "Register changed on falling edge\n");
        return 1;
      }
      previous = data;
      valid = true;
      ++transitions;
    }
  }
  std::printf(
      "%u aggregate driver transitions and clock timing checks passed\n",
      transitions);
  return 0;
}
