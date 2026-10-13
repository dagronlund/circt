// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include "Vtop.h"
#include "verilated.h"
#include <cstdint>
#include <iostream>

int main(int argc, char **argv) {
  VerilatedContext context;
  context.commandArgs(argc, argv);
  context.randReset(2);
  context.randSeed(123);
  Vtop dut{&context};
#ifdef SMALL_ARRAY
  constexpr unsigned elementWidth = 3, elements = 5, offsets = 4;
#else
  constexpr unsigned elementWidth = 8, elements = 4, offsets = 2;
#endif
  constexpr unsigned values = 1u << (2 * elementWidth);
  constexpr unsigned dataMask = values - 1;
  dut.clk = 0;
  dut.enable = 0;
  dut.offset = 0;
  dut.d = 0;
  dut.eval();
  // Initial state is unconstrained. Sample it, then check that every update
  // preserves the unselected lanes, including any lane that is never written.
  uint32_t expected = dut.q;
  auto check = [&]() {
    if (dut.q == expected)
      return true;
    std::cerr << "enable=" << unsigned(dut.enable)
              << " offset=" << unsigned(dut.offset) << " d=" << unsigned(dut.d)
              << ": expected " << expected << ", got " << unsigned(dut.q)
              << '\n';
    return false;
  };
  auto step = [&](unsigned d, unsigned offset, bool enable) {
    dut.clk = 0;
    dut.enable = enable;
    dut.offset = offset;
    dut.d = d;
    dut.eval();
    if (!check())
      return false;
#ifdef ASCENDING
    unsigned shift = (elements - 2 - offset) * elementWidth;
#else
    unsigned shift = offset * elementWidth;
#endif
    if (enable) {
      expected = (expected & ~(dataMask << shift)) | (d << shift);
#ifdef SECOND_SLICE
      // The later nonblocking assignment overrides its overlap with the first.
      expected = (expected & ~(dataMask << elementWidth)) |
                 ((d ^ dataMask) << elementWidth);
#endif
    }
    dut.clk = 1;
    dut.eval();
    if (!check())
      return false;
    // Input changes between edges and falling edges must leave state unchanged.
    dut.enable = !enable;
    dut.offset = (offset + 1) % offsets;
    dut.d = d ^ dataMask;
    dut.eval();
    if (!check())
      return false;
    dut.clk = 0;
    dut.eval();
    return check();
  };
  uint32_t random = 0x12345678;
  for (unsigned d = 0; d < values; ++d)
    for (unsigned offset = 0; offset < offsets; ++offset)
      for (unsigned enable = 0; enable < 2; ++enable) {
        // Vary the prior contents as well as the incoming data and controls.
        for (unsigned seedOffset = 0; seedOffset < offsets; ++seedOffset) {
          random ^= random << 13;
          random ^= random >> 17;
          random ^= random << 5;
          if (!step(random & dataMask, seedOffset, true))
            return 1;
        }
        if (!step(d, offset, enable))
          return 1;
      }
  dut.final();
  std::cout << values * offsets * 2
            << " dynamic array slice transitions and synchronous timing checks "
               "passed\n";
}
