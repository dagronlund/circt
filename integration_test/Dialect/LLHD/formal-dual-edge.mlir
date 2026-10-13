// REQUIRES: slang, verilator
// RUN: circt-verilog --detect-memories=false --ir-hw %CIRCT_SOURCE%/test/circt-verilog/formal-dual-edge.sv -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued -o %t.two-valued.mlir
// RUN: circt-opt %t.two-valued.mlir --lower-llhd-formal-to-core -o %t.formal.mlir
// RUN: circt-opt %t.formal.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.model %t.sv %S/Inputs/dual-edge-driver.cpp > %t.build.log 2>&1
// RUN: %t.model/Vtop | FileCheck %s --check-prefix=TOGGLE
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module enabled --Mdir %t.enabled.model %t.sv %S/Inputs/dual-edge-enabled-driver.cpp > %t.enabled.build.log 2>&1
// RUN: %t.enabled.model/Venabled | FileCheck %s --check-prefix=ENABLED
// RUN: circt-verilog --ir-llhd %CIRCT_SOURCE%/test/circt-verilog/formal-dual-edge.sv | circt-opt --lower-llhd-formal-to-core -o %t.direct.mlir
// RUN: circt-opt %t.direct.mlir --lower-seq-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.direct.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module top --Mdir %t.direct.model %t.direct.sv %S/Inputs/dual-edge-driver.cpp > %t.direct.build.log 2>&1
// RUN: %t.direct.model/Vtop | FileCheck %s --check-prefix=TOGGLE
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build -Wno-fatal --top-module enabled --Mdir %t.direct.enabled.model %t.direct.sv %S/Inputs/dual-edge-enabled-driver.cpp > %t.direct.enabled.build.log 2>&1
// RUN: %t.direct.enabled.model/Venabled | FileCheck %s --check-prefix=ENABLED
// TOGGLE: Initial value 1 and 256 alternating clock edges passed
// ENABLED: 512 enabled dual-edge updates and hold checks passed
module {}
