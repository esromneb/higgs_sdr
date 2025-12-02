#!/usr/bin/env python3
"""
Build-only XSIM compatibility patch: add explicit `= 1'b0` initial values to
internal `reg` declarations that lack one.

Why this is needed (see README.md "XSIM vs Verilator: register reset"
section for the full writeup): this q-engine/piston IP was written and only
ever verified against Verilator, whose 2-state engine implicitly starts
every `reg` at 0. A proper 4-state simulator (XSIM) instead leaves an
unreset `reg` at X until its first write, and if that first write is itself
gated by an expression that reads the (still-X) register -- a common
elastic-pipeline handshake idiom in this IP (see e.g. vector_slice.v's
i0_latched/k15_latched) -- the register can never resolve out of X,
permanently poisoning downstream valid/ready logic. On real silicon this is
a non-issue: synthesis programs each flip-flop's power-on `INIT` bitstream
attribute to 0 absent an explicit initial value, exactly matching
Verilator's assumption; only XSIM's pre-synthesis behavioral semantics are
uniquely pessimistic here. Adding `= 1'b0` (which synthesis tools also
honor as the FF's INIT attribute) reproduces that already-implied power-on
state without changing any reset_n-driven behavior -- including for regs
that already have explicit synchronous reset logic elsewhere in the file
(the added initial value is then simply redundant with, never in conflict
with, that reset).

Deliberately conservative: only rewrites simple `reg [range]? name(,
name)*;` declarations with no existing `=` and no trailing `[..]` unpacked
dimension (memory arrays, e.g. `reg [31:0] vreg [0:15];`, are intentionally
left untouched -- some entries are legitimately never written in a given
test, which is fine as long as they are never read before being written,
matching real-hardware semantics for an uninitialized memory) and that are
not part of a port declaration (module ports are handled, if at all, by
other build-only patches, not this one).
"""
import re
import sys

DECL_RE = re.compile(
    r'^(?P<indent>\s*)reg\s*(?P<signed>signed\s+)?(?P<range>\[[^\]]*\]\s*)?'
    r'(?P<names>[A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)'
    r'\s*;\s*(?P<trailing>//.*)?$'
)


def patch_line(line):
    if '=' in line:
        return line, False
    # Only inspect the code portion (before any trailing "//" comment) for
    # port-keyword exclusion -- a comment merely *mentioning* the English
    # word "input"/"output" (e.g. "// synchronized data input") must not
    # cause a genuine internal reg declaration to be skipped.
    code_part = line.split('//', 1)[0]
    if re.search(r'\b(input|output|inout)\b', code_part):
        return line, False
    m = DECL_RE.match(line)
    if not m:
        return line, False
    names = [n.strip() for n in m.group('names').split(',')]
    # Skip any declaration with a trailing unpacked-array dimension, e.g.
    # "reg [31:0] vreg [0:15];" -- the regex above only matches plain
    # identifiers as names, so a name followed by "[" would already have
    # failed DECL_RE's match; nothing further to check here.
    new_names = ', '.join(f"{n} = 1'b0" for n in names)
    signed = m.group('signed') or ''
    rng = m.group('range') or ''
    trailing = (' ' + m.group('trailing')) if m.group('trailing') else ''
    new_line = f"{m.group('indent')}reg {signed}{rng}{new_names};{trailing}\n"
    return new_line, True


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <input.v> <output_dir>", file=sys.stderr)
        sys.exit(1)
    src_path, out_dir = sys.argv[1], sys.argv[2]
    with open(src_path) as f:
        lines = f.readlines()
    out_lines = []
    n_patched = 0
    for line in lines:
        new_line, patched = patch_line(line)
        out_lines.append(new_line)
        if patched:
            n_patched += 1
    import os
    out_path = os.path.join(out_dir, os.path.basename(src_path))
    with open(out_path, 'w') as f:
        f.writelines(out_lines)
    print(f"{src_path}: patched {n_patched} reg declaration(s) -> {out_path}")


if __name__ == '__main__':
    main()
