// sha256d_search.v — nonce search over sha256d_core.
// _muse — written 2026-11-17 for Branden's hand-built mining core project.
//
// Given an 80-byte header template, sweeps nonce = nonce_start..nonce_limit
// (inclusive), writing each nonce little-endian into header bytes 76..79,
// and stops at the first nonce whose double-SHA-256, read as a big-endian
// number in display order, is strictly below `target` — the Bitcoin rule.
// Pulses `done` with `found`, `nonce_out`, `digest_out` (internal byte
// order) and `hashes_done` valid. One core, sequential: a spoon, searching.
`default_nettype none
module sha256d_search (
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
    // ---- sub-core ----
    reg         core_start;
    reg [639:0] core_header;
    wire [255:0] core_digest;
    wire        core_done, core_busy;

    sha256d_core u_search_core (
        .clk(clk), .rst_n(rst_n), .start(core_start), .header(core_header),
        .digest(core_digest), .done(core_done), .busy(core_busy)
    );

    // Byte-reversal: internal digest order -> display order for the
    // target comparison (Bitcoin compares the reversed digest).
    function [255:0] byterev;
        input [255:0] x;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1)
                byterev[8*i +: 8] = x[255 - 8*i -: 8];
        end
    endfunction

    wire [255:0] digest_display = byterev(core_digest);
    wire         hit = digest_display < target;

    // ---- sequencer ----
    localparam S_IDLE = 2'd0, S_ISSUE = 2'd1, S_WAIT = 2'd2, S_FIN = 2'd3;
    reg [1:0]  state;
    reg [31:0] nonce;
    reg [31:0] limit_r;
    reg [639:0] tmpl;

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            busy        <= 1'b0;
            done        <= 1'b0;
            found       <= 1'b0;
            core_start  <= 1'b0;
            hashes_done <= 32'd0;
        end else begin
            done       <= 1'b0;
            core_start <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        tmpl        <= header_template;
                        limit_r     <= nonce_limit;
                        nonce       <= nonce_start;
                        hashes_done <= 32'd0;
                        found       <= 1'b0;
                        busy        <= 1'b1;
                        state       <= S_ISSUE;
                    end
                end
                S_ISSUE: begin
                    core_header <= {tmpl[639:32],
                                    nonce[7:0], nonce[15:8], nonce[23:16], nonce[31:24]};
                    core_start  <= 1'b1;
                    state       <= S_WAIT;
                end
                S_WAIT: begin
                    if (core_done) begin
                        hashes_done <= hashes_done + 32'd1;
                        if (hit) begin
                            found      <= 1'b1;
                            nonce_out  <= nonce;
                            digest_out <= core_digest;
                            state      <= S_FIN;
                        end else if (nonce == limit_r) begin
                            found <= 1'b0;
                            state <= S_FIN;
                        end else begin
                            nonce <= nonce + 32'd1;
                            state <= S_ISSUE;
                        end
                    end
                end
                S_FIN: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
