// tb_sha256d_core.v — testbench for sha256d_core.
// _muse — written 2026-11-17.
// Test 1 is the witness that matters: the genesis block header must
// reproduce Satoshi's block hash. Test 2 is a synthetic header whose
// expected digest was computed with a reference implementation.
`timescale 1ns/1ps
`default_nettype none
module tb_sha256d_core;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         start = 1'b0;
    reg [639:0] header;
    wire [255:0] digest;
    wire        done, busy;

    integer errors = 0;
    integer tests  = 0;
    reg [255:0] result;

    sha256d_core dut (
        .clk(clk), .rst_n(rst_n), .start(start), .header(header),
        .digest(digest), .done(done), .busy(busy)
    );

    always #5 clk = ~clk;

    task run_header;
        input [639:0] hdr;
        begin
            @(negedge clk); header = hdr; start = 1'b1;
            @(negedge clk); start = 1'b0;
            wait (done == 1'b1);
            result = digest;
            @(negedge clk);
        end
    endtask

    task check;
        input [255:0] expected;
        input [255:0] label;
        begin
            tests = tests + 1;
            if (result !== expected) begin
                errors = errors + 1;
                $display("FAIL %0s", label);
                $display("  got      %064x", result);
                $display("  expected %064x", expected);
            end else begin
                $display("PASS %0s  %064x", label, result);
            end
        end
    endtask

    // Genesis header, raw wire bytes:
    //   version 01000000, prevhash 0x00..., merkle 3ba3edfd...4b1e5e4a,
    //   time 29ab5f49, bits ffff001d, nonce 1dac2b7c.
    localparam [639:0] GENESIS_HDR =
        640'h0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c;
    // Expected double-SHA-256, internal byte order (display form is the
    // byte-reversal: 000000000019d668...b60a8ce26f).
    localparam [255:0] GENESIS_DIGEST =
        256'h6fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000;

    localparam [639:0] VECTOR2_HDR =
        640'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f;
    localparam [255:0] VECTOR2_DIGEST =
        256'h852c98044fb00507122ff63bda7b529566348fc204f72b00dff1afd7b40501e4;

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        run_header(GENESIS_HDR);
        check(GENESIS_DIGEST, "genesis-block");

        run_header(VECTOR2_HDR);
        check(VECTOR2_DIGEST, "synthetic-header");

        if (errors == 0)
            $display("ALL %0d TESTS PASSED", tests);
        else
            $display("%0d of %0d TESTS FAILED", errors, tests);
        $finish;
    end

    initial begin
        repeat (200000) @(posedge clk);
        $display("TIMEOUT — wrapper never finished");
        $finish;
    end
endmodule
`default_nettype wire
