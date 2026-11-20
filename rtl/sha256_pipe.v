// sha256_pipe.v — fully pipelined SHA-256 compression core (FIPS 180-4).
// _muse — written 2026-11-20 for Branden's hand-built mining core project.
//
// The iterative sha256_core unrolled in space instead of time: 64 round
// stages, one round per stage, one new block accepted every clock once
// the pipe is full. Same round math as sha256_core, line for line — the
// two cores are meant to be read side by side.
//
// Interface: present `block` and `state_in` with `in_valid` high for one
// clock. 65 clocks later the same slot emerges at the output with
// `out_valid` high and
//     digest = state_in + (final working variables)   (word-wise mod 2^32)
// Results emerge in input order, one per clock. Padding is the caller's
// job — this core eats raw 512-bit blocks, exactly like sha256_core.
//
// Per-stage state, all of it travelling with the slot:
//   vars  — the eight working variables a..h          (256 bits)
//   hin   — the chaining value, carried for the final add (256 bits)
//   win   — the message-schedule window w[0..15]      (512 bits)
//   blk   — the unconsumed message words, MSB first   (512 bits)
// `blk` is only consumed by stages 0..15 (W[t] for t<16 comes straight
// from the block), so stages 16..63 are built with WITH_BLK=0 and do not
// carry it. That is the one deliberate irregularity, and it is worth
// roughly 24k flip-flops per pipeline.
`default_nettype none

module sha256_pipe_stage #(
    parameter T = 0,          // round index, 0..63
    parameter WITH_BLK = 1    // 0 for T>=16: no block words left to carry
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         valid_in,
    input  wire [255:0] vars_in,   // {a,b,c,d,e,f,g,h}, a at [255:224]
    input  wire [255:0] hin,       // chaining value, pass-through
    input  wire [511:0] win,       // {w15,...,w0}, w15 at [511:480]
    input  wire [511:0] blk_in,    // unconsumed block words, MSB first
    output reg          valid_out,
    output reg  [255:0] vars_out,
    output reg  [255:0] hin_out,
    output reg  [511:0] win_out,
    output reg  [511:0] blk_out
);
    // ---- Round constants K[t] (FIPS 180-4 §4.2.2) — same table as sha256_core ----
    function [31:0] K;
        input [5:0] t;
        begin
            case (t)
                6'd0:  K = 32'h428a2f98; 6'd1:  K = 32'h71374491;
                6'd2:  K = 32'hb5c0fbcf; 6'd3:  K = 32'he9b5dba5;
                6'd4:  K = 32'h3956c25b; 6'd5:  K = 32'h59f111f1;
                6'd6:  K = 32'h923f82a4; 6'd7:  K = 32'hab1c5ed5;
                6'd8:  K = 32'hd807aa98; 6'd9:  K = 32'h12835b01;
                6'd10: K = 32'h243185be; 6'd11: K = 32'h550c7dc3;
                6'd12: K = 32'h72be5d74; 6'd13: K = 32'h80deb1fe;
                6'd14: K = 32'h9bdc06a7; 6'd15: K = 32'hc19bf174;
                6'd16: K = 32'he49b69c1; 6'd17: K = 32'hefbe4786;
                6'd18: K = 32'h0fc19dc6; 6'd19: K = 32'h240ca1cc;
                6'd20: K = 32'h2de92c6f; 6'd21: K = 32'h4a7484aa;
                6'd22: K = 32'h5cb0a9dc; 6'd23: K = 32'h76f988da;
                6'd24: K = 32'h983e5152; 6'd25: K = 32'ha831c66d;
                6'd26: K = 32'hb00327c8; 6'd27: K = 32'hbf597fc7;
                6'd28: K = 32'hc6e00bf3; 6'd29: K = 32'hd5a79147;
                6'd30: K = 32'h06ca6351; 6'd31: K = 32'h14292967;
                6'd32: K = 32'h27b70a85; 6'd33: K = 32'h2e1b2138;
                6'd34: K = 32'h4d2c6dfc; 6'd35: K = 32'h53380d13;
                6'd36: K = 32'h650a7354; 6'd37: K = 32'h766a0abb;
                6'd38: K = 32'h81c2c92e; 6'd39: K = 32'h92722c85;
                6'd40: K = 32'ha2bfe8a1; 6'd41: K = 32'ha81a664b;
                6'd42: K = 32'hc24b8b70; 6'd43: K = 32'hc76c51a3;
                6'd44: K = 32'hd192e819; 6'd45: K = 32'hd6990624;
                6'd46: K = 32'hf40e3585; 6'd47: K = 32'h106aa070;
                6'd48: K = 32'h19a4c116; 6'd49: K = 32'h1e376c08;
                6'd50: K = 32'h2748774c; 6'd51: K = 32'h34b0bcb5;
                6'd52: K = 32'h391c0cb3; 6'd53: K = 32'h4ed8aa4a;
                6'd54: K = 32'h5b9cca4f; 6'd55: K = 32'h682e6ff3;
                6'd56: K = 32'h748f82ee; 6'd57: K = 32'h78a5636f;
                6'd58: K = 32'h84c87814; 6'd59: K = 32'h8cc70208;
                6'd60: K = 32'h90befffa; 6'd61: K = 32'ha4506ceb;
                6'd62: K = 32'hbef9a3f7; 6'd63: K = 32'hc67178f2;
                default: K = 32'h00000000;
            endcase
        end
    endfunction

    function [31:0] rotr;
        input [31:0] x;
        input [4:0]  n;
        begin rotr = (x >> n) | (x << (6'd32 - {1'b0, n})); end
    endfunction

    // Message-schedule small sigmas (FIPS 180-4 §4.1.2)
    function [31:0] s0;
        input [31:0] x;
        begin s0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3); end
    endfunction
    function [31:0] s1;
        input [31:0] x;
        begin s1 = rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10); end
    endfunction

    // ---- Unpack the working variables ----
    wire [31:0] a = vars_in[255:224];
    wire [31:0] b = vars_in[223:192];
    wire [31:0] c = vars_in[191:160];
    wire [31:0] d = vars_in[159:128];
    wire [31:0] e = vars_in[127:96];
    wire [31:0] f = vars_in[95:64];
    wire [31:0] g = vars_in[63:32];
    wire [31:0] h = vars_in[31:0];

    // ---- This round's message word W[T] ----
    // Window layout matches sha256_core: w[14] is W[t-2], w[9] is W[t-7],
    // w[1] is W[t-15], w[0] is W[t-16] when the round begins.
    wire [31:0] w_expand = s1(win[479:448]) + win[319:288]
                         + s0(win[63:32]) + win[31:0];
    wire [31:0] w_round  = (WITH_BLK != 0 && T < 16) ? blk_in[511:480]
                                                    : w_expand;

    // ---- The round itself — identical to sha256_core ----
    wire [31:0] S1  = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
    wire [31:0] ch  = (e & f) ^ (~e & g);
    wire [31:0] t1  = h + S1 + ch + K(T[5:0]) + w_round;
    wire [31:0] S0  = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
    wire [31:0] maj = (a & b) ^ (a & c) ^ (b & c);
    wire [31:0] t2  = S0 + maj;
    wire [31:0] a_n = t1 + t2;
    wire [31:0] e_n = d + t1;
    // (b_n, c_n, d_n, f_n, g_n, h_n) = (a, b, c, e, f, g) — plain shifts.

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_in;
        end
        vars_out <= {a_n, a, b, c, e_n, e, f, g};
        hin_out  <= hin;
        win_out  <= {w_round, win[511:32]};
        blk_out  <= (WITH_BLK != 0) ? {blk_in[479:0], 32'b0} : 512'b0;
    end
endmodule

module sha256_pipe (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         in_valid,
    input  wire [511:0] block,
    input  wire [255:0] state_in,
    output reg          out_valid,
    output reg  [255:0] digest
);
    // Stage interconnect: index 0 is the pipe input, index t+1 the
    // registered output of stage t.
    wire        v   [0:64];
    wire [255:0] vv [0:64];
    wire [255:0] hh [0:64];
    wire [511:0] ww [0:64];
    wire [511:0] bb [0:64];

    assign v[0]  = in_valid;
    assign vv[0] = state_in;
    assign hh[0] = state_in;
    assign ww[0] = 512'b0;      // window fills from the block, stages 0..15
    assign bb[0] = block;

    genvar t;
    generate
        for (t = 0; t < 64; t = t + 1) begin : stage
            sha256_pipe_stage #(.T(t), .WITH_BLK(t < 16 ? 1 : 0)) u (
                .clk(clk), .rst_n(rst_n),
                .valid_in(v[t]), .vars_in(vv[t]), .hin(hh[t]),
                .win(ww[t]), .blk_in(bb[t]),
                .valid_out(v[t+1]), .vars_out(vv[t+1]), .hin_out(hh[t+1]),
                .win_out(ww[t+1]), .blk_out(bb[t+1])
            );
        end
    endgenerate

    // Final feed-forward add, registered: digest = hin + vars, word-wise.
    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
        end else begin
            out_valid <= v[64];
        end
        digest <= { hh[64][255:224] + vv[64][255:224],
                    hh[64][223:192] + vv[64][223:192],
                    hh[64][191:160] + vv[64][191:160],
                    hh[64][159:128] + vv[64][159:128],
                    hh[64][127:96]  + vv[64][127:96],
                    hh[64][95:64]   + vv[64][95:64],
                    hh[64][63:32]   + vv[64][63:32],
                    hh[64][31:0]    + vv[64][31:0] };
    end
endmodule
`default_nettype wire
