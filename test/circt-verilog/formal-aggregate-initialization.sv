// RUN: split-file %s %t
// RUN: circt-verilog --ir-llhd %t/uninitialized.sv | FileCheck %s --check-prefix=LLHD
// RUN: circt-verilog --ir-llhd %t/uninitialized.sv | circt-opt --comb-assume-two-valued --lower-llhd-formal-to-core | FileCheck %s --check-prefix=CORE --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %t/uninitialized.sv | FileCheck %s --check-prefix=CORE --implicit-check-not=llhd. --implicit-check-not=preset
// RUN: circt-verilog --ir-hw %t/explicit.sv --top=union_init | FileCheck %s --check-prefix=EXPLICIT
// RUN: circt-verilog --ir-llhd %t/explicit.sv --top=union_init | not circt-opt --lower-llhd-formal-to-core 2>&1 | FileCheck %s --check-prefix=ERROR
// RUN: not circt-verilog --ir-hw %t/explicit.sv --top=union_init --lower-llhd-formal-to-core 2>&1 | FileCheck %s --check-prefix=ERROR
// RUN: not circt-verilog --ir-hw %t/explicit.sv --top=struct_init --lower-llhd-formal-to-core 2>&1 | FileCheck %s --check-prefix=ERROR
// RUN: not circt-verilog --ir-hw %t/explicit.sv --top=array_init --lower-llhd-formal-to-core 2>&1 | FileCheck %s --check-prefix=ERROR
// RUN: not circt-verilog --ir-hw %t/dynamic.sv --lower-llhd-formal-to-core 2>&1 | FileCheck %s --check-prefix=ERROR
// REQUIRES: slang

// Scheduling zeros for uninitialized aggregates must not constrain registers.
// LLHD-LABEL: hw.module @overlay_value_repro
// LLHD: %overlay_value = llhd.sig {{.*}} {llhd.unconstrained} : !hw.union<raw: i8, nibbles: !hw.array<2xi4>>
// LLHD-LABEL: hw.module @nested_aggregate
// LLHD: %matrix_value = llhd.sig {{.*}} {llhd.unconstrained} : !hw.array<2xarray<2xstruct<lo: i4, hi: i4>>>
// CORE-LABEL: hw.module @overlay_value_repro
// CORE: seq.firreg {{.*}} : !hw.union<raw: i8, nibbles: !hw.array<2xi4>>
// CORE: seq.firreg {{.*}} : i8
// CORE: hw.output
// CORE-LABEL: hw.module @nested_aggregate
// CORE: seq.firreg {{.*}} : !hw.array<2xarray<2xstruct<lo: i4, hi: i4>>>
// CORE: seq.firreg {{.*}} : i32
// CORE: hw.output

// Explicit initializers must survive ordinary extraction for a diagnostic.
// EXPLICIT-LABEL: hw.module @union_init
// EXPLICIT-DAG: [[CONSTANT:%.+]] = hw.constant 90 : i8
// EXPLICIT-DAG: [[INIT:%.+]] = hw.bitcast [[CONSTANT]] : (i8) -> !hw.union<raw: i8, nibbles: !hw.array<2xi4>>
// EXPLICIT-DAG: %state = llhd.sig [[INIT]] {llhd.explicit_init} : !hw.union<raw: i8, nibbles: !hw.array<2xi4>>
// EXPLICIT: llhd.process
// ERROR: error: aggregate register initialization is unsupported

//--- uninitialized.sv
module overlay_value_repro(input logic clk, input logic [7:0] data,
                           output logic [7:0] out);
  typedef union packed {
    logic [7:0] raw;
    logic [1:0][3:0] nibbles;
  } overlay_t;
  overlay_t overlay_value;
  always @(posedge clk) begin
    overlay_value <= data;
    out <= overlay_value.raw;
  end
endmodule

module nested_aggregate(input logic clk, input logic [31:0] data,
                        output logic [31:0] out);
  typedef struct packed {
    logic [3:0] lo;
    logic [3:0] hi;
  } lane_t;
  lane_t [1:0][1:0] matrix_value;
  always @(posedge clk) begin
    matrix_value <= data;
    out <= matrix_value;
  end
endmodule

//--- explicit.sv
module union_init(input logic clk, input logic [7:0] data,
                  output logic [7:0] out);
  typedef union packed {
    logic [7:0] raw;
    logic [1:0][3:0] nibbles;
  } overlay_t;
  overlay_t state = 8'h5a;
  assign out = state.raw;
  always @(posedge clk) state <= data;
endmodule

module struct_init(input logic clk, input logic [7:0] data,
                   output logic [7:0] out);
  typedef struct packed {
    logic [3:0] lo;
    logic [3:0] hi;
  } lane_t;
  lane_t state = '{lo: 4'ha, hi: 4'h5};
  assign out = state;
  always @(posedge clk) state <= data;
endmodule

module array_init(input logic clk, input logic [7:0] data,
                  output logic [7:0] out);
  logic [1:0][3:0] state = '{4'h5, 4'ha};
  assign out = state;
  always @(posedge clk) state <= data;
endmodule

//--- dynamic.sv
module dynamic_init(input logic clk, input logic [7:0] data,
                    output logic [7:0] out);
  typedef union packed {
    logic [7:0] raw;
    logic [1:0][3:0] nibbles;
  } overlay_t;
  overlay_t state = data;
  assign out = state.raw;
  always @(posedge clk) state <= data;
endmodule
