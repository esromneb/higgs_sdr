#!/usr/bin/env python3
"""Build-only patch: insert an explicit `wire` net type into any bare
`input`/`output`/`inout` port declaration that lacks one, but only in the
portion of the file after its own ``default_nettype none`` directive.

Several legacy .sv files in this repo declare ports like
``input               CLK,`` -- legal, and treated as an implicit `wire`,
by Verilator (and Vivado's synthesizer) even under
``default_nettype none``, but rejected outright by XSIM's `xvlog`
frontend, which enforces the stricter IEEE1800 LRM reading. This script
produces build-only copies with the missing net type added; the
committed source files are never modified. See
sim/verilator/test_fft_lib_1/README.md for the full list of affected
files and rationale.

Usage: xsim_net_type_fix.py <src1> [<src2> ...] <output_dir>
Writes <output_dir>/<basename(src)> for each source file.
"""
import os
import re
import sys

PORT_RE = re.compile(r'^(\s*)(input|output|inout)(\s+)(\S.*)$', re.MULTILINE)
ALREADY_TYPED_RE = re.compile(r'^(wire|reg|logic)\b')


def fix_port_line(m):
    indent, direction, _ws, rest = m.groups()
    if ALREADY_TYPED_RE.match(rest):
        return m.group(0)
    return f"{indent}{direction} wire {rest}"


def patch(path, out_dir):
    text = open(path).read()
    marker = '`default_nettype none'
    idx = text.find(marker)
    assert idx != -1, f"{path}: no `default_nettype none found"
    idx += len(marker)
    head, tail = text[:idx], text[idx:]
    tail = PORT_RE.sub(fix_port_line, tail)
    out_path = os.path.join(out_dir, os.path.basename(path))
    open(out_path, 'w').write(head + tail)


def main():
    if len(sys.argv) < 3:
        print(f"usage: {sys.argv[0]} <src1> [<src2> ...] <output_dir>")
        return 2
    *sources, out_dir = sys.argv[1:]
    os.makedirs(out_dir, exist_ok=True)
    for src in sources:
        patch(src, out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
