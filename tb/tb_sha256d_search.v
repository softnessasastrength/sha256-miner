// tb_sha256d_search.v — testbench for sha256d_search.
// _muse — written 2026-11-17.
// (a) Genesis recovery: starting 500 nonces early, the search must land
//     exactly on Satoshi's nonce, 2083236893.
// (b) Synthetic sweep: first qualifying nonce for a 2^248 target is 434
//     (computed with a reference implementation).
// (c) Exhaustion: an impossible target over a 4-nonce range must report
//     found=0 after exactly 4 hashes.
`timescale 1ns/1ps
`default_nettype none
module tb_sha256d_search;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         start = 1'b0;
    reg [639:0] header_template;
    reg [31:0]  nonce_start, nonce_limit;
    reg [255:0] target;
    wire        found, done, busy;
    wire [31:0] nonce_out, hashes_done;
    wire [255:0] digest_out;

    integer errors = 0;
    integer tests  = 0;

    sha256d_search dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .header_template(header_template),
        .nonce_start(nonce_start), .nonce_limit(nonce_limit), .target(target),
        .found(found), .done(done), .busy(busy),
        .nonce_out(nonce_out), .digest_out(digest_out), .hashes_done(hashes_done)
    );

    always #5 clk = ~clk;

    localparam [639:0] GENESIS_HDR =
        640'h0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c;
    localparam [255:0] GENESIS_TARGET =
        256'h00000000ffff0000000000000000000000000000000000000000000000000000;
    localparam [255:0] GENESIS_DIGEST =
        256'h6fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000;
    localparam [639:0] VECTOR2_HDR =
        640'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f;

    task run_search;
        input [639:0] tmpl;
        input [31:0]  n0, n1;
        input [255:0] tgt;
        begin
            @(negedge clk);
            header_template = tmpl; nonce_start = n0; nonce_limit = n1; target = tgt;
            start = 1'b1;
            @(negedge clk); start = 1'b0;
            wait (done == 1'b1);
            @(negedge clk);
        end
    endtask

    task expect;
        input exp_found;
        input [31:0] exp_nonce;
        input [31:0] exp_hashes;
        input [255:0] label;
        begin
            tests = tests + 1;
            if (found !== exp_found || hashes_done !== exp_hashes ||
                (exp_found && nonce_out !== exp_nonce)) begin
                errors = errors + 1;
                $display("FAIL %0s  found=%b nonce=%0d hashes=%0d (expected found=%b nonce=%0d hashes=%0d)",
                         label, found, nonce_out, hashes_done, exp_found, exp_nonce, exp_hashes);
            end else begin
                $display("PASS %0s  found=%b nonce=%0d hashes=%0d", label, found, nonce_out, hashes_done);
            end
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // (a) genesis recovery
        run_search(GENESIS_HDR, 32'd2083236393, 32'd2083236893, GENESIS_TARGET);
        expect(1'b1, 32'd2083236893, 32'd501, "genesis-nonce-recovery");
        if (digest_out !== GENESIS_DIGEST) begin
            errors = errors + 1;
            $display("FAIL genesis digest  got %064x", digest_out);
        end

        // (b) synthetic sweep, target 2^248
        run_search(VECTOR2_HDR, 32'd0, 32'd100000,
                   256'h0100000000000000000000000000000000000000000000000000000000000000);
        expect(1'b1, 32'd434, 32'd435, "synthetic-sweep");

        // (c) exhaustion, target 0
        run_search(VECTOR2_HDR, 32'd100, 32'd103, 256'b0);
        expect(1'b0, 32'd0, 32'd4, "exhaustion");

        if (errors == 0)
            $display("ALL %0d TESTS PASSED", tests);
        else
            $display("%0d ERRORS ACROSS %0d TESTS", errors, tests);
        $finish;
    end

    initial begin
        repeat (3000000) @(posedge clk);
        $display("TIMEOUT — search never finished");
        $finish;
    end
endmodule
`default_nettype wire
