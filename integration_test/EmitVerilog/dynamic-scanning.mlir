// REQUIRES: iverilog
// RUN: circt-opt %s --lower-sim-to-sv --export-verilog -o /dev/null > %t.sv
// RUN: iverilog -g2012 -s dynamic -o %t.vvp %t.sv
// RUN: mkdir -p %t.dir
// RUN: printf 73 > %t.dir/dynamic-scanning-input.txt
// RUN: cd %t.dir && vvp %t.vvp | FileCheck %s
// CHECK: PASS

hw.module @dynamic() {
  sv.initial {
    // Partial matching only makes the first result valid.
    %text = sim.string.literal "12 nope"
    %scanFormat = sim.string.literal "%d %d"
    %count, %values:2 = sim.sv.sscanf_dynamic %text, %scanFormat : i32, i32
    sv.verbatim "if ({{0}} != 1 || {{1}} != 12) $fatal(1, \22partial scan\22);" (%count, %values#0) : i32, i32

    // Suppression does not consume an output or contribute to the count.
    %suppressedText = sim.string.literal "11 29"
    %suppressedFormat = sim.string.literal "%*d %d"
    %count2, %value = sim.sv.sscanf_dynamic %suppressedText, %suppressedFormat : i32
    sv.verbatim "if ({{0}} != 1 || {{1}} != 29) $fatal(1, \22suppression\22);" (%count2, %value) : i32, i32

    %mixedText = sim.string.literal "hello 1.25"
    %mixedFormat = sim.string.literal "%s %f"
    %mixedCount, %mixed:2 = sim.sv.sscanf_dynamic %mixedText, %mixedFormat : !sim.dstring, f64
    %mixedString = builtin.unrealized_conversion_cast %mixed#0 : !sim.dstring to !hw.string
    sv.verbatim "if ({{0}} != 2 || {{1}} != \22hello\22 || {{2}} != 1.25) $fatal(1, \22mixed scan\22);" (%mixedCount, %mixedString, %mixed#1) : i32, !hw.string, f64

    %filename = sim.string.literal "dynamic-scanning-input.txt"
    %mode = sim.string.literal "r"
    %fd = sim.sv.fopen_dynamic %filename, %mode
    %decimal = sim.string.literal "%d"
    %read, %number = sim.sv.fscanf_dynamic %fd, %decimal : i32
    sv.verbatim "if ({{0}} != 1 || {{1}} != 73) $fatal(1, \22file scan\22);" (%read, %number) : i32, i32
    %eof, %ignored = sim.sv.fscanf_dynamic %fd, %decimal : i32
    sv.verbatim "if ($signed({{0}}) != -1) $fatal(1, \22EOF\22);" (%eof) : i32
    sv.verbatim "$fclose({{0}});" (%fd) : i32
    sv.verbatim "$display(\22PASS\22);"
  }
  hw.output
}
