module ADC_Capture(clk, rst_n, adc_clk, trig1, trig2, trig_en, trig_pos, clr_cap_done,
                   decimator, addr_ptr, set_capture_done, dump, dump_fin, trig_cfg, we, en);
  /////////////////////////////////////////////////////////////////
  //This module controls the flow of data capture from the ADCs.//
  //Contains arming logic that determines if it can trigger.   //
  //May also end up controlling channel dumps.                //
  /////////////////////////////////////////////////////////////
  input clk, rst_n;
  input trig1, trig2;
  input trig_en;
  input adc_clk;
  input [8:0] trig_pos;
  input [7:0] trig_cfg;
  input clr_cap_done;
  input [4:0] decimator;
  input dump;
  input dump_fin; // dump finished
  output logic [8:0] addr_ptr;
  output logic set_capture_done;
  output we, en;

  typedef enum logic [2:0] { IDLE, WRT, WRT2, DONE, DUMP } state_t;
  state_t currentState, nextState;

  logic clr_cnt;
  logic [15:0] smpl_cnt, trig_cnt;
  logic [14:0] wait_cnt;
  logic [7:0] trace_end;
  logic en_wait_cnt;
  logic keep_ff;
  logic dumpDump; // indicates whether dump is complete
  wire armed, keep, en_trig_cnt, en_smpl_cnt;

  TriggerLogic trigLogic(.clk(clk), .rst_n(rst_n), .trig1(trig1), .trig2(trig2),
                       .trig_cfg(trig_cfg), .armed(armed), .trig_en(trig_en),
                       .set_capture_done(set_capture_done), .triggered(triggered));

  assign autoroll = trig_cfg[3] & !trig_cfg[2];
  assign capture_done = trig_cfg[5];

  ///////////////////
  // State flops //
  ////////////////
  always @(posedge clk, negedge rst_n) begin
    if(!rst_n)
      currentState <= IDLE;
    else
      currentState <= nextState;
  end

  ///////////////////////
  // Control smpl_cnt //
  /////////////////////
  always_ff @(posedge clk, negedge rst_n) begin
    if(!rst_n)
      smpl_cnt <= 4'h0;
    else if(clr_cnt)
      smpl_cnt <= 4'h0;
    else if(en_smpl_cnt)
      smpl_cnt <= smpl_cnt + 1;
  end

  ///////////////////////
  // Control trig_cnt //
  /////////////////////
  always_ff @(posedge clk, negedge rst_n) begin
    if(!rst_n)
      trig_cnt <= 4'h0;
    else if(clr_cnt)
      trig_cnt <= 4'h0;
    else if(en_trig_cnt)
      trig_cnt <= trig_cnt + 1;
  end
  
  ///////////////////////
  // Control wait_cnt //
  /////////////////////
  always_ff @(posedge clk, negedge rst_n) begin
    if(!rst_n) begin
      wait_cnt <= 15'h0000;
    end else if(keep) begin
      wait_cnt <= 15'h0000;
    end else if(en_wait_cnt) begin
      wait_cnt <= wait_cnt + 1;
    end
  end
  
  ///////////////////////
  // Control addr_ptr //
  /////////////////////
  always_ff @(posedge clk, negedge rst_n) begin
    if(!rst_n)
      addr_ptr <= 16'h0000;
    else if(keep_ff) // Wait one clock cycle after write to increment address
      addr_ptr <= addr_ptr + 1;
  end

  // Decide whether or not to keep/write sample based on decimator
  assign keep = (wait_cnt == (1 << decimator) - 1) ? 1'b1 : 1'b0;
  
  assign en_trig_cnt = (triggered | autoroll&armed)&keep;
  
  assign en_smpl_cnt = !triggered&keep;
  
  assign armed = (smpl_cnt + trig_pos >= 512) ? 1'b1 : 1'b0;
  
  assign we = keep;
  assign en = keep;

  // STATE MACHINE ftw
  always_comb begin
    clr_cnt = 1'b0;
    nextState = IDLE;
    set_capture_done = 1'b0;
    case(currentState)
      IDLE :  begin
        if((|trig_cfg[3:2]) & adc_clk) begin
          nextState = WRT;
          clr_cnt = 1'b1;
          trace_end = 8'h00;
        end else if(dump)
          nextState = DUMP;
      end WRT : begin
        en_wait_cnt = 1'b1; // Count half the time
        nextState = WRT2;
      end WRT2 : begin
        if(trig_cnt == trig_pos) begin
          set_capture_done = 1'b1;
          trace_end = addr_ptr;
          nextState = DONE;
        end else
          nextState = WRT;
      end DONE : begin
        if(capture_done)
          nextState = DONE;
        else
          nextState = IDLE;
      end DUMP : begin // Wait for channel dump to finish
        if(dumpDump)
          nextState = IDLE;
        else
          nextState = DUMP;
      end 
      endcase
  end
  // END MAIN LOGIC
  // BEGIN DUMP LOGIC
  
  // END DUMP LOGIC
endmodule