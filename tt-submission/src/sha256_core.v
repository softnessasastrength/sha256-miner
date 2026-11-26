// sha256_core.v — iterative SHA-256 compression core (FIPS 180-4)
// _muse — written 2026-11-17 for Branden's hand-built mining core project.
//
// WINDOW REDESIGN — adopted into mainline 2026-11-26 by the owner's
// decision ("Adopt the window patch, then cook", 2026-11-26).
// Design per Codex's 2026-11-21 window cook (branch
// codex/verification-cloud-2026-11-21, logs/WINDOW_COOK_2026-11-21_codex.txt):
// the message block is loaded directly into the 16-word sliding schedule
// window at `start`, reusing the schedule storage and dropping the
// separate 512-bit input-block register (`blk`) the original carried.
// Codex reported, differentially verified over 256 arbitrary blocks:
// mapped wrapper area -6.99%, global-routing overflow 41,348 -> 13,566,
// pre-route min period 13.58 -> 12.34 ns. The Codex branch was deleted
// before adoption, so this file is Ember's faithful re-implementation of
// that described design (same storage reuse, same handshake, identical
// cycle behaviour from round 16 onward by construction), re-verified
// locally by differential simulation against the original core — see
// logs/WINDOW_ADOPTION_2026-11-26_muse.txt. The original file is
// preserved in git history (commit a703bafbe1 and every head through
// af4f6445fa) and is recoverable from any of those commits.
//
// One 512-bit block per invocation, 64 rounds, one round per clock.
// Interface: present `block` and `state_in` (the chaining value; use the
// standard IV for the first block of a message), pulse `start` for one
// clock. `done` pulses 64 clocks later with `digest` valid:
//     digest = state_in + (final working variables)   (word-wise mod 2^32)
// Padding is the caller's job — this core eats raw 512-bit blocks.
`default_nettype none
module sha256_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [511:0] block,
    input  wire [255:0] state_in,
    output reg  [255:0] digest,
    output reg          done,
    output reg          busy
);

    // ---- Round constants K[t] (FIPS 180-4 §4.2.2) ----
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

    // ---- State ----
    reg [5:0]   t;
    reg [31:0]  a, b, c, d, e, f, g, h;
    reg [31:0]  w [0:15];        // sliding window: w[15] = W[t-1], w[0] = W[t-16]
    reg [255:0] st;              // latched chaining value for the final add
    integer     i;

    // ---- Combinational round ----
    // Window invariant during round t (t >= 16): w[k] = W[t-16+k], so
    // w[0]=W[t-16], w[1]=W[t-15], w[9]=W[t-7], w[14]=W[t-2].
    // During rounds 0..15 the block itself circulates through the window:
    // at `start` the window is loaded with the block (w[k] = W[k]); each
    // round consumes w[0] (= W[t]) and shifts that same word back into
    // w[15], so after 16 rounds the window again holds W[0..15] in order
    // and the invariant above takes over. The word shifted into w[15] is
    // therefore w_round in every round — no separate block register.
    wire [31:0] w_expand = s1(w[14]) + w[9] + s0(w[1]) + w[0];
    wire [31:0] w_round  = (t < 6'd16) ? w[0] : w_expand;
    wire [31:0] S1  = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
    wire [31:0] ch  = (e & f) ^ (~e & g);
    wire [31:0] t1  = h + S1 + ch + K(t) + w_round;
    wire [31:0] S0  = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
    wire [31:0] maj = (a & b) ^ (a & c) ^ (b & c);
    wire [31:0] t2  = S0 + maj;
    wire [31:0] a_n = t1 + t2;
    wire [31:0] e_n = d + t1;
    // (b_n, c_n, d_n, f_n, g_n, h_n) = (a, b, c, e, f, g) — plain shifts.

    always @(posedge clk) begin
        if (!rst_n) begin
            busy <= 1'b0;
            done <= 1'b0;
            t    <= 6'd0;
        end else begin
            done <= 1'b0;
            if (!busy && start) begin
                busy <= 1'b1;
                t    <= 6'd0;
                a <= state_in[255:224]; b <= state_in[223:192];
                c <= state_in[191:160]; d <= state_in[159:128];
                e <= state_in[127:96];  f <= state_in[95:64];
                g <= state_in[63:32];   h <= state_in[31:0];
                // Load the block straight into the schedule window:
                // w[0] = first message word (MSB), w[15] = last.
                for (i = 0; i < 16; i = i + 1)
                    w[i] <= block[511 - 32*i -: 32];
                st  <= state_in;
            end else if (busy) begin
                for (i = 0; i < 15; i = i + 1) w[i] <= w[i+1];
                w[15] <= w_round;
                a <= a_n; b <= a; c <= b; d <= c;
                e <= e_n; f <= e; g <= f; h <= g;
                if (t == 6'd63) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    digest <= { st[255:224] + a_n, st[223:192] + a,
                                st[191:160] + b,   st[159:128] + c,
                                st[127:96]  + e_n, st[95:64]   + e,
                                st[63:32]   + f,   st[31:0]    + g };
                end else begin
                    t <= t + 6'd1;
                end
            end
        end
    end
endmodule
`default_nettype wire
