// RUN: circt-verilog %s | FileCheck %s --check-prefixes=CHECK,DEFAULT
// RUN: circt-verilog --sroa %s | FileCheck %s
// REQUIRES: slang
// UNSUPPORTED: valgrind

// Writing a struct slice containing a union must update its shared storage.
// CHECK-LABEL: hw.module @top(
// CHECK: %[[ZERO:.*]] = hw.constant 0 : i16
// DEFAULT: %[[INIT:.*]] = hw.bitcast %[[ZERO]] : (i16) -> !hw.struct<
// CHECK: %[[PAYLOAD:.*]] = hw.union_create "bytes", %data
// DEFAULT: %[[PACKET:.*]] = hw.struct_inject %[[INIT]]["payload"], %[[PAYLOAD]]
// DEFAULT: %[[RESULT:.*]] = hw.bitcast %[[PACKET]] : {{.*}} -> i16
// DEFAULT: hw.output %[[RESULT]] : i16
// CHECK: }
module top(input logic [7:0] data, output logic [15:0] result);
  typedef union packed {
    logic [7:0] bytes;
    logic [1:0][3:0] nibbles;
  } payload_t;
  typedef struct packed {logic [7:0] header; payload_t payload;} packet_t;
  packet_t packet;
  always_comb begin
    packet = '0;
    packet[7:0] = data;
  end
  assign result = packet;
endmodule

// Flatten an array view of the union and cross the union/header boundary.
// CHECK-LABEL: hw.module @array_view(
// CHECK-NOT: llhd.
// CHECK-NOT: seq.
// CHECK: hw.output
module array_view(input logic [7:0] data, output logic [15:0] result);
  typedef union packed {
    logic [1:0][3:0] nibbles;
    logic [7:0] bytes;
  } payload_t;
  typedef struct packed {logic [7:0] header; payload_t payload;} packet_t;
  packet_t packet;
  always_comb begin
    packet = '0;
    packet[11:4] = data;
  end
  assign result = packet;
endmodule

// Dynamic slices use the same union flattening as constant slices.
// CHECK-LABEL: hw.module @dynamic_write(
// CHECK-NOT: moore.
// CHECK: hw.output
module dynamic_write(input logic [7:0] data, input logic [3:0] index,
                     output logic [15:0] result);
  typedef union packed {
    struct packed {logic [3:0] upper, lower;} fields;
    logic [7:0] bytes;
  } payload_t;
  typedef struct packed {logic [7:0] header; payload_t payload;} packet_t;
  packet_t packet;
  always_comb begin
    packet = '0;
    packet[index +: 8] = data;
  end
  assign result = packet;
endmodule
