# Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
# See https://llvm.org/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exhaustively compare lowered hardware against independent source trace rules.

This deliberately small two-state evaluator consumes the actual pass output. It
models simultaneous register updates, unconstrained history initialization, and
asynchronous reset events between samples. Unknown operations fail the test.
"""

import itertools
import re
import sys
from functools import reduce

SSA = r'%[\w.$-]+'


class Circuit:

  def __init__(self, text, initial=0):
    self.ops = {}
    self.regs = {}
    self.checks = []
    self.state = {}
    self.inputs = {}
    for line in text.splitlines()[1:]:
      line = line.strip()
      if not line or line == '}' or line.startswith('hw.output'):
        continue
      if line.startswith('verif.'):
        flavor = re.search(r'verif.(?:clocked_)?(\w+)', line)[1]
        operands = re.findall(SSA, line)
        prop = operands[0]
        enabled = re.search(r'\bif (' + SSA + ')', line)
        label = re.search(r'label "([^"]+)"', line)[1]
        edge = 'neg' if 'negedge' in line else 'pos'
        self.checks.append(
            (flavor, prop, enabled[1] if enabled else None, label, edge))
        continue
      name, expr = line.split(' = ', 1)
      opcode = expr.split()[0]
      operands = re.findall(SSA, expr)
      widths = re.findall(r'\bi(\d+)\b', expr)
      width = int(widths[-1]) if widths else 1
      self.ops[name] = (opcode, operands, expr, width)
      if opcode in ('seq.firreg', 'seq.compreg'):
        self.regs[name] = self.ops[name]
        preset = re.search(r'preset (-?\d+)', expr)
        self.state[name] = int(preset[1]) if preset else (
            initial.get(name, 0) if isinstance(initial, dict) else initial)

  def values(self, inputs):
    cache = dict(inputs)
    cache.update(self.state)

    def get(name):
      if name in cache:
        return cache[name]
      opcode, operands, expr, width = self.ops[name]
      args = [get(operand) for operand in operands]
      if opcode == 'hw.constant':
        val = expr.split()[1]
        result = int(val) if val not in ('true',
                                         'false') else int(val == 'true')
      elif opcode == 'comb.and':
        result = reduce(lambda a, b: a & b, args)
      elif opcode == 'comb.or':
        result = reduce(lambda a, b: a | b, args)
      elif opcode == 'comb.xor':
        result = reduce(lambda a, b: a ^ b, args)
      elif opcode == 'comb.mux':
        result = args[1] if args[0] else args[2]
      elif opcode == 'comb.icmp':
        pred = expr.split()[1]
        assert pred in ('eq', 'ne', 'ceq', 'cne'), expr
        result = int((args[0] == args[1]) == (pred in ('eq', 'ceq')))
      elif opcode in ('seq.to_clock', 'seq.from_clock'):
        result = args[0]
      elif opcode == 'seq.clock_inv':
        result = 1 - args[0]
      else:
        raise AssertionError('Unsupported evaluator operation: ' + expr)
      cache[name] = result & ((1 << width) - 1)
      return cache[name]

    return get

  def reset(self, inputs):
    # A pulse can arrive and disappear without a sampling edge.
    get = self.values(inputs)
    for name, (_, _, expr, _) in self.regs.items():
      reset = re.search(r'reset async (' + SSA + '), (' + SSA + ')', expr)
      if reset and get(reset[1]):
        self.state[name] = get(reset[2])

  def sample(self, inputs, edge='pos'):
    self.reset(inputs)
    get = self.values(inputs)
    observed = {}
    for flavor, prop, enable, label, check_edge in self.checks:
      active = check_edge == edge and (enable is None or get(enable))
      observed[label] = observed.get(label, False) or bool(
          active and (get(prop) if flavor == 'cover' else not get(prop)))
    updates = {}
    for name, (_, operands, expr, _) in self.regs.items():
      reset = re.search(r'reset (?:async|sync) (' + SSA + '), (' + SSA + ')',
                        expr)
      if reset and get(reset[1]):
        updates[name] = get(reset[2])
      elif get(operands[1]):
        updates[name] = get(operands[0])
    self.state.update(updates)
    return observed


def extract(text, name):
  return re.search(r'hw.module @' + name + r'\(.*?\n  }', text, re.S)[0]


def combinational(text):
  for a, b, en in itertools.product(range(2), repeat=3):
    got = Circuit(text).sample({'%a': a, '%b': b, '%en': en})
    expected = {
        'unconditional': not a,
        'nested': bool(a and b and not en),
        'nested_assume': bool(a and b and not en),
        'disabled_cover': bool(a and b and en),
        'merge': not ((a if b else b) if a else en)
    }
    assert got == expected, (got, expected)


def procedural(text):
  for trace in itertools.product(range(4), repeat=4):
    circuit = Circuit(text)
    q, r = 0, 1
    for bits in trace:
      en, d = bits & 1, bits >> 1
      got = circuit.sample({'%clk': 1, '%en': en, '%d': d})
      assert got == {
          'oldq': bool(en and not q),
          'oldr': bool(en and not r),
          'blocking': bool(en and not q)
      }, (trace, got, q, r)
      if en:
        q, r = d, q
      assert circuit.state['%qs'] == q and circuit.state['%rs'] == r


text = sys.stdin.read()
combinational(extract(text, 'combinational'))
procedural(extract(text, 'procedural'))
wrapper = Circuit(extract(text, 'wrapper'))
assert wrapper.sample({'%clk': 0, '%a': 0}, 'neg')['wrapped']
assert not wrapper.sample({'%clk': 0, '%a': 1}, 'neg')['wrapped']

# The scheduling zero must not constrain the initial state of this register.
for initial in range(2):
  circuit = Circuit(extract(text, 'unconstrained'), initial)
  assert list(circuit.state.values()) == [initial]
  circuit.sample({'%clk': 1, '%d': 1 - initial})
  assert list(circuit.state.values()) == [1 - initial]

for trace in itertools.product(range(2), repeat=4):
  circuit = Circuit(extract(text, 'raw_nonblocking'))
  q = 1
  for d in trace:
    observed = circuit.sample({'%clk': 1, '%d': d})
    assert observed == {'raw_before': not q, 'raw_after': not q}
    q = d

print('Exhaustive combinational and sequential traces passed')
