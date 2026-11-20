// synth_pipe_top.v — synthesis/P&R measurement harness for a single
// sha256_pipe compression core. _muse — written 2026-11-20.
//
// Same instrument pattern as synth_top: serial-load the wide inputs
// (512-bit block + 256-bit state = 768 bits), pulse `go` to present
// them with in_valid for one clock, and fold the digest into an 8-bit
// signature. Lets one pipeline be measured on its own — the number
// that matters for the TinyTapeout tile-fit question.
`default_nettype none
module synth_pipe_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ser_in,     // serial parameter data, MSB first
    input  wire       shift,      // pulse: shift ser_in into the register
    input  wire       go,         // pulse: present block+state for one clock
    output wire       out_valid,
    output wire [7:0] sig         // folded signature of the digest
);
    reg [767:0] params;
    always @(posedge clk) begin
        if (shift) params <= {params[766:0], ser_in};
    end

    wire [255:0] digest;

    sha256_pipe u_pipe (
        .clk(clk), .rst_n(rst_n), .in_valid(go),
        .block(params[767:256]), .state_in(params[255:0]),
        .out_valid(out_valid), .digest(digest)
    );

    assign sig = digest[255:248] ^ digest[247:240] ^ digest[239:232]
               ^ digest[231:224] ^ digest[223:216] ^ digest[215:208]
               ^ digest[207:200] ^ digest[199:192] ^ digest[191:184]
               ^ digest[183:176] ^ digest[175:168] ^ digest[167:160]
               ^ digest[159:152] ^ digest[151:144] ^ digest[143:136]
               ^ digest[135:128] ^ digest[127:120] ^ digest[119:112]
               ^ digest[111:104] ^ digest[103:96]  ^ digest[95:88]
               ^ digest[87:80]   ^ digest[79:72]   ^ digest[71:64]
               ^ digest[63:56]   ^ digest[55:48]   ^ digest[47:40]
               ^ digest[39:32]   ^ digest[31:24]   ^ digest[23:16]
               ^ digest[15:8]    ^ digest[7:0];
endmodule
`default_nettype wire
