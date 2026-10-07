# Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Check witnesses against counts obtained from the original SV harness.

The same deterministic driver was run on the original stream-stage SystemVerilog
with Verilator. Counts cover acceptance, replacement, stall/pop, and drain for
both immediate and concurrent properties; the long sequence has 20 witnesses.
"""
import sys

with open(sys.argv[1]) as coverage:
  counts = [
      int(line.rsplit(' ', 1)[1]) for line in coverage if line.startswith('C ')
  ]
assert sorted(counts) == [20, 945, 945, 1247, 1247, 2391, 2391, 2547], counts
