// tb_sha256d_pipe_search.v — testbench for sha256d_pipe_search.
// _muse — written 2026-11-20.
// Same three correctness tests as tb_sha256d_search (the iterative
// unit), same expected answers:
//  (a) Genesis recovery: nonce 2083236893, exactly 501 hashes.
//  (b) Synthetic sweep: first qualifying nonce 434, 435 hashes.
//  (c) Exhaustion: found=0 after exactly 4 hashes.
// Plus (d) a throughput measurement: 100,000 nonces against an
// impossible target, counting clocks from start to done — the ratio
// is the simulated hashes-per-clock of the cascade.
`timescale 1ns/1ps
`default_nettype none
module tb_sha256d_pipe_search;
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
    integer cycle = 0;
    integer start_cycle = 0;

    sha256d_pipe_search dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .header_template(header_template),
        .nonce_start(nonce_start), .nonce_limit(nonce_limit), .target(target),
        .found(found), .done(done), .busy(busy),
        .nonce_out(nonce_out), .digest_out(digest_out), .hashes_done(hashes_done)
    );

    always #5 clk = ~clk;
    always @(posedge clk) cycle = cycle + 1;

    localparam [639:0] GENESIS_HDR =
        640'h0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c;
    localparam [255:0] GENESIS_TARGET =
        256'h00000000ffff0000000000000000000000000000000000000000000000000000;
    localparam [255:0] GENESIS_DIGEST =
        256'h6fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000;
    localparam [639:0] VECTOR2_HDR =
        640'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f;

    task do_reset;
        begin
            rst_n = 1'b0;
            repeat (4) @(negedge clk);
            rst_n = 1'b1;
            @(negedge clk);
        end
    endtask

    task run_search;
        input [639:0] tmpl;
        input [31:0]  n0, n1;
        input [255:0] tgt;
        begin
            @(negedge clk);
            header_template = tmpl; nonce_start = n0; nonce_limit = n1; target = tgt;
            start = 1'b1;
            @(negedge clk); start = 1'b0;
            start_cycle = cycle;
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

    integer elapsed;
    initial begin
        do_reset;

        // (a) genesis recovery
        run_search(GENESIS_HDR, 32'd2083236393, 32'd2083236893, GENESIS_TARGET);
        expect(1'b1, 32'd2083236893, 32'd501, "genesis-nonce-recovery");
        if (digest_out !== GENESIS_DIGEST) begin
            errors = errors + 1;
            $display("FAIL genesis digest  got %064x", digest_out);
        end
        do_reset;

        // (b) synthetic sweep, target 2^248
        run_search(VECTOR2_HDR, 32'd0, 32'd100000,
                   256'h0100000000000000000000000000000000000000000000000000000000000000);
        expect(1'b1, 32'd434, 32'd435, "synthetic-sweep");
        do_reset;

        // (c) exhaustion, target 0
        run_search(VECTOR2_HDR, 32'd100, 32'd103, 256'b0);
        expect(1'b0, 32'd0, 32'd4, "exhaustion");
        do_reset;

        // (d) throughput: 100,000 nonces, impossible target.
        // Gated behind +thru: Icarus is slow on this design; the
        // throughput measurement is taken under Verilator instead
        // (host/sim_main_pipe_search.cpp). Run with +thru to include.
        if ($test$plusargs("thru")) begin
        run_search(VECTOR2_HDR, 32'd0, 32'd99999, 256'b0);
        elapsed = cycle - start_cycle;
        tests = tests + 1;
        if (found !== 1'b0 || hashes_done !== 32'd100000) begin
            errors = errors + 1;
            $display("FAIL throughput-run  found=%b hashes=%0d", found, hashes_done);
        end else begin
            $display("PASS throughput-run  hashes=%0d clocks=%0d  hashes-per-clock=%0d.%04d",
                     hashes_done, elapsed,
                     hashes_done / elapsed,
                     (hashes_done % elapsed) * 10000 / elapsed);
        end
        end

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
