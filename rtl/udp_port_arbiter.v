`timescale 1ns / 1ps
// 3-way arbiter for UDP port access
module udp_port_arbiter(
        input clk,
        input reset,
        
        input req_A,
        output gnt_A,
        output [1:0] status_A,
        
        input req_B,
        output gnt_B,
        output [1:0] status_B,
        
        input req_C,
        output gnt_C,
        output [1:0] status_C,
        
        output req_Y,
        input [1:0] status_Y
    );

    
    localparam [1:0] UDPTX_RESULT_NONE = 2'b00;
    localparam [1:0] UDPTX_RESULT_SENDING = 2'b01;
    localparam [1:0] UDPTX_RESULT_SENT = 2'b11;
    localparam [1:0] UDPTX_RESULT_ERR = 2'b10;
    
    
    // TRY #2. State machine time.
    // This one is a bit more conservative than the other, but might have the advantage of actually working.
    // this could obviously be compressed and expanded arbitarily with a last_grant/current_grant register.
    // OH WELL
    localparam FSM_BITS=4;
    localparam [FSM_BITS-1:0] IDLE_A = 0;       //% idle, and last grant was A
    localparam [FSM_BITS-1:0] IDLE_B = 1;       //% idle, and last grant was B
    localparam [FSM_BITS-1:0] IDLE_C = 2;
    localparam [FSM_BITS-1:0] WAIT_A = 3;
    localparam [FSM_BITS-1:0] GRANT_A = 4;
    localparam [FSM_BITS-1:0] FINISH_A = 5;
    localparam [FSM_BITS-1:0] WAIT_B = 6;
    localparam [FSM_BITS-1:0] GRANT_B = 7;
    localparam [FSM_BITS-1:0] FINISH_B = 8;
    localparam [FSM_BITS-1:0] WAIT_C = 9;
    localparam [FSM_BITS-1:0] GRANT_C = 10;
    localparam [FSM_BITS-1:0] FINISH_C = 11;    
    reg [FSM_BITS-1:0] state = IDLE_A;
        
    // round-robin-y-kinda-thing 3-way arbiter
    // this is complicated by the fact that after granting
    // we have to wait for the UDP/IP stack to begin sending
    // and then wait for the result before moving on. So this
    // can't be done with an interconnect or anything like that,
    // at least not easily.
    always @(posedge clk) begin
        if (reset) state <= IDLE_A;
        else begin
            case (state)
                IDLE_A: if (status_Y != UDPTX_RESULT_SENDING) begin
                    if (req_B) state <= WAIT_B;
                    else if (req_C) state <= WAIT_C;
                    else if (req_A) state <= WAIT_A;
                end
                IDLE_B: if (status_Y != UDPTX_RESULT_SENDING) begin
                    if (req_C) state <= WAIT_C;
                    else if (req_A) state <= WAIT_A;
                    else if (req_B) state <= WAIT_B;
                end
                IDLE_C: if (status_Y != UDPTX_RESULT_SENDING) begin
                    if (req_A) state <= WAIT_A;
                    else if (req_B) state <= WAIT_B;
                    else if (req_C) state <= WAIT_C;
                end
                WAIT_A: if (status_Y == UDPTX_RESULT_SENDING) state <= GRANT_A;
                GRANT_A: if (status_Y != UDPTX_RESULT_SENDING) state <= FINISH_A;
                FINISH_A: state <= IDLE_A;
                WAIT_B: if (status_Y == UDPTX_RESULT_SENDING) state <= GRANT_B;
                GRANT_B: if (status_Y != UDPTX_RESULT_SENDING) state <= FINISH_B;
                FINISH_B: state <= IDLE_B;
                WAIT_C: if (status_Y == UDPTX_RESULT_SENDING) state <= GRANT_C;
                GRANT_C: if (status_Y != UDPTX_RESULT_SENDING) state <= FINISH_C;
                FINISH_C: state <= IDLE_C;
            endcase
        end
    end                

    assign gnt_A = (state == WAIT_A || state == GRANT_A || state == FINISH_A);
    assign status_A = (gnt_A) ? status_Y : UDPTX_RESULT_NONE;
    assign gnt_B = (state == WAIT_B || state == GRANT_B || state == FINISH_B);
    assign status_B = (gnt_B) ? status_Y : UDPTX_RESULT_NONE;
    assign gnt_C = (state == WAIT_C || state == GRANT_C || state == FINISH_C);
    assign status_C = (gnt_C) ? status_Y : UDPTX_RESULT_NONE;
    // As soon as status_Y transitions, grant_A/grant_B will still be active, so req_A/req_B will no longer be valid.
    // Hold them off for one clock there.
    assign req_Y = ((state == WAIT_A) && req_A) || ((state == WAIT_B) && req_B) || ((state == WAIT_C) && req_C);
endmodule
