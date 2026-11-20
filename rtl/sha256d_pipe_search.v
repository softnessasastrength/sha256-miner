// sha256d_pipe_search.v — nonce search over a cascade of sha256_pipe cores.
// _muse — written 2026-11-20 for Branden's hand-built mining core project.
//
// Same job and same interface as sha256d_search, a different shape of
// time: instead of one iterative core grinding nonces sequentially,
// three pipelined compression cores are cascaded and every nonce flows
// through all three —
//
//   pipe A: SHA-256 block 1 of the header (bytes 0..63),  state = IV
//   pipe B: SHA-256 block 2 (bytes 64..79 + padding),     state = A result
//   pipe C: SHA-256 of the 32-byte first digest (+ pad),  state = IV
//
// While nonce n is in pipe C, nonce n+1 is in pipe B and nonce n+2 is
// in pipe A: one completed double-hash per clock once the cascade is
// full (195 clocks of latency). Results emerge in nonce order, so the
// first hit is the lowest qualifying nonce — the same contract the
// iterative search keeps. Pipe A's input is nonce-independent (the
// midstate trick is deliberately NOT taken here: recomputing block 1
// per nonce keeps the cascade a uniform flow with no sequencer, and
// the throughput is identical — one hash per clock either way).
//
// The nonce travels beside the data as a tag, delayed through plain
// shift registers matched to the pipe latencies (65 clocks each),
// with a `last` bit marking the final nonce of the sweep.
//
// One operational contract: a search that ends in a HIT exits early,
// leaving higher nonces of the old job still in flight in the cascade.
// Pulse rst_n before the next `start` (or let 195 clocks drain). A
// search that ends by exhaustion drains itself.
`default_nettype none
module sha256d_pipe_search (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [639:0] header_template,
    input  wire [31:0]  nonce_start,
    input  wire [31:0]  nonce_limit,
    input  wire [255:0] target,
    output reg          found,
    output reg          done,
    output reg          busy,
    output reg  [31:0]  nonce_out,
    output reg  [255:0] digest_out,
    output reg  [31:0]  hashes_done
);
    localparam [255:0] IV = {32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
                             32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19};
    localparam LAT = 65;   // sha256_pipe latency in clocks

    // ---- latched job ----
    reg [639:0] tmpl;
    reg [255:0] tgt;
    reg [31:0]  limit_r;
    reg [31:0]  nonce;
    reg         feeding;

    wire feed_valid = feeding;
    wire feed_last  = feeding && (nonce == limit_r);

    // ---- pipe A: header block 1, state = IV ----
    wire        a_valid;
    wire [255:0] a_digest;
    sha256_pipe u_pipe_a (
        .clk(clk), .rst_n(rst_n), .in_valid(feed_valid),
        .block(tmpl[639:128]), .state_in(IV),
        .out_valid(a_valid), .digest(a_digest)
    );

    // ---- tag delay A: nonce (+last) aligned with pipe A's output ----
    reg [32:0] taga [0:LAT-1];
    integer i;
    always @(posedge clk) begin
        taga[0] <= {feed_last, nonce};
        for (i = 1; i < LAT; i = i + 1) taga[i] <= taga[i-1];
    end
    wire [31:0] nonce_b = taga[LAT-1][31:0];
    wire        last_b  = taga[LAT-1][32];

    // ---- pipe B: header block 2 with this slot's nonce, state = A ----
    wire [511:0] block_b = {tmpl[127:32],
                            nonce_b[7:0], nonce_b[15:8],
                            nonce_b[23:16], nonce_b[31:24],
                            8'h80, 312'b0, 64'd640};
    wire        b_valid;
    wire [255:0] b_digest;
    sha256_pipe u_pipe_b (
        .clk(clk), .rst_n(rst_n), .in_valid(a_valid),
        .block(block_b), .state_in(a_digest),
        .out_valid(b_valid), .digest(b_digest)
    );

    // ---- tag delay B ----
    reg [32:0] tagb [0:LAT-1];
    always @(posedge clk) begin
        tagb[0] <= {last_b, nonce_b};
        for (i = 1; i < LAT; i = i + 1) tagb[i] <= tagb[i-1];
    end
    wire [31:0] nonce_c = tagb[LAT-1][31:0];
    wire        last_c  = tagb[LAT-1][32];

    // ---- pipe C: hash of the first digest, state = IV ----
    wire [511:0] block_c = {b_digest, 8'h80, 184'b0, 64'd256};
    wire        c_valid;
    wire [255:0] c_digest;
    sha256_pipe u_pipe_c (
        .clk(clk), .rst_n(rst_n), .in_valid(b_valid),
        .block(block_c), .state_in(IV),
        .out_valid(c_valid), .digest(c_digest)
    );

    // ---- tag delay C ----
    reg [32:0] tagc [0:LAT-1];
    always @(posedge clk) begin
        tagc[0] <= {last_c, nonce_c};
        for (i = 1; i < LAT; i = i + 1) tagc[i] <= tagc[i-1];
    end
    wire [31:0] nonce_r = tagc[LAT-1][31:0];
    wire        last_r  = tagc[LAT-1][32];

    // ---- target compare (Bitcoin rule, same as sha256d_search) ----
    function [255:0] byterev;
        input [255:0] x;
        integer j;
        begin
            for (j = 0; j < 32; j = j + 1)
                byterev[8*j +: 8] = x[255 - 8*j -: 8];
        end
    endfunction
    wire hit = c_valid && (byterev(c_digest) < tgt);

    // ---- control ----
    localparam S_IDLE = 1'b0, S_RUN = 1'b1;
    reg state;

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            busy        <= 1'b0;
            done        <= 1'b0;
            found       <= 1'b0;
            feeding     <= 1'b0;
            hashes_done <= 32'd0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        tmpl        <= header_template;
                        tgt         <= target;
                        limit_r     <= nonce_limit;
                        nonce       <= nonce_start;
                        hashes_done <= 32'd0;
                        found       <= 1'b0;
                        feeding     <= 1'b1;
                        busy        <= 1'b1;
                        state       <= S_RUN;
                    end
                end
                S_RUN: begin
                    // Feeder: one nonce per clock until the limit is fed.
                    if (feeding) begin
                        if (nonce == limit_r)
                            feeding <= 1'b0;
                        else
                            nonce <= nonce + 32'd1;
                    end
                    // Result stream: in order, one per clock at full rate.
                    if (c_valid)
                        hashes_done <= hashes_done + 32'd1;
                    if (hit) begin
                        found      <= 1'b1;
                        nonce_out  <= nonce_r;
                        digest_out <= c_digest;
                        feeding    <= 1'b0;
                        busy       <= 1'b0;
                        done       <= 1'b1;
                        state      <= S_IDLE;
                    end else if (c_valid && last_r) begin
                        found <= 1'b0;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
