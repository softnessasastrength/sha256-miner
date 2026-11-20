/*
 * SPOON-1 — hand-built SHA-256 mining core (iterative design) wrapped
 * for the TinyTapeout sky130 template.
 *
 * Copyright (c) 2026 Branden Algozino
 * SPDX-License-Identifier: Apache-2.0
 *
 * The mining core has ~1,300 signals of interface (640-bit header,
 * 256-bit target, 256-bit digest); the TT pin budget is 24. So the
 * wrapper serialises: job parameters shift in one bit per clock over
 * ui_in[0] (960 clocks), `go` starts the nonce search, and the result
 * is folded into an 8-bit signature on uo_out with busy/found/done on
 * the bidirectional pins. This is the same serial harness the project
 * uses for FPGA place-and-route measurement (rtl/synth_top.v), mapped
 * onto the tt_um_ pinout — it is a measurement/demonstration wrapper,
 * not a production mining interface.
 */

`default_nettype none

module tt_um_spoon_sha256 (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  wire ser_in = ui_in[0];
  wire shift  = ui_in[1];
  wire go     = ui_in[2];

  // 640 header + 32 nonce_start + 32 nonce_limit + 256 target = 960 bits
  reg [959:0] params;
  always @(posedge clk) begin
    if (shift) params <= {params[958:0], ser_in};
  end

  wire        busy, found, done;
  wire [31:0] nonce_out;
  wire [255:0] digest_out;
  wire [31:0] hashes_done;

  sha256d_search u_search (
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
  // optimised away and the outcome stays observable on 8 pins.
  wire [7:0] sig = digest_out[255:248] ^ digest_out[247:240] ^ digest_out[239:232]
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

  assign uo_out  = sig;
  assign uio_out = {5'b0, busy, found, done};
  assign uio_oe  = 8'b0000_0111;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, ui_in[7:3], uio_in, 1'b0};

endmodule
