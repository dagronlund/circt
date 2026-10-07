// RUN: split-file %s %t
// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %t/data.sv | FileCheck %s --check-prefix=DATA --implicit-check-not=llhd. --implicit-check-not=moore. --implicit-check-not=unrealized_conversion_cast
// RUN: circt-verilog --ir-hw %t/data.sv | circt-opt --lower-llhd-formal-to-core | FileCheck %s --check-prefix=DATA --implicit-check-not=llhd.
// RUN: circt-verilog --ir-hw %t/data.sv | FileCheck %s --check-prefix=DEFAULT
// RUN: not circt-verilog --ir-hw --lower-llhd-formal-to-core %t/dynamic-init.sv 2>&1 | FileCheck %s --check-prefix=DYNAMIC
// RUN: not circt-verilog --ir-hw --lower-llhd-formal-to-core %t/query.sv 2>&1 | FileCheck %s --check-prefix=QUERY
// REQUIRES: slang
// UNSUPPORTED: valgrind

// Time data retains the frontend's femtosecond representation and timescale
// arithmetic. The implicit scheduling zero must not become a register preset.
// DATA-LABEL: hw.module @time_repro(in %clk : i1, in %value : i64, out stored : i64)
// DATA: [[SCALE:%.+]] = hw.constant 1000000 : i64
// DATA: [[VALUE:%.+]] = comb.mul %value, [[SCALE]] : i64
// DATA: [[CLOCK:%.+]] = seq.to_clock %clk
// DATA: [[REG:%.+]] = seq.firreg [[VALUE]] clock [[CLOCK]] : i64
// DATA-NEXT: hw.output [[REG]] : i64
// DATA-LABEL: hw.module @initialized(in %clk : i1, in %value : i64, out stored : i64)
// DATA: [[INIT_REG:%.+]] = seq.firreg {{.*}} preset 7000 : i64
// DATA: hw.output [[INIT_REG]] : i64
// DATA-LABEL: hw.module @time_passthrough(in %value : i64, out stored : i64)
// DATA-NEXT: hw.output %value : i64
// DEFAULT-LABEL: hw.module @time_repro
// DEFAULT-SAME: out stored : !llhd.time
// DEFAULT: llhd.sig
// DEFAULT: llhd.process
// DEFAULT: llhd.int_to_time
// DEFAULT-LABEL: hw.module @initialized
// DEFAULT-SAME: out stored : !llhd.time
// DEFAULT: llhd.sig {{.*}} {llhd.explicit_init} : !llhd.time
// DYNAMIC: error: nonconstant register initialization is unsupported
// QUERY: error:
// QUERY-SAME: unsupported

//--- data.sv
`timescale 1ns/1ns
module time_repro (
    input logic clk,
    input logic [63:0] value,
    output time stored
);
    always @(posedge clk)
        stored <= value;
endmodule

module initialized(input logic clk, input logic [63:0] value,
                   output time stored);
    timeunit 1ps;
    timeprecision 1ps;
    time state = 7;
    assign stored = state;
    always @(posedge clk)
        state <= value;
endmodule

module time_passthrough(input time value, output time stored);
    assign stored = value;
endmodule

//--- dynamic-init.sv
module dynamic_init(input logic clk, input logic [63:0] value,
                    output time stored);
    time state = value;
    assign stored = state;
    always @(posedge clk)
        state <= value;
endmodule

//--- query.sv
module time_query(output time value);
    assign value = $time;
endmodule
