// sha256d_core.v — double-SHA-256 of an 80-byte Bitcoin block header.
// _muse — written 2026-11-17 for Branden's hand-built mining core project.
//
// Wraps one sha256_core and runs it three times:
//   phase 0: SHA-256 block 1 of the header (bytes 0..63),  state = IV
//   phase 1: SHA-256 block 2 (bytes 64..79 + padding),    state = phase 0 result
//   phase 2: SHA-256 of the 32-byte first digest (+ pad), state = IV
// `header` is the raw 80 bytes in wire order: header[639:632] is byte 0.
// `digest` is the double-SHA-256 in internal byte order (digest[255:248]
// is byte 0); reverse it for the familiar display form of a block hash.
`default_nettype none
module sha256d_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [639:0] header,
    output reg  [255:0] digest,
    output reg          done,
    output reg          busy
);
    localparam [255:0] IV = {32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
                             32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19};

    // ---- sub-core ----
    reg         core_start;
    reg [511:0] core_block;
    reg [255:0] core_state;
    wire [255:0] core_digest;
    wire        core_done, core_busy;

    sha256_core u_core (
        .clk(clk), .rst_n(rst_n), .start(core_start),
        .block(core_block), .state_in(core_state),
        .digest(core_digest), .done(core_done), .busy(core_busy)
    );

    // ---- sequencer ----
    localparam S_IDLE = 2'd0, S_ISSUE = 2'd1, S_WAIT = 2'd2, S_FIN = 2'd3;
    reg [1:0]   state;
    reg [1:0]   phase;
    reg [255:0] d1;        // chaining value / first-pass digest
    reg [639:0] hdr;       // latched header

    always @(*) begin
        case (phase)
            2'd0: begin
                core_block = hdr[639:128];
                core_state = IV;
            end
            2'd1: begin
                core_block = {hdr[127:0], 8'h80, 312'b0, 64'd640};
                core_state = d1;
            end
            default: begin
                core_block = {d1, 8'h80, 184'b0, 64'd256};
                core_state = IV;
            end
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            phase      <= 2'd0;
            busy       <= 1'b0;
            done       <= 1'b0;
            core_start <= 1'b0;
        end else begin
            done       <= 1'b0;
            core_start <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        hdr   <= header;
                        phase <= 2'd0;
                        busy  <= 1'b1;
                        state <= S_ISSUE;
                    end
                end
                S_ISSUE: begin
                    core_start <= 1'b1;
                    state      <= S_WAIT;
                end
                S_WAIT: begin
                    if (core_done) begin
                        d1 <= core_digest;
                        if (phase == 2'd2) begin
                            digest <= core_digest;
                            state  <= S_FIN;
                        end else begin
                            phase <= phase + 2'd1;
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
