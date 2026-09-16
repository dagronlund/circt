// REQUIRES: iverilog
// RUN: circt-opt %s --lower-sim-to-sv --export-verilog -o /dev/null > %t.sv
// RUN: iverilog -g2012 -s formatting -o %t.vvp %t.sv
// RUN: vvp %t.vvp | FileCheck %s
// CHECK: PASS

hw.module @formatting() {
  sv.initial {
    %fmtVar = sv.reg : !hw.inout<!hw.string>
    %firstFmt = sv.constantStr "%0d %0d %s %0.2f"
    sv.bpassign %fmtVar, %firstFmt : !hw.string
    %firstRead = sv.read_inout %fmtVar : !hw.inout<!hw.string>
    %fmt = builtin.unrealized_conversion_cast %firstRead : !hw.string to !sim.dstring
    %n = hw.constant -7 : i32
    %u = hw.constant -1 : i32
    %text = sim.string.literal "%literal"
    %bits = hw.constant 4608308318706860032 : i64
    %real = sv.system "bitstoreal"(%bits) : (i64) -> f64
    %result = sim.sv.sformat_dynamic %fmt(%n, %u, %text, %real) {isSigned = array<i1: true, false, false, false>} : i32, i32, !sim.dstring, f64
    %string = builtin.unrealized_conversion_cast %result : !sim.dstring to !hw.string
    sv.verbatim "if ({{0}} != \22-7 4294967295 %literal 1.25\22) $fatal(1, \22mixed format\22);" (%string) : !hw.string

    // The second call sees a changed format; the first result remains captured.
    %nextFmt = sv.constantStr "%04h"
    sv.bpassign %fmtVar, %nextFmt : !hw.string
    %nextRead = sv.read_inout %fmtVar : !hw.inout<!hw.string>
    %next = builtin.unrealized_conversion_cast %nextRead : !hw.string to !sim.dstring
    %hex = hw.constant 42 : i16
    %second = sim.sv.sformat_dynamic %next(%hex) {isSigned = array<i1: false>} : i16
    %secondString = builtin.unrealized_conversion_cast %second : !sim.dstring to !hw.string
    sv.verbatim "if ({{0}} != \22002a\22 || {{1}} != \22-7 4294967295 %literal 1.25\22) $fatal(1, \22changed format\22);" (%secondString, %string) : !hw.string, !hw.string

    %escape = sim.string.literal "100%%"
    %escaped = sim.sv.sformat_dynamic %escape() {isSigned = array<i1>}
    %escapedString = builtin.unrealized_conversion_cast %escaped : !sim.dstring to !hw.string
    sv.verbatim "if ({{0}} != \22100%\22) $fatal(1, \22percent escape\22);" (%escapedString) : !hw.string
    sv.verbatim "$display(\22PASS\22);"
  }
  hw.output
}
