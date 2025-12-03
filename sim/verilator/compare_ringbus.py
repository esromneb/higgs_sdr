#!/usr/bin/env python3
"""Compare the ring-bus hex item stream captured from a Verilator test
run's stdout against an XSIM run's stdout.

Both simulators print one ring-bus item per line as ``0x<hex>`` (no
zero-padding -- Verilator's HEX_STRING() macro and the SV testbench's
``%0h`` format both produce this, and higgs_helper.hpp's zero-padded
``0x%08h`` style also matches via this same regex), interleaved with
other log lines that are ignored here. Exits non-zero (and prints a
diagnostic) on any mismatch: different item counts, any differing item,
or either log missing the "All Tests Passed" line that every test's own
tb.cpp/tb_higgs_top_xsim.sv self-check prints on success (each test
defines its own pass/fail criteria internally -- e.g. exact item count,
specific first/last values -- this script only confirms both simulators
agree with each other AND both independently self-reported success; it
does not hardcode any test-specific expected values).

Usage: compare_ringbus.py <verilator_log> <xsim_log>
"""
import re
import sys

HEX_RE = re.compile(r'^0x([0-9a-fA-F]+)$')
PASS_STRING = "All Tests Passed"


def extract_items(path):
    items = []
    with open(path) as f:
        for line in f:
            m = HEX_RE.match(line.strip())
            if m:
                items.append(int(m.group(1), 16))
    return items


def check_self(name, path):
    with open(path) as f:
        if PASS_STRING in f.read():
            return True
    print(f"FAIL: {name}: missing \"{PASS_STRING}\" (own self-check failed)")
    return False


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <verilator_log> <xsim_log>")
        return 2

    ver_log, xsim_log = sys.argv[1], sys.argv[2]
    ver_items = extract_items(ver_log)
    xsim_items = extract_items(xsim_log)

    print(f"Verilator: {len(ver_items)} items: "
          f"[{', '.join('0x%x' % i for i in ver_items)}]")
    print(f"XSIM:      {len(xsim_items)} items: "
          f"[{', '.join('0x%x' % i for i in xsim_items)}]")

    ok = check_self("Verilator", ver_log)
    ok = check_self("XSIM", xsim_log) and ok

    if ver_items != xsim_items:
        print("FAIL: Verilator and XSIM ring-bus streams differ")
        ok = False

    if ok:
        print("PASS: XSIM matches Verilator exactly "
              "(both passed their own self-check)")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
