// RUN: circt-opt %s --lower-llhd-formal-to-core --canonicalize --cse | FileCheck %s --implicit-check-not=llhd. --implicit-check-not=ltl. --implicit-check-not=cf. --implicit-check-not=unrealized_conversion_cast
// Regression: a one-entry stream stage with a procedural scoreboard, immediate
// checks, property self-loops, sampled history, fixed repetition and disable iff.
// CHECK: hw.module @stream_stage_formal
// CHECK: verif.clocked_assume
// CHECK: verif.clocked_assert
// CHECK: verif.clocked_cover
// CHECK: seq.firreg
// CHECK: reset async
// CHECK: verif.clocked_cover
// CHECK: hw.output

module {
  hw.module private @std_register(in %clk : i1, in %rst : i1, in %enable : i1, in %next : i1, out value : i1) {
    %true = hw.constant true
    %0 = comb.xor %rst, %true : i1
    %1 = comb.and %0, %enable, %next : i1
    %2 = comb.or %rst, %enable : i1
    %3 = seq.to_clock %clk
    %4 = comb.mux bin %2, %1, %value : i1
    %value = seq.firreg %4 clock %3 : i1
    hw.output %value : i1
  }
  hw.module private @std_register_0(in %clk : i1, in %rst : i1, in %enable : i1, in %next : i4, out value : i4) {
    %true = hw.constant true
    %c0_i4 = hw.constant 0 : i4
    %0 = comb.xor %enable, %true : i1
    %1 = comb.or %rst, %0 : i1
    %2 = comb.mux %1, %c0_i4, %next : i4
    %3 = comb.or %rst, %enable : i1
    %4 = seq.to_clock %clk
    %5 = comb.mux bin %3, %2, %value : i4
    %value = seq.firreg %5 clock %4 : i4
    hw.output %value : i4
  }
  hw.module private @stream_stage(in %clk : i1, in %rst : i1, in %stream_in_valid : i1, out stream_in_ready : i1, in %stream_in_payload : i4, out stream_out_valid : i1, in %stream_out_ready : i1, out stream_out_payload : i4) {
    %true = hw.constant true
    %false = hw.constant false
    %genblk1.valid_register_inst.value = hw.instance "genblk1.valid_register_inst" @std_register(clk: %clk: i1, rst: %rst: i1, enable: %3: i1, next: %2: i1) -> (value: i1)
    %genblk1.payload_register_inst.value = hw.instance "genblk1.payload_register_inst" @std_register_0(clk: %clk: i1, rst: %false: i1, enable: %2: i1, next: %stream_in_payload: i4) -> (value: i4)
    %0 = comb.xor %genblk1.valid_register_inst.value, %true : i1
    %1 = comb.or %stream_out_ready, %0 : i1
    %2 = comb.and %stream_in_valid, %1 : i1
    %3 = comb.or %2, %stream_out_ready : i1
    hw.output %1, %genblk1.valid_register_inst.value, %genblk1.payload_register_inst.value : i1, i1, i4
  }
  hw.module @stream_stage_formal(in %clk : i1, in %rst : i1, in %in_valid : i1, in %in_payload : i4, in %out_ready : i1) {
    %0 = llhd.constant_time <0ns, 1d, 0e>
    %true = hw.constant true
    %c-1_i2 = hw.constant -1 : i2
    %c0_i4 = hw.constant 0 : i4
    %c1_i2 = hw.constant 1 : i2
    %c-2_i2 = hw.constant -2 : i2
    %c0_i2 = hw.constant 0 : i2
    %false = hw.constant false
    %past_valid = llhd.sig %false : i1
    %1 = llhd.prb %past_valid : i1
    %occupied = llhd.sig %false {llhd.unconstrained} : i1
    %2 = llhd.prb %occupied : i1
    %expected_payload = llhd.sig %c0_i4 {llhd.unconstrained} : i4
    %3 = llhd.prb %expected_payload : i4
    %stall_history = llhd.sig %c0_i2 {llhd.unconstrained} : i2
    %4 = llhd.prb %stall_history : i2
    %saw_two_cycle_stall = llhd.sig %false {llhd.unconstrained} : i1
    %5 = llhd.prb %saw_two_cycle_stall : i1
    %dut.stream_in_ready, %dut.stream_out_valid, %dut.stream_out_payload = hw.instance "dut" @stream_stage(clk: %clk: i1, rst: %rst: i1, stream_in_valid: %in_valid: i1, stream_in_payload: %in_payload: i4, stream_out_ready: %out_ready: i1) -> (stream_in_ready: i1, stream_out_valid: i1, stream_out_payload: i4)
    %6 = comb.and %in_valid, %dut.stream_in_ready : i1
    %7 = comb.and %dut.stream_out_valid, %out_ready : i1
    %8 = comb.xor %out_ready, %true : i1
    %9 = comb.and %dut.stream_out_valid, %8 : i1
    %10:10 = llhd.process -> i1, i1, i1, i1, i2, i1, i1, i1, i4, i1 {
      cf.br ^bb1(%false, %false, %false, %false, %c0_i2, %false, %false, %false, %c0_i4, %false : i1, i1, i1, i1, i2, i1, i1, i1, i4, i1)
    ^bb1(%13: i1, %14: i1, %15: i1, %16: i1, %17: i2, %18: i1, %19: i1, %20: i1, %21: i4, %22: i1):  // 4 preds: ^bb0, ^bb2, ^bb10, ^bb17
      llhd.wait yield (%13, %14, %15, %16, %17, %18, %19, %20, %21, %22 : i1, i1, i1, i1, i2, i1, i1, i1, i4, i1), (%clk : i1), ^bb2(%clk : i1)
    ^bb2(%23: i1):  // pred: ^bb1
      %24 = comb.xor bin %23, %true : i1
      %25 = comb.and bin %24, %clk : i1
      cf.cond_br %25, ^bb3, ^bb1(%1, %false, %2, %false, %4, %false, %5, %false, %3, %false : i1, i1, i1, i1, i2, i1, i1, i1, i4, i1)
    ^bb3:  // pred: ^bb2
      %26 = comb.xor %1, %true : i1
      %27 = comb.icmp eq %rst, %26 : i1
      verif.assume %27 label "" : i1
      %28 = comb.xor %rst, %true : i1
      %29 = ltl.past %rst, 1 clk %clk : i1
      %30 = comb.xor %29, %true : i1
      %31 = comb.and %1, %28, %30 : i1
      cf.cond_br %31, ^bb4, ^bb6
    ^bb4:  // pred: ^bb3
      %32 = comb.xor %dut.stream_in_ready, %true : i1
      %33 = comb.and %in_valid, %32 : i1
      %34 = ltl.past %33, 1 clk %clk : i1
      cf.cond_br %34, ^bb5, ^bb6
    ^bb5:  // pred: ^bb4
      verif.assume %in_valid label "" : i1
      %35 = ltl.past %in_payload, 1 clk %clk : i4
      %36 = comb.icmp eq %in_payload, %35 : i4
      verif.assume %36 label "" : i1
      cf.br ^bb6
    ^bb6:  // 3 preds: ^bb3, ^bb4, ^bb5
      cf.cond_br %rst, ^bb10(%false, %true, %c0_i2, %false, %true, %3, %false : i1, i1, i2, i1, i1, i4, i1), ^bb7
    ^bb7:  // pred: ^bb6
      %37 = comb.concat %6, %7 : i1, i1
      %38 = comb.icmp ceq %37, %c-2_i2 : i2
      cf.cond_br %38, ^bb9(%true, %true : i1, i1), ^bb8
    ^bb8:  // pred: ^bb7
      %39 = comb.icmp ceq %37, %c1_i2 : i2
      cf.cond_br %39, ^bb9(%false, %true : i1, i1), ^bb9(%2, %false : i1, i1)
    ^bb9(%40: i1, %41: i1):  // 3 preds: ^bb7, ^bb8, ^bb8
      %42 = comb.mux %6, %in_payload, %3 : i4
      %43 = comb.extract %4 from 0 : (i2) -> i1
      %44 = comb.concat %43, %9 : i1, i1
      %45 = comb.icmp eq %4, %c-1_i2 : i2
      cf.cond_br %45, ^bb10(%40, %41, %44, %true, %true, %42, %6 : i1, i1, i2, i1, i1, i4, i1), ^bb10(%40, %41, %44, %5, %false, %42, %6 : i1, i1, i2, i1, i1, i4, i1)
    ^bb10(%46: i1, %47: i1, %48: i2, %49: i1, %50: i1, %51: i4, %52: i1):  // 3 preds: ^bb6, ^bb9, ^bb9
      %53 = comb.and %1, %28 : i1
      cf.cond_br %53, ^bb11, ^bb1(%true, %true, %46, %47, %48, %true, %49, %50, %51, %52 : i1, i1, i1, i1, i2, i1, i1, i1, i4, i1)
    ^bb11:  // pred: ^bb10
      %54 = comb.icmp eq %dut.stream_out_valid, %2 : i1
      verif.assert %54 label "" : i1
      cf.cond_br %dut.stream_out_valid, ^bb12, ^bb13
    ^bb12:  // pred: ^bb11
      %55 = comb.icmp eq %dut.stream_out_payload, %3 : i4
      verif.assert %55 label "" : i1
      cf.br ^bb13
    ^bb13:  // 2 preds: ^bb11, ^bb12
      %56 = comb.xor %7, %true : i1
      %57 = comb.or %56, %2 : i1
      verif.assert %57 label "" : i1
      %58 = comb.xor %6, %true : i1
      %59 = comb.xor %2, %true : i1
      %60 = comb.or %58, %59, %7 : i1
      verif.assert %60 label "" : i1
      %61 = comb.or %59, %out_ready : i1
      %62 = comb.icmp eq %dut.stream_in_ready, %61 : i1
      verif.assert %62 label "" : i1
      cf.cond_br %29, ^bb14, ^bb15
    ^bb14:  // pred: ^bb13
      %63 = comb.xor %dut.stream_out_valid, %true : i1
      verif.assert %63 label "" : i1
      cf.br ^bb15
    ^bb15:  // 2 preds: ^bb13, ^bb14
      %64 = ltl.past %9, 1 clk %clk : i1
      %65 = comb.and %30, %64 : i1
      cf.cond_br %65, ^bb16, ^bb17
    ^bb16:  // pred: ^bb15
      verif.assert %dut.stream_out_valid label "" : i1
      %66 = ltl.past %dut.stream_out_payload, 1 clk %clk : i4
      %67 = comb.icmp eq %dut.stream_out_payload, %66 : i4
      verif.assert %67 label "" : i1
      cf.br ^bb17
    ^bb17:  // 2 preds: ^bb15, ^bb16
      %68 = comb.and %59, %6 : i1
      verif.cover %68 label "" : i1
      %69 = comb.icmp ne %in_payload, %dut.stream_out_payload : i4
      %70 = comb.and %6, %7, %69 : i1
      verif.cover %70 label "" : i1
      %71 = comb.icmp eq %4, %c-1_i2 : i2
      %72 = comb.and %71, %7 : i1
      verif.cover %72 label "" : i1
      %73 = comb.and %5, %59 : i1
      verif.cover %73 label "" : i1
      cf.br ^bb1(%true, %true, %46, %47, %48, %true, %49, %50, %51, %52 : i1, i1, i1, i1, i2, i1, i1, i1, i4, i1)
    }
    llhd.drv %past_valid, %10#0 after %0 if %10#1 : i1
    llhd.drv %occupied, %10#2 after %0 if %10#3 : i1
    llhd.drv %stall_history, %10#4 after %0 if %10#5 : i2
    llhd.drv %saw_two_cycle_stall, %10#6 after %0 if %10#7 : i1
    llhd.drv %expected_payload, %10#8 after %0 if %10#9 : i4
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %1, %true : i1
      %14 = comb.icmp eq %rst, %13 : i1
      verif.clocked_assume %14, posedge %clk : i1
      cf.br ^bb1
    }
    %11 = ltl.past %in_payload, 1 clk %clk : i4
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %rst, %true : i1
      %14 = comb.xor %dut.stream_in_ready, %true : i1
      %15 = comb.and %in_valid, %14 : i1
      %16 = comb.icmp eq %11, %in_payload : i4
      %17 = comb.and %in_valid, %16 : i1
      %18 = ltl.delay %true, 1, 0 : i1
      %19 = ltl.concat %15, %18 : i1, !ltl.sequence
      %20 = ltl.implication %19, %17 : !ltl.sequence, i1
      verif.clocked_assume %20 if %13, posedge %clk : !ltl.property
      cf.br ^bb1
    }
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %dut.stream_out_valid, %true : i1
      %14 = ltl.delay %true, 1, 0 : i1
      %15 = ltl.concat %rst, %14 : i1, !ltl.sequence
      %16 = ltl.implication %15, %13 : !ltl.sequence, i1
      verif.clocked_assert %16, posedge %clk : !ltl.property
      cf.br ^bb1
    }
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %rst, %true : i1
      %14 = comb.icmp eq %dut.stream_out_valid, %2 : i1
      %15 = ltl.implication %1, %14 : i1, i1
      verif.clocked_assert %15 if %13, posedge %clk : !ltl.property
      cf.br ^bb1
    }
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %rst, %true : i1
      %14 = comb.and %1, %dut.stream_out_valid : i1
      %15 = comb.icmp eq %dut.stream_out_payload, %3 : i4
      %16 = ltl.implication %14, %15 : i1, i1
      verif.clocked_assert %16 if %13, posedge %clk : !ltl.property
      cf.br ^bb1
    }
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %rst, %true : i1
      %14 = comb.and %1, %7 : i1
      %15 = ltl.implication %14, %2 : i1, i1
      verif.clocked_assert %15 if %13, posedge %clk : !ltl.property
      cf.br ^bb1
    }
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %rst, %true : i1
      %14 = comb.and %1, %6 : i1
      %15 = comb.xor %2, %true : i1
      %16 = comb.or %15, %7 : i1
      %17 = ltl.implication %14, %16 : i1, i1
      verif.clocked_assert %17 if %13, posedge %clk : !ltl.property
      cf.br ^bb1
    }
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %rst, %true : i1
      %14 = comb.xor %2, %true : i1
      %15 = comb.or %14, %out_ready : i1
      %16 = comb.icmp eq %dut.stream_in_ready, %15 : i1
      %17 = ltl.implication %1, %16 : i1, i1
      verif.clocked_assert %17 if %13, posedge %clk : !ltl.property
      cf.br ^bb1
    }
    %12 = ltl.past %dut.stream_out_payload, 1 clk %clk : i4
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %rst, %true : i1
      %14 = comb.and %1, %9 : i1
      %15 = comb.icmp eq %12, %dut.stream_out_payload : i4
      %16 = comb.and %dut.stream_out_valid, %15 : i1
      %17 = ltl.delay %true, 1, 0 : i1
      %18 = ltl.concat %14, %17 : i1, !ltl.sequence
      %19 = ltl.implication %18, %16 : !ltl.sequence, i1
      verif.clocked_assert %19 if %13, posedge %clk : !ltl.property
      cf.br ^bb1
    }
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %rst, %true : i1
      %14 = comb.and %1, %6 : i1
      %15 = comb.icmp eq %dut.stream_out_payload, %11 : i4
      %16 = comb.and %dut.stream_out_valid, %15 : i1
      %17 = ltl.delay %true, 1, 0 : i1
      %18 = ltl.concat %14, %17 : i1, !ltl.sequence
      %19 = ltl.implication %18, %16 : !ltl.sequence, i1
      verif.clocked_assert %19 if %13, posedge %clk : !ltl.property
      cf.br ^bb1
    }
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %rst, %true : i1
      %14 = comb.xor %2, %true : i1
      %15 = comb.and %1, %14, %6 : i1
      verif.clocked_cover %15 if %13, posedge %clk : i1
      cf.br ^bb1
    }
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %rst, %true : i1
      %14 = comb.icmp ne %in_payload, %dut.stream_out_payload : i4
      %15 = comb.and %1, %6, %7, %14 : i1
      verif.clocked_cover %15 if %13, posedge %clk : i1
      cf.br ^bb1
    }
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %rst, %true : i1
      %14 = comb.and %1, %9 : i1
      %15 = ltl.repeat %14, 2, 0 : i1
      %16 = ltl.delay %7, 1, 0 : i1
      %17 = ltl.concat %15, %16 : !ltl.sequence, !ltl.sequence
      verif.clocked_cover %17 if %13, posedge %clk : !ltl.sequence
      cf.br ^bb1
    }
    llhd.process {
      cf.br ^bb1
    ^bb1:  // 2 preds: ^bb0, ^bb1
      %13 = comb.xor %rst, %true : i1
      %14 = comb.xor %2, %true : i1
      %15 = comb.and %1, %14, %6 : i1
      %16 = ltl.delay %15, 0, 0 : i1
      %17 = ltl.repeat %9, 2, 0 : i1
      %18 = ltl.delay %17, 1, 0 : !ltl.sequence
      %19 = comb.xor %6, %true : i1
      %20 = comb.and %7, %19 : i1
      %21 = ltl.delay %20, 1, 0 : i1
      %22 = ltl.delay %14, 1, 0 : i1
      %23 = ltl.concat %16, %18, %21, %22 : !ltl.sequence, !ltl.sequence, !ltl.sequence, !ltl.sequence
      verif.clocked_cover %23 if %13, posedge %clk : !ltl.sequence
      cf.br ^bb1
    }
    hw.output
  }
}
