# Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare generated constraints with independent unsigned interval rules."""

import itertools
import re
import sys
from functools import reduce

SSA = r'%[\w.$-]+'
SAMPLES = tuple(
    range(13)) + (0x7fffffff, 0x80000000, 0x80000001, 0xfffffffe, 0xffffffff)
text = sys.stdin.read()
body = re.search(r'hw.module @ranges\(.*?\n  }', text, re.S)[0]
ops, checks, sources = {}, [], []
for line in body.splitlines()[1:-1]:
  line = line.strip()
  if line.startswith('hw.output'):
    outputs = re.findall(SSA, line)
  elif line.startswith('verif.assume'):
    checks.append(re.findall(SSA, line)[0])
  else:
    name, expr = line.split(' = ', 1)
    opcode = expr.split()[0]
    widths = re.findall(r'\bi(\d+)\b', expr)
    width = 1 if opcode == 'comb.icmp' or not widths else int(widths[-1])
    ops[name] = (opcode, expr, re.findall(SSA, expr), width)
    if opcode == 'verif.symbolic_value':
      sources.append(name)

assert len(sources) == len(outputs) == 8
assert set(sources) == set(outputs), 'Draws must be independent direct sources'
unbounded = '--unbounded' in sys.argv
assert bool(checks) != unbounded


def allowed(inputs):
  cache = dict(inputs)

  def get(name):
    if name in cache:
      return cache[name]
    opcode, expr, operands, width = ops[name]
    args = [get(v) for v in operands]
    if opcode == 'hw.constant':
      literal = expr.split()[1]
      result = {'true': 1, 'false': 0}.get(literal)
      if result is None:
        result = int(literal)
    elif opcode == 'comb.icmp':
      predicate = re.search(r'icmp bin (\w+)', expr)[1]
      a, b = args
      result = {
          'eq': a == b,
          'ne': a != b,
          'ult': a < b,
          'ule': a <= b,
          'ugt': a > b,
          'uge': a >= b,
      }[predicate]
    elif opcode == 'comb.mux':
      result = args[1] if args[0] else args[2]
    elif opcode == 'comb.and':
      result = reduce(lambda a, b: a & b, args)
    else:
      raise AssertionError('Unexpected operation: ' + expr)
    cache[name] = int(result) & ((1 << width) - 1)
    return cache[name]

  return all(get(prop) for prop in checks)


intervals = ((3, 10), (3, 10), (7, 7), (0, 0), (0x80000000, 0xffffffff),
             (0, 0xffffffff), (0, 10))
baseline = dict(zip(outputs[1:], (low for low, _ in intervals)))
for low, high, draw in itertools.product(SAMPLES, repeat=3):
  got = allowed({**baseline, '%low': low, '%high': high, outputs[0]: draw})
  lower, upper = sorted((low, high))
  assert bool(got) == (unbounded or
                       lower <= draw <= upper), (low, high, draw, got)

baseline.update({'%low': 0, '%high': 0, outputs[0]: 0})
for output, (low, high) in zip(outputs[1:], intervals):
  for draw in SAMPLES:
    got = allowed({**baseline, output: draw})
    assert bool(got) == (unbounded or
                         low <= draw <= high), (low, high, draw, got)
print('Independent draws and unsigned random range constraints passed')
