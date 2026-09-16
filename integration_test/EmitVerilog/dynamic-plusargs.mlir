// REQUIRES: iverilog
// RUN: circt-opt %s --lower-sim-to-sv --export-verilog -o /dev/null > %t.sv
// RUN: iverilog -g2012 -s dynamic -o %t.vvp %t.sv
// RUN: vvp %t.vvp +arg1=41 +arg2=82 | FileCheck %s
// CHECK: PASS

hw.module @dynamic() {
  sv.initial {
    %one = hw.constant 1 : i32
    %two = hw.constant 2 : i32
    %index = sv.reg : !hw.inout<i32>
    %namefmt = sv.constantStr "arg%0d"
    %suffix = sim.string.literal "=%d"

    // The name is computed from mutable state at each call site.
    sv.bpassign %index, %one : i32
    %i = sv.read_inout %index : !hw.inout<i32>
    %name1 = sv.system "sformatf"(%namefmt, %i) : (!hw.string, i32) -> !hw.string
    %prefix1 = builtin.unrealized_conversion_cast %name1 : !hw.string to !sim.dstring
    %format1 = sim.string.concat (%prefix1, %suffix)
    %found1 = sim.plusargs.test_dynamic %prefix1
    %ok1, %value1 = sim.plusargs.value_dynamic %format1 : i32
    sv.verbatim "if (!{{0}} || !{{1}} || {{2}} != 41) $fatal(1, \22first plusarg\22);" (%found1, %ok1, %value1) : i1, i1, i32

    sv.bpassign %index, %two : i32
    %j = sv.read_inout %index : !hw.inout<i32>
    %name2 = sv.system "sformatf"(%namefmt, %j) : (!hw.string, i32) -> !hw.string
    %prefix2 = builtin.unrealized_conversion_cast %name2 : !hw.string to !sim.dstring
    %format2 = sim.string.concat (%prefix2, %suffix)
    %ok2, %value2 = sim.plusargs.value_dynamic %format2 : i32
    sv.verbatim "if (!{{0}} || {{1}} != 82) $fatal(1, \22second plusarg\22);" (%ok2, %value2) : i1, i32

    %missing = sim.string.literal "missing=%d"
    %notFound, %unused = sim.plusargs.value_dynamic %missing : i32
    sv.verbatim "if ({{0}}) $fatal(1, \22missing plusarg\22);" (%notFound) : i1

    sv.verbatim "$display(\22PASS\22);"
  }
  hw.output
}
