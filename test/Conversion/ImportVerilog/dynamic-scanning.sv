// RUN: circt-verilog --import-only %s | FileCheck %s
// RUN: circt-verilog --import-only %s | circt-opt --convert-moore-to-core --canonicalize | FileCheck %s --check-prefix=CORE
// REQUIRES: slang
// UNSUPPORTED: valgrind

// Dynamic formats retain heterogeneous destination types. Signed comparisons
// ensure an EOF count of -1 does not assign any destination; counts 1 and 2
// only assign the first one or two destinations respectively.
// CHECK-LABEL: func.func private @scan_string(
// CHECK: [[COUNT:%.*]], [[VALUES:%.*]]:3 = moore.builtin.sscanf_dynamic %arg0, %arg1 : !moore.i32, !moore.string, !moore.f64
// CHECK: [[ZERO:%.*]] = moore.constant 0 : i32
// CHECK: moore.sgt [[COUNT]], [[ZERO]] : i32 -> i1
// CHECK: [[ONE:%.*]] = moore.constant 1 : i32
// CHECK: moore.sgt [[COUNT]], [[ONE]] : i32 -> i1
// CHECK: [[TWO:%.*]] = moore.constant 2 : i32
// CHECK: moore.sgt [[COUNT]], [[TWO]] : i32 -> i1
// CHECK: cf.cond_br
// CHECK: moore.blocking_assign %arg2, [[VALUES]]#0 : i32
// CHECK: cf.cond_br
// CHECK: moore.blocking_assign %arg3, [[VALUES]]#1 : string
// CHECK: cf.cond_br
// CHECK: moore.blocking_assign %arg4, [[VALUES]]#2 : f64
// CORE-LABEL: func.func private @scan_string(
// CORE: sim.sv.sscanf_dynamic %arg0, %arg1 : i32, !sim.dstring, f64
// CORE: comb.icmp sgt
function automatic int scan_string(string input_value, string format_value,
                                   ref int x, ref string y, ref real z);
  return $sscanf(input_value, format_value, x, y, z);
endfunction

// CHECK-LABEL: func.func private @scan_file(
// CHECK: moore.builtin.fscanf_dynamic %arg0, %arg1 : !moore.i32, !moore.string
// CORE-LABEL: func.func private @scan_file(
// CORE: sim.sv.fscanf_dynamic %arg0, %arg1 : i32, !sim.dstring
function automatic int scan_file(int fd, string format_value,
                                 ref int x, ref string y);
  return $fscanf(fd, format_value, x, y);
endfunction

// CHECK-LABEL: func.func private @open_file(
// CHECK: moore.builtin.fopen_dynamic %arg0, %arg1
// CORE-LABEL: func.func private @open_file(
// CORE: sim.sv.fopen_dynamic %arg0, %arg1
function automatic int open_file(string filename, string mode);
  return $fopen(filename, mode);
endfunction

// Expression-valued constant arguments must also work without being literals.
// CHECK-LABEL: func.func private @constant_formats(
// CHECK: moore.builtin.sscanf_dynamic
// CHECK: moore.builtin.fscanf_dynamic
// CHECK: moore.builtin.fopen_dynamic
function automatic void constant_formats(int fd);
  localparam string format_value = "%d";
  localparam string mode = "r";
  int value;
  void'($sscanf("42", format_value, value));
  void'($fscanf(fd, format_value, value));
  fd = $fopen("input.txt", mode);
endfunction

// CHECK-LABEL: func.func private @no_destinations(
// CHECK: moore.builtin.sscanf_dynamic %arg0, %arg1
// CORE-LABEL: func.func private @no_destinations(
// CORE: sim.sv.sscanf_dynamic %arg0, %arg1
function automatic int no_destinations(string source, string format_value);
  return $sscanf(source, format_value);
endfunction

// CHECK-LABEL: func.func private @conditional_mode(
// CHECK: moore.builtin.fopen_dynamic
function automatic int conditional_mode(string filename, bit write_mode);
  return $fopen(filename, write_mode ? "w" : "r");
endfunction

module top;
endmodule
