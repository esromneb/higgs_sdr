#!/usr/bin/env python3
import sys

PASS_STRING = "All Tests Passed"


def read_samples(path):
    with open(path) as handle:
        return [int(line.strip(), 16) for line in handle if line.strip()]


def has_pass(path):
    with open(path) as handle:
        return PASS_STRING in handle.read()


def main():
    if len(sys.argv) != 5:
        print(
            "usage: compare_nco.py "
            "<verilator-log> <verilator-samples> <xsim-log> <xsim-samples>"
        )
        return 2

    ver_log, ver_samples_path, xsim_log, xsim_samples_path = sys.argv[1:]
    ok = True
    for name, path in (("Verilator", ver_log), ("XSIM", xsim_log)):
        if not has_pass(path):
            print(f'FAIL: {name}: missing "{PASS_STRING}"')
            ok = False

    ver_samples = read_samples(ver_samples_path)
    xsim_samples = read_samples(xsim_samples_path)
    if ver_samples != xsim_samples:
        mismatch = next(
            (
                index
                for index, pair in enumerate(zip(ver_samples, xsim_samples))
                if pair[0] != pair[1]
            ),
            min(len(ver_samples), len(xsim_samples)),
        )
        print(
            "FAIL: NCO streams differ at sample "
            f"{mismatch} (Verilator count={len(ver_samples)}, "
            f"XSIM count={len(xsim_samples)})"
        )
        ok = False

    if ok:
        print(
            f"PASS: {len(ver_samples)} NCO samples match exactly "
            "and both simulator self-checks passed"
        )
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
