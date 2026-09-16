// RUN: circt-verilog --import-only %s | FileCheck %s
// RUN: circt-verilog --import-only %s | circt-opt --convert-moore-to-core --canonicalize | FileCheck %s --check-prefix=CORE
// REQUIRES: slang
// UNSUPPORTED: valgrind

// Runtime formats preserve all value types and integral signedness.
// CHECK-LABEL: func.func private @format_function(
// CHECK: moore.builtin.sformat_dynamic %arg0(%arg1, %arg2, %arg3, %arg4, %arg5) {isSigned = array<i1: true, false, false, false, false>} : !moore.i32, !moore.i32, !moore.string, !moore.f64, !moore.f32
// CORE-LABEL: func.func private @format_function(
// CORE: sim.sv.sformat_dynamic %arg0(%arg1, %arg2, %arg3, %arg4, %arg5) {isSigned = array<i1: true, false, false, false, false>} : i32, i32, !sim.dstring, f64, f32
function automatic string format_function(string fmt, int n, int unsigned u,
                                          string s, real r, shortreal sr);
  return $sformatf(fmt, n, u, s, r, sr);
endfunction

// CHECK-LABEL: func.func private @format_task(
// CHECK: moore.string.concat
// CHECK: moore.builtin.sformat_dynamic
// CHECK: moore.fmt.string
// CHECK: moore.fstring_to_string
// CHECK: moore.blocking_assign %arg2
// CORE-LABEL: func.func private @format_task(
// CORE: sim.sv.sformat_dynamic
function automatic void format_task(string prefix, int n, ref string result);
  $sformat(result, {prefix, "=%0d"}, n);
endfunction

// Packed, computed formats work too, and a no-argument format is not just text:
// percent escapes must still be interpreted at runtime.
// CHECK-LABEL: func.func private @packed_format(
// CHECK: moore.int_to_string
// CHECK: moore.builtin.sformat_dynamic
function automatic string packed_format(bit [63:0] fmt, int n);
  return $sformatf(fmt, n);
endfunction
// CHECK-LABEL: func.func private @no_values(
// CHECK: moore.builtin.sformat_dynamic %arg0() {isSigned = array<i1>}
function automatic string no_values(string fmt);
  return $sformatf(fmt);
endfunction

// Display-family tasks treat computed strings as message text. A subsequent
// literal can still format subsequent arguments. All tasks share this path.
// CHECK-LABEL: func.func private @messages(
// CHECK: [[TEXT:%.*]] = moore.string.concat
// CHECK: [[MSG:%.*]] = moore.fmt.string [[TEXT]]
// CHECK: [[COLON:%.*]] = moore.fmt.literal ":"
// CHECK: [[N:%.*]] = moore.fmt.int decimal %arg1
// CHECK: [[NL:%.*]] = moore.fmt.literal "\0A"
// CHECK: [[ALL:%.*]] = moore.fmt.concat ([[MSG]], [[COLON]], [[N]], [[NL]])
// CHECK: moore.builtin.display [[ALL]]
// CHECK: moore.builtin.display
// CHECK: moore.builtin.fdisplay
// CHECK: moore.builtin.fdisplay
// CHECK: moore.blocking_assign %arg3
// CHECK: moore.builtin.severity info
// CHECK: moore.builtin.severity warning
// CHECK: moore.builtin.severity error
// CHECK: moore.builtin.severity fatal
// CORE-LABEL: func.func private @messages(
// CORE: sim.proc.print
function automatic void messages(string name, int n, int fd, ref string result);
  $display({name, "%d"}, ":%0d", n);
  $write(name, ":%0d", n);
  $fdisplay(fd, {name, "%d"}, ":%0d", n);
  $fwrite(fd, name, ":%0d", n);
  $swrite(result, {name, "%d"}, ":%0d", n);
  $info({name, "%d"}, ":%0d", n);
  $warning(name, ":%0d", n);
  $error({name, "%d"}, ":%0d", n);
  $fatal(1, name, ":%0d", n);
endfunction

// Implicit strings such as concatenated literals print as strings even when
// their type is packed. Real arguments use default floating-point formatting.
// CHECK-LABEL: func.func private @default_formats(
// CHECK: moore.fmt.string
// CHECK: moore.fmt.real
// CHECK: moore.builtin.severity info
function automatic void default_formats(real r);
  $info({"percent", "%d"}, r);
endfunction

// Existing literal formats retain the statically parsed formatting path.
// CHECK-LABEL: func.func private @literal_format(
// CHECK-NOT: sformat_dynamic
// CHECK: moore.fmt.int
// CHECK: return
function automatic string literal_format(int n);
  return $sformatf("value=%0d", n);
endfunction

// Nested format results are strings, not formatting fragments passed to the
// native function. Also exercise the task's packed output conversion.
// CHECK-LABEL: func.func private @nested_format(
// CHECK: moore.builtin.sformat_dynamic
// CHECK: moore.fstring_to_string
// CHECK: moore.builtin.sformat_dynamic
// CHECK: moore.string_to_int
// CHECK: moore.blocking_assign %arg2
// CORE-LABEL: func.func private @nested_format(
// CORE: sim.sv.sformat_dynamic
// CORE: sim.sv.sformat_dynamic
function automatic void nested_format(string fmt, int n, ref bit [127:0] result);
  $sformat(result, fmt, $sformatf(fmt, n));
endfunction
