// synth_pipe_search_top.v — synthesis/P&R measurement harness for
// sha256d_pipe_search. _muse — written 2026-11-20.
//
// Identical instrument to synth_top (same serial parameter load, same
// signature fold), with the pipelined search unit under test — so the
// iterative and pipelined designs are measured by the same ruler.
`default_nettype none
module synth_pipe_search_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ser_in,     // serial parameter data, MSB first
    input  wire       shift,      // pulse: shift ser_in into the register
    input  wire       go,         // pulse: start the search
    output wire       busy,
    output wire       found,
    output wire       done,
    output wire [7:0] sig         // folded signature of the result
);
    // 640 header + 256 target + 32 nonce_start + 32 nonce_limit = 960 bits
    reg [959:0] params;
    always @(posedge clk) begin
        if (shift) params <= {params[958:0], ser_in};
    end

    wire [31:0]  nonce_out;
    wire [255:0] digest_out;
    wire [31:0]  hashes_done;

    sha256d_pipe_search u_search (
        .clk(clk), .rst_n(rst_n), .start(go),
        .header_template(params[959:320]),
        .nonce_start(params[319:288]),
        .nonce_limit(params[287:256]),
        .target(params[255:0]),
        .found(found), .done(done), .busy(busy),
        .nonce_out(nonce_out), .digest_out(digest_out),
        .hashes_done(hashes_done)
    );

    // XOR-fold every result bit into the signature so nothing is
    // optimised away and the outputs stay observable on 8 pins.
    assign sig = digest_out[255:248] ^ digest_out[247:240] ^ digest_out[239:232]
               ^ digest_out[231:224] ^ digest_out[223:216] ^ digest_out[215:208]
               ^ digest_out[207:200] ^ digest_out[199:192] ^ digest_out[191:184]
               ^ digest_out[183:176] ^ digest_out[175:168] ^ digest_out[167:160]
               ^ digest_out[159:152] ^ digest_out[151:144] ^ digest_out[143:136]
               ^ digest_out[135:128] ^ digest_out[127:120] ^ digest_out[119:112]
               ^ digest_out[111:104] ^ digest_out[103:96]  ^ digest_out[95:88]
               ^ digest_out[87:80]   ^ digest_out[79:72]   ^ digest_out[71:64]
               ^ digest_out[63:56]   ^ digest_out[55:48]   ^ digest_out[47:40]
               ^ digest_out[39:32]   ^ digest_out[31:24]   ^ digest_out[23:16]
               ^ digest_out[15:8]    ^ digest_out[7:0]
               ^ nonce_out[31:24]    ^ nonce_out[23:16]    ^ nonce_out[15:8]
               ^ nonce_out[7:0]      ^ hashes_done[31:24]  ^ hashes_done[23:16]
               ^ hashes_done[15:8]   ^ hashes_done[7:0];
endmodule
`default_nettype wire
