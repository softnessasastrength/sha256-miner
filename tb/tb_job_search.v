// tb_job_search.v — plusargs-driven search harness for the stratum client.
// _muse — written 2026-11-17.
//
// The host client compiles this once, then runs one vvp invocation per
// work chunk:
//   vvp build/tb_job_search.vvp +tmpl=<160 hex> +target=<64 hex> \
//       +n0=<start> +n1=<limit>
// Prints exactly one result line:
//   RESULT FOUND nonce=<n> hashes=<h> digest=<64 hex, internal order>
//   RESULT MISS  hashes=<h>
//   RESULT TIMEOUT
`timescale 1ns/1ps
`default_nettype none
module tb_job_search;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         start = 1'b0;
    reg [639:0] tmpl;
    reg [255:0] target;
    reg [31:0]  n0, n1;
    wire        found, done, busy;
    wire [31:0] nonce_out, hashes_done;
    wire [255:0] digest_out;

    sha256d_search dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .header_template(tmpl), .nonce_start(n0), .nonce_limit(n1),
        .target(target), .found(found), .done(done), .busy(busy),
        .nonce_out(nonce_out), .digest_out(digest_out), .hashes_done(hashes_done)
    );

    always #5 clk = ~clk;

    initial begin
        if (!$value$plusargs("tmpl=%h", tmpl))   begin $display("RESULT ERROR no tmpl");   $finish; end
        if (!$value$plusargs("target=%h", target)) begin $display("RESULT ERROR no target"); $finish; end
        if (!$value$plusargs("n0=%d", n0))       begin $display("RESULT ERROR no n0");     $finish; end
        if (!$value$plusargs("n1=%d", n1))       begin $display("RESULT ERROR no n1");     $finish; end
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk); start = 1'b1;
        @(negedge clk); start = 1'b0;
        wait (done == 1'b1);
        if (found)
            $display("RESULT FOUND nonce=%0d hashes=%0d digest=%064x", nonce_out, hashes_done, digest_out);
        else
            $display("RESULT MISS hashes=%0d", hashes_done);
        $finish;
    end

    initial begin
        // Generous watchdog: ~300 cycles per hash plus slack.
        repeat (200000000) @(posedge clk);
        $display("RESULT TIMEOUT");
        $finish;
    end
endmodule
`default_nettype wire
