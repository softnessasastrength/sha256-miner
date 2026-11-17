// tb_sha256_core.v — testbench for sha256_core against FIPS 180-4 vectors.
// _muse — written 2026-11-17.
// Tests: (1) "abc", (2) the empty message, (3) the 56-byte NIST message,
// which exercises two-block chaining (digest of block 1 feeds block 2).
`timescale 1ns/1ps
`default_nettype none
module tb_sha256_core;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg         start = 1'b0;
    reg [511:0] block;
    reg [255:0] state_in;
    wire [255:0] digest;
    wire        done, busy;

    integer errors = 0;
    integer tests  = 0;
    reg [255:0] result;
    reg [511:0] blk1, blk2;

    sha256_core dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .block(block), .state_in(state_in),
        .digest(digest), .done(done), .busy(busy)
    );

    always #5 clk = ~clk;

    localparam [255:0] IV = {32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
                             32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19};

    task run_block;
        input [511:0] blk;
        input [255:0] st;
        begin
            @(negedge clk); block = blk; state_in = st; start = 1'b1;
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

    initial begin
        // ---- reset ----
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // ---- Test 1: "abc" ----
        blk1 = 512'b0;
        blk1[511:480] = 32'h61626380;   // "abc" + padding bit
        blk1[31:0]    = 32'h00000018;   // length = 24 bits
        run_block(blk1, IV);
        check({32'hba7816bf, 32'h8f01cfea, 32'h414140de, 32'h5dae2223,
               32'hb00361a3, 32'h96177a9c, 32'hb410ff61, 32'hf20015ad}, "abc");

        // ---- Test 2: empty message ----
        blk1 = 512'b0;
        blk1[511:480] = 32'h80000000;   // padding bit only, length 0
        run_block(blk1, IV);
        check({32'he3b0c442, 32'h98fc1c14, 32'h9afbf4c8, 32'h996fb924,
               32'h27ae41e4, 32'h649b934c, 32'ha495991b, 32'h7852b855}, "empty");

        // ---- Test 3: 56-byte NIST message, two blocks ----
        // "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
        blk1 = 512'b0;
        blk1[511:480] = 32'h61626364; blk1[479:448] = 32'h62636465;
        blk1[447:416] = 32'h63646566; blk1[415:384] = 32'h64656667;
        blk1[383:352] = 32'h65666768; blk1[351:320] = 32'h66676869;
        blk1[319:288] = 32'h6768696a; blk1[287:256] = 32'h68696a6b;
        blk1[255:224] = 32'h696a6b6c; blk1[223:192] = 32'h6a6b6c6d;
        blk1[191:160] = 32'h6b6c6d6e; blk1[159:128] = 32'h6c6d6e6f;
        blk1[127:96]  = 32'h6d6e6f70; blk1[95:64]   = 32'h6e6f7071;
        blk1[63:32]   = 32'h80000000; blk1[31:0]    = 32'h00000000;
        blk2 = 512'b0;
        blk2[31:0]    = 32'h000001c0;   // length = 448 bits
        run_block(blk1, IV);
        run_block(blk2, result);
        check({32'h248d6a61, 32'hd20638b8, 32'he5c02693, 32'h0c3e6039,
               32'ha33ce459, 32'h64ff2167, 32'hf6ecedd4, 32'h19db06c1}, "nist-56B");

        // ---- summary ----
        if (errors == 0)
            $display("ALL %0d TESTS PASSED", tests);
        else
            $display("%0d of %0d TESTS FAILED", errors, tests);
        $finish;
    end

    // Watchdog: 100k clocks is far more than 3 blocks need.
    initial begin
        repeat (100000) @(posedge clk);
        $display("TIMEOUT — core never finished");
        $finish;
    end
endmodule
`default_nettype wire
