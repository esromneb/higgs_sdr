#!/usr/bin/env python3
"""Compare the ring-bus hex item stream captured from a Verilator test
run's stdout against an XSIM run's stdout.

Both simulators print one ring-bus item per line as ``0x<hex>`` (no
zero-padding -- Verilator's HEX_STRING() macro and the SV testbench's
``%0h`` format both produce this), interleaved with other log lines that
are ignored here. Exits non-zero (and prints a diagnostic) on any
mismatch: different item counts, any differing item, or either stream's
own start/end self-check failing (``first==0xdeadbeef``,
``last==0xf``) -- the same two checks tb.cpp itself performs.

Usage: compare_ringbus.py <verilator_log> <xsim_log>
"""
import re
import sys

HEX_RE = re.compile(r'^0x([0-9a-fA-F]+)$')


def extract_items(path):
    items = []
    with open(path) as f:
        for line in f:
            m = HEX_RE.match(line.strip())
            if m:
                items.append(int(m.group(1), 16))
    return items


def check_self(name, items):
    ok = True
    if not items:
        print(f"FAIL: {name}: no ring-bus items captured")
        return False
    if items[0] != 0xdeadbeef:
        print(f"FAIL: {name}: first item 0x{items[0]:x} != 0xdeadbeef")
        ok = False
    if items[-1] != 0xf:
        print(f"FAIL: {name}: last item 0x{items[-1]:x} != 0xf")
        ok = False
    return ok


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <verilator_log> <xsim_log>")
        return 2

    ver_items = extract_items(sys.argv[1])
    xsim_items = extract_items(sys.argv[2])

    print(f"Verilator: {len(ver_items)} items: "
          f"[{', '.join('0x%x' % i for i in ver_items)}]")
    print(f"XSIM:      {len(xsim_items)} items: "
          f"[{', '.join('0x%x' % i for i in xsim_items)}]")

    ok = check_self("Verilator", ver_items)
    ok = check_self("XSIM", xsim_items) and ok

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
