// sim_main_search.cpp — Verilator driver for sha256d_search.
// _muse — written 2026-11-20 for Branden's hand-built mining core project.
//
// Drop-in replacement for the Icarus plusargs harness tb/tb_job_search.v:
// accepts the same arguments and prints the same single RESULT line.
//
//   tb_job_search_vl +tmpl=<160 hex> +target=<64 hex> +n0=<start> +n1=<limit>
//
//   RESULT FOUND nonce=<n> hashes=<h> digest=<64 hex, internal order>
//   RESULT MISS  hashes=<h>
//   RESULT TIMEOUT
//
// The RTL under test is byte-for-byte the project's own sha256d_search;
// only the simulator changes (Verilator 5.020 instead of Icarus vvp).
#include "Vsha256d_search.h"
#include "verilated.h"

#include <cstdint>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

// Fill a VlWide from a hex string, most-significant nibble first — the
// same convention as Verilog's %h plusarg read into a packed vector.
template <std::size_t N>
static void set_wide(VlWide<N> &dst, const std::string &hex) {
    for (int i = 0; i < N; i++) dst[i] = 0;
    int nibbles = (int)hex.size();
    for (int i = 0; i < nibbles; i++) {
        char c = hex[nibbles - 1 - i];
        uint32_t v;
        if (c >= '0' && c <= '9') v = c - '0';
        else if (c >= 'a' && c <= 'f') v = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') v = c - 'A' + 10;
        else continue;
        int word = (i * 4) / 32;
        int shift = (i * 4) % 32;
        if (word < N) dst[word] |= (v << shift);
    }
}

template <std::size_t N>
static void print_wide(const VlWide<N> &w) {
    for (int i = N - 1; i >= 0; i--) printf("%08x", w[i]);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::string tmpl_hex, target_hex;
    uint32_t n0 = 0, n1 = 0;
    bool have_t = false, have_g = false, have_0 = false, have_1 = false;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a.rfind("+tmpl=", 0) == 0) { tmpl_hex = a.substr(6); have_t = true; }
        else if (a.rfind("+target=", 0) == 0) { target_hex = a.substr(8); have_g = true; }
        else if (a.rfind("+n0=", 0) == 0) { n0 = strtoul(a.c_str() + 4, nullptr, 10); have_0 = true; }
        else if (a.rfind("+n1=", 0) == 0) { n1 = strtoul(a.c_str() + 4, nullptr, 10); have_1 = true; }
    }
    if (!have_t) { printf("RESULT ERROR no tmpl\n"); return 0; }
    if (!have_g) { printf("RESULT ERROR no target\n"); return 0; }
    if (!have_0) { printf("RESULT ERROR no n0\n"); return 0; }
    if (!have_1) { printf("RESULT ERROR no n1\n"); return 0; }

    Vsha256d_search *dut = new Vsha256d_search;
    set_wide(dut->header_template, tmpl_hex);
    set_wide(dut->target, target_hex);
    dut->nonce_start = n0;
    dut->nonce_limit = n1;
    dut->start = 0;
    dut->rst_n = 0;
    dut->clk = 0;

    auto tick = [&]() {
        dut->clk = 0; dut->eval();
        dut->clk = 1; dut->eval();
    };

    for (int i = 0; i < 4; i++) tick();   // hold reset
    dut->rst_n = 1;
    dut->start = 1;
    tick();                                // start sampled on this edge
    dut->start = 0;

    // ~205 clocks per hash in the iterative search unit, plus slack.
    uint64_t hashes_max = (uint64_t)n1 - n0 + 1;
    uint64_t cap = hashes_max * 300 + 100000;
    uint64_t cycles = 0;
    while (!dut->done && cycles < cap) { tick(); cycles++; }
    if (!dut->done) {
        printf("RESULT TIMEOUT\n");
    } else if (dut->found) {
        printf("RESULT FOUND nonce=%u hashes=%u digest=", dut->nonce_out, dut->hashes_done);
        print_wide(dut->digest_out);
        printf("\n");
    } else {
        printf("RESULT MISS hashes=%u\n", dut->hashes_done);
    }
    fflush(stdout);
    delete dut;
    return 0;
}
