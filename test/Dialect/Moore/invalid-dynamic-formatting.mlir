// RUN: circt-opt %s --verify-diagnostics
func.func @invalid(%fmt: !moore.string, %n: !moore.i32) {
  // expected-error @+1 {{requires one signedness flag per value}}
  %s = moore.builtin.sformat_dynamic %fmt(%n) {isSigned = array<i1>} : !moore.i32
  return
}
