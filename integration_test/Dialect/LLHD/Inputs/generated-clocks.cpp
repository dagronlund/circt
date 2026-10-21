//===- generated-clocks.cpp - Check formal clock edges
//---------------------===//
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
  model.clk = 0;
  model.clocks = 0;
  model.d = 0;
  model.eval();

  // Infer each unconstrained counter's phase from its first two samples.
  // All four initial states have distinct pairs: 00, 01, 11, and 10.
  unsigned counter[2];
  unsigned initializedCounter[2] = {0, 1};
  for (unsigned lane = 0; lane < 2; ++lane) {
    model.clocks ^= 1u << lane;
    model.eval();
    if (((model.initialized_q >> lane) & 1) !=
        (initializedCounter[lane] >> 1)) {
      std::fprintf(stderr,
                   "Incorrect initialized counter sample for lane %u: got %u, "
                   "expected %u\n",
                   lane, (model.initialized_q >> lane) & 1,
                   initializedCounter[lane] >> 1);
      return 1;
    }
    initializedCounter[lane] = (initializedCounter[lane] + 1) & 3;
    unsigned first = (model.generated_q >> lane) & 1;
    model.clocks ^= 1u << lane;
    model.eval();
    if (((model.initialized_q >> lane) & 1) !=
        (initializedCounter[lane] >> 1)) {
      std::fprintf(stderr, "Counter sample used the updated value\n");
      return 1;
    }
    initializedCounter[lane] = (initializedCounter[lane] + 1) & 3;
    unsigned second = (model.generated_q >> lane) & 1;
    counter[lane] = (2 * first + (first ^ second) + 2) & 3;
  }

  unsigned clocks = model.clocks;
  unsigned expectedGenerated = model.generated_q;
  unsigned expectedInitialized = model.initialized_q;
  bool clk = false, half = false, phaseQ = false;
  bool halfValid = false, phaseValid = false;
  uint32_t random = 0x12345678;
  for (unsigned step = 0; step < 65536; ++step) {
    random ^= random << 13;
    random ^= random >> 17;
    random ^= random << 5;
    unsigned nextClocks = random & 3;
    bool nextClk = (random >> 2) & 1;
    bool data = (random >> 3) & 1;
    for (unsigned lane = 0; lane < 2; ++lane) {
      if (((clocks ^ nextClocks) >> lane) & 1) {
        expectedGenerated = (expectedGenerated & ~(1u << lane)) |
                            ((counter[lane] >> 1) << lane);
        counter[lane] = (counter[lane] + 1) & 3;
        expectedInitialized = (expectedInitialized & ~(1u << lane)) |
                              ((initializedCounter[lane] >> 1) << lane);
        initializedCounter[lane] = (initializedCounter[lane] + 1) & 3;
      }
    }
    if (clk && !nextClk) {
      half = data;
      halfValid = true;
    } else if (!clk && nextClk) {
      phaseQ = half;
      phaseValid = halfValid;
    }
    model.clocks = nextClocks;
    model.clk = nextClk;
    model.d = data;
    model.eval();
    if (model.generated_q != expectedGenerated ||
        model.initialized_q != expectedInitialized ||
        (phaseValid && model.phase_q != phaseQ)) {
      std::fprintf(stderr, "Incorrect edge update at step %u\n", step);
      return 1;
    }
    // Data changing without a clock transition cannot update either stage.
    model.d = !data;
    model.eval();
    if (model.generated_q != expectedGenerated ||
        model.initialized_q != expectedInitialized ||
        (phaseValid && model.phase_q != phaseQ)) {
      std::fprintf(stderr, "State changed without a clock transition\n");
      return 1;
    }
    clk = nextClk;
    clocks = nextClocks;
  }
  std::puts("65536 independent clock transitions and opposite-edge pipeline "
            "checks passed");
  return 0;
}
