// sim_main_pipe_search.cpp — Verilator driver for sha256d_pipe_search.
// _muse — written 2026-11-20.
//
// Same +tmpl/+target/+n0/+n1 plusarg interface as sim_main_search.cpp,
// plus throughput reporting: it counts the clocks from start to done
// (the cascade's hashes-per-clock) and the wall-clock time (the
// simulated hashes/sec on this host), and prints both. Build:
//   make obj-pipe-search  (see Makefile)
// Run:
//   ./build/tb_pipe_search_vl +tmpl=<hex> +target=<hex> +n0=<dec> +n1=<dec>
#include "Vsha256d_pipe_search.h"
#include "verilated.h"
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

static int hexval(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return 0;
}

// Parse exactly nwords*8 hex chars (most significant first) into words,
// words[0] = most significant word (matches the Verilog literal order).
static void parse_words(const char* s, uint32_t* words, int nwords) {
    int n = nwords * 8;
    for (int i = 0; i < nwords; i++) words[i] = 0;
    for (int i = 0; i < n; i++) {
        int word = i / 8;              // hex chars 0..7 -> MSW
        int nib = 7 - (i % 8);
        words[word] |= (uint32_t)hexval(s[i]) << (4 * nib);
    }
}

// Verilator wide-vector layout: element [0] holds the LEAST significant
// 32 bits. The Verilog literal is MSW-first, so reverse into the array.
static void load_reversed(VlWide<20>& dst, const uint32_t* words) {
    for (int i = 0; i < 20; i++) dst[i] = words[19 - i];
}
static void load_reversed8(VlWide<8>& dst, const uint32_t* words) {
    for (int i = 0; i < 8; i++) dst[i] = words[7 - i];
}

static void print_digest(const VlWide<8>& d) {
    for (int w = 7; w >= 0; w--) printf("%08x", d[w]);
}

int main(int argc, char** argv) {
    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);

    const char* tmpl_s = nullptr;
    const char* target_s = nullptr;
    uint32_t n0 = 0, n1 = 0;
    for (int i = 1; i < argc; i++) {
        if (strncmp(argv[i], "+tmpl=", 6) == 0) tmpl_s = argv[i] + 6;
        else if (strncmp(argv[i], "+target=", 8) == 0) target_s = argv[i] + 8;
        else if (strncmp(argv[i], "+n0=", 4) == 0) n0 = strtoul(argv[i] + 4, nullptr, 10);
        else if (strncmp(argv[i], "+n1=", 4) == 0) n1 = strtoul(argv[i] + 4, nullptr, 10);
    }
    if (!tmpl_s || !target_s || strlen(tmpl_s) != 160 || strlen(target_s) != 64) {
        fprintf(stderr, "usage: +tmpl=<160 hex> +target=<64 hex> +n0=<dec> +n1=<dec>\n");
        return 2;
    }

    Vsha256d_pipe_search* top = new Vsha256d_pipe_search{ctx};
    uint32_t tmpl_words[20], target_words[8];
    parse_words(tmpl_s, tmpl_words, 20);
    parse_words(target_s, target_words, 8);
    load_reversed(top->header_template, tmpl_words);
    load_reversed8(top->target, target_words);
    top->nonce_start = n0;
    top->nonce_limit = n1;

    auto tick = [&]() {
        top->clk = 0; top->eval();
        top->clk = 1; top->eval();
    };

    top->rst_n = 0; top->start = 0; top->clk = 0;
    for (int i = 0; i < 4; i++) tick();
    top->rst_n = 1;
    tick();
    top->start = 1;
    tick();
    top->start = 0;

    auto t_begin = std::chrono::steady_clock::now();
    uint64_t clocks = 0;
    const uint64_t kMaxClocks = 500000000ull;
    while (!top->done && clocks < kMaxClocks) {
        tick();
        clocks++;
    }
    auto t_end = std::chrono::steady_clock::now();
    double secs = std::chrono::duration<double>(t_end - t_begin).count();

    if (!top->done) {
        printf("RESULT TIMEOUT clocks=%llu\n", (unsigned long long)clocks);
        return 1;
    }
    uint32_t hashes = top->hashes_done;
    printf("CLOCKS %llu\n", (unsigned long long)clocks);
    printf("WALL_SECONDS %.3f\n", secs);
    if (secs > 0)
        printf("SIM_HASHRATE %.0f\n", hashes / secs);
    if (top->found) {
        printf("RESULT FOUND nonce=%u hashes=%u digest=", top->nonce_out, hashes);
        print_digest(top->digest_out);
        printf("\n");
    } else {
        printf("RESULT MISS hashes=%u\n", hashes);
    }
    delete top;
    delete ctx;
    return 0;
}
