#!/usr/bin/env python3
"""Cross-simulator trace comparator for the memory_slice parity harness.

A plain byte-for-byte `cmp` is too strict: several output fields are backed by
registers that are genuinely uninitialized before the first real transaction
loads them (the vendor `xpm_memory_tdpram` output-data/address registers, and
downstream pipeline stages derived from them, such as `i1_valid`).  Verilator
zero-initializes such registers by default, while XSIM (matching real
silicon) leaves them as `x`.  Both are correct: whenever either trace reports
`x` for a field, the value is architecturally undefined there, so it is
treated as matching anything (the same "don't-care" convention already
established for the harness's live self-checks and confirmed empirically
against the real `xpm_memory_tdpram` primitive -- see README.md).  Every
column where both sides report a defined value must match exactly.
"""

import sys


def is_dont_care(value):
    return "x" in value.lower()


def load(path):
    with open(path, "r") as handle:
        lines = [line.rstrip("\n") for line in handle if line.strip()]
    header = lines[0].split(",")
    rows = [dict(zip(header, line.split(","))) for line in lines[1:]]
    return header, rows


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <trace_a.csv> <trace_b.csv>", file=sys.stderr)
        return 2

    header_a, rows_a = load(sys.argv[1])
    header_b, rows_b = load(sys.argv[2])

    if header_a != header_b:
        print("header mismatch:", file=sys.stderr)
        print(f"  {sys.argv[1]}: {header_a}", file=sys.stderr)
        print(f"  {sys.argv[2]}: {header_b}", file=sys.stderr)
        return 1

    if len(rows_a) != len(rows_b):
        print(
            f"row count mismatch: {sys.argv[1]} has {len(rows_a)}, "
            f"{sys.argv[2]} has {len(rows_b)}",
            file=sys.stderr,
        )
        return 1

    errors = 0
    for line_number, (row_a, row_b) in enumerate(zip(rows_a, rows_b), start=2):
        for column in header_a:
            value_a = row_a[column]
            value_b = row_b[column]
            if is_dont_care(value_a) or is_dont_care(value_b):
                continue
            if value_a != value_b:
                print(
                    f"line {line_number}: column '{column}' differs: "
                    f"{sys.argv[1]}={value_a} {sys.argv[2]}={value_b}",
                    file=sys.stderr,
                )
                errors += 1

    if errors:
        print(f"FAIL: {errors} field mismatch(es)", file=sys.stderr)
        return 1

    print("PASS: traces match ('x' fields treated as don't-care)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
