// RUN: circt-opt --verify-diagnostics --split-input-file %s

// expected-error @below {{expected a covergroup declaration for result type}}
%instance = moore.covergroup.new : !moore.covergroup<@missing>

// -----

moore.covergroup.decl @cg {
^bb0(%value: !moore.l32):
}
%instance = moore.covergroup.new : !moore.covergroup<@cg>
// expected-error @below {{sample arguments must match the covergroup body arguments}}
moore.covergroup.sample %instance() : !moore.covergroup<@cg>

// -----

moore.covergroup.decl @cg {
^bb0(%value: !moore.l32):
}
%instance = moore.covergroup.new : !moore.covergroup<@cg>
%value = moore.constant 1 : i32
// expected-error @below {{sample arguments must match the covergroup body arguments}}
moore.covergroup.sample %instance(%value) : !moore.covergroup<@cg>(!moore.i32)

// -----

func.func @wrong_symbol() { return }
// expected-error @below {{expected a covergroup declaration for result type}}
%instance = moore.covergroup.new : !moore.covergroup<@wrong_symbol>

// -----

// expected-error @below {{sample arguments must have unpacked Moore types}}
moore.covergroup.decl @bad {
^bb0(%value: i32):
}

// -----

// expected-error @below {{coverpoint names must be nonempty and unique}}
moore.covergroup.decl @bad {
^bb0(%value: !moore.l32):
  %enabled = moore.constant 1 : i1
  moore.coverpoint "value" %value if %enabled : l32
  moore.coverpoint "value" %value if %enabled : l32
}

// -----

func.func @missing(%instance: !moore.covergroup<@missing>) {
  // expected-error @below {{expected a covergroup declaration for instance type}}
  moore.covergroup.sample %instance() : !moore.covergroup<@missing>
  return
}
