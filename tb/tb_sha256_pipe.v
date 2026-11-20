// tb_sha256_pipe.v — testbench for sha256_pipe (pipelined SHA-256).
// _muse — written 2026-11-20.
// Tests:
//  (A) Three different single-block messages fed on three CONSECUTIVE
//      clocks must emerge in order on three consecutive clocks:
//      "abc", the empty message, and a 55-byte sequence block whose
//      expected digest was computed with Python hashlib.
//  (B) The 56-byte NIST message (two-block chaining): block 1's digest
//      is captured from the pipe output and fed back as block 2's
//      state, as a caller would; the final digest must be 248d6a61...
//  (C) A burst of 16 identical blocks back-to-back: 16 identical
//      digests, no cross-talk between pipeline slots.
// Also measures the pipeline latency in clocks.
`timescale 1ns/1ps
`default_nettype none
module tb_sha256_pipe;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         in_valid = 1'b0;
    reg [511:0] block;
    reg [255:0] state_in;
    wire        out_valid;
    wire [255:0] digest;

    integer errors = 0;
    integer tests  = 0;
    integer out_ptr = 0;
    reg [255:0] expected [0:63];
    reg         check_en [0:63];
    reg [255:0] got [0:63];
    integer exp_count = 0;
    integer cycle = 0;
    integer first_in_cycle = -1;
    integer first_out_cycle = -1;

    sha256_pipe dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .block(block), .state_in(state_in),
        .out_valid(out_valid), .digest(digest)
    );

    always #5 clk = ~clk;
    always @(posedge clk) cycle = cycle + 1;

    localparam [255:0] IV = {32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
                             32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19};
    localparam [255:0] ABC_DIGEST =
        {32'hba7816bf, 32'h8f01cfea, 32'h414140de, 32'h5dae2223,
         32'hb00361a3, 32'h96177a9c, 32'hb410ff61, 32'hf20015ad};
    localparam [255:0] EMPTY_DIGEST =
        {32'he3b0c442, 32'h98fc1c14, 32'h9afbf4c8, 32'h996fb924,
         32'h27ae41e4, 32'h649b934c, 32'ha495991b, 32'h7852b855};
    localparam [255:0] SEQ_DIGEST = 256'he87b25305254cd03a1ab3d2ce92986a903c4fbc0c76db2e52a26f88b0a97ce10;
    localparam [255:0] NIST_DIGEST =
        {32'h248d6a61, 32'hd20638b8, 32'he5c02693, 32'h0c3e6039,
         32'ha33ce459, 32'h64ff2167, 32'hf6ecedd4, 32'h19db06c1};

    reg [511:0] blk_abc, blk_empty, blk_seq, blk_nist1, blk_nist2;

    // Output monitor: records every output; checks those flagged.
    always @(posedge clk) begin
        if (out_valid) begin
            if (first_out_cycle < 0) first_out_cycle = cycle;
            got[out_ptr] = digest;
            if (out_ptr < exp_count && check_en[out_ptr]) begin
                tests = tests + 1;
                if (digest !== expected[out_ptr]) begin
                    errors = errors + 1;
                    $display("FAIL output #%0d  got %064x  expected %064x",
                             out_ptr, digest, expected[out_ptr]);
                end else begin
                    $display("PASS output #%0d  %064x", out_ptr, digest);
                end
            end
            out_ptr = out_ptr + 1;
        end
    end

    // Feed one block on the next clock edge. exp_digest is only checked
    // when do_check is 1.
    task feed;
        input [511:0] blk;
        input [255:0] st;
        input [255:0] exp_digest;
        input         do_check;
        begin
            expected[exp_count] = exp_digest;
            check_en[exp_count] = do_check;
            exp_count = exp_count + 1;
            if (first_in_cycle < 0) first_in_cycle = cycle;
            @(negedge clk); block = blk; state_in = st; in_valid = 1'b1;
        end
    endtask

    task idle;
        begin
            @(negedge clk); in_valid = 1'b0;
        end
    endtask

    integer i;
    initial begin
        // ---- build the blocks (same constructions as tb_sha256_core) ----
        blk_abc = 512'b0;
        blk_abc[511:480] = 32'h61626380;
        blk_abc[31:0]    = 32'h00000018;
        blk_empty = 512'b0;
        blk_empty[511:480] = 32'h80000000;
        blk_seq = 512'h0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f30313233343536378000000000000001b8;
        blk_nist1 = 512'b0;
        blk_nist1[511:480] = 32'h61626364; blk_nist1[479:448] = 32'h62636465;
        blk_nist1[447:416] = 32'h63646566; blk_nist1[415:384] = 32'h64656667;
        blk_nist1[383:352] = 32'h65666768; blk_nist1[351:320] = 32'h66676869;
        blk_nist1[319:288] = 32'h6768696a; blk_nist1[287:256] = 32'h68696a6b;
        blk_nist1[255:224] = 32'h696a6b6c; blk_nist1[223:192] = 32'h6a6b6c6d;
        blk_nist1[191:160] = 32'h6b6c6d6e; blk_nist1[159:128] = 32'h6c6d6e6f;
        blk_nist1[127:96]  = 32'h6d6e6f70; blk_nist1[95:64]   = 32'h6e6f7071;
        blk_nist1[63:32]   = 32'h80000000; blk_nist1[31:0]    = 32'h00000000;
        blk_nist2 = 512'b0;
        blk_nist2[31:0]    = 32'h000001c0;

        // ---- reset ----
        repeat (4) @(negedge clk);
        rst_n = 1'b1;

        // ---- (A) three blocks, three consecutive clocks ----
        feed(blk_abc, IV, ABC_DIGEST, 1'b1);
        feed(blk_empty, IV, EMPTY_DIGEST, 1'b1);
        feed(blk_seq, IV, SEQ_DIGEST, 1'b1);
        idle;
        wait (out_ptr == 3);
        @(negedge clk);
        $display("LATENCY first-in to first-out: %0d clocks",
                 first_out_cycle - first_in_cycle);

        // ---- (B) NIST two-block chaining ----
        feed(blk_nist1, IV, 256'b0, 1'b0);       // record only
        idle;
        wait (out_ptr == 4);
        @(negedge clk);
        feed(blk_nist2, got[3], NIST_DIGEST, 1'b1);
        idle;
        wait (out_ptr == 5);
        @(negedge clk);

        // ---- (C) burst of 16 identical blocks ----
        for (i = 0; i < 16; i = i + 1)
            feed(blk_abc, IV, ABC_DIGEST, 1'b1);
        idle;
        wait (out_ptr == 21);
        @(negedge clk);

        if (errors == 0)
            $display("ALL %0d TESTS PASSED", tests);
        else
            $display("%0d of %0d TESTS FAILED", errors, tests);
        $finish;
    end

    initial begin
        repeat (100000) @(posedge clk);
        $display("TIMEOUT — pipe never produced all outputs");
        $finish;
    end
endmodule
`default_nettype wire
