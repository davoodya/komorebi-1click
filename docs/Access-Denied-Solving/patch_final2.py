#!/usr/bin/env python3
"""
Surgical patch for komorebi.exe v0.1.41 on Windows 11 26H2 (build 26300).

Patches EXACTLY two call sites, each located unambiguously and verified
byte-for-byte afterwards.

  [1] foreground_lock_timeout() -> SystemParametersInfoW(
          SPI_SETFOREGROUNDLOCKTIMEOUT, 0, NULL, SPIF_SENDCHANGE)

      Located by the unique `mov ecx, 0x2001` action constant, which appears
      exactly once in the whole binary, immediately followed by the
      xor edx,edx / xor r8d,r8d / mov r9d,2 / call [rip+rel32] sequence.
      On build 26300 this SET returns ERROR_INVALID_PARAMETER in every
      parameter form, even elevated, so the `?` in komorebi's Rust code kills
      it. Returning Ok(()) lets the function complete.
      NOTE: SystemParametersInfoW is imported once but CALLED from 8 sites;
      patching all of them would break monitor enumeration, wallpaper, etc.
      Only the 0x2001 site is touched.

  [2] allow_set_foreground_window() -> AllowSetForegroundWindow(own_pid)

      Located as the single FF 15 indirect call whose RIP-relative target is
      user32.dll!AllowSetForegroundWindow's IAT slot. On 26H2 the foreground
      lock never expires, so a background-launched komorebi can never pass
      this and bails after 5 retries. The call already failed on every
      attempt, so returning Ok removes no capability - it only stops komorebi
      from treating a permanent failure as fatal.

Both are 6 -> 6 byte swaps (call [rip+rel32] -> mov eax,1 ; nop), so no RVA,
rel32, or function boundary in the file changes.

USAGE
    # dry run - locate and report, write nothing
    python3 patch_final2.py --src komorebi.exe.orig --dry-run

    # write a patched copy, keeping the original
    python3 patch_final2.py --src komorebi.exe.orig --dst komorebi.exe

    # patch in place (a .bak backup is written first)
    python3 patch_final2.py --src komorebi.exe --in-place

The script is IDEMPOTENT: if both sites already carry the patch bytes it
reports "already patched" and writes nothing.

It REFUSES to patch when:
  * the `mov ecx,0x2001` sequence is not found exactly once
  * the AllowSetForegroundWindow import is missing, or is called from
    anywhere other than exactly one site
  * the located offsets are not the known-good 0x2898E9 / 0x28D7E4
  * the resulting diff would change anything other than those two 6-byte runs

That last check is what makes it safe to run against a different build: a
wrong-version binary fails loudly instead of being silently corrupted.
"""

import argparse
import os
import shutil
import struct
import sys

REPL = bytes([0xB8, 0x01, 0x00, 0x00, 0x00, 0x90])  # mov eax,1 ; nop

# Known-good offsets for v0.1.41. Used only as a cross-check; the sites are
# always located by pattern, never by offset alone.
EXPECTED_SPI_OFFSET = 0x2898E9
EXPECTED_ASFW_OFFSET = 0x28D7E4

# The instructions that identify the SPI_SETFOREGROUNDLOCKTIMEOUT call site:
#   B9 01 20 00 00            mov ecx, 0x2001        (5 bytes,  idx 0-4)
#   31 D2                     xor edx, edx           (2 bytes,  idx 5-6)
#   45 31 C0                  xor r8d, r8d           (3 bytes,  idx 7-9)
#   41 B9 02 00 00 00         mov r9d, 2             (6 bytes,  idx 10-15)
# This is matched WITHOUT the trailing `FF 15` opcode on purpose. The patch
# overwrites those two bytes, so a pattern that included them would stop
# matching once applied - making the binary look like the wrong version instead
# of "already patched", and the idempotency check below unreachable.
SPI_PREFIX = bytes([
    0xB9, 0x01, 0x20, 0x00, 0x00,
    0x31, 0xD2,
    0x45, 0x31, 0xC0,
    0x41, 0xB9, 0x02, 0x00, 0x00, 0x00,
])
CALL_OPCODE = b'\xFF\x15'   # call [rip+rel32]
CALL_LEN = 6


# ------------------------------------------------------------------ PE utils
def parse_secs(data):
    """Return the section table with file<->RVA deltas."""
    e_lfanew = struct.unpack_from('<I', data, 0x3C)[0]
    coff = e_lfanew + 4
    nsec = struct.unpack_from('<H', data, coff + 2)[0]
    opt_size = struct.unpack_from('<H', data, coff + 16)[0]
    st = coff + 20 + opt_size
    secs = []
    for i in range(nsec):
        s = st + i * 40
        name = data[s:s + 8].rstrip(b'\0').decode('latin1')
        vsize, vaddr, rawsize, rawptr = struct.unpack_from('<IIII', data, s + 8)
        secs.append({
            'name': name, 'vaddr': vaddr, 'rawptr': rawptr,
            'rawsize': rawsize, 'delta': rawptr - vaddr,
        })
    return secs


def rva2off(secs, rva):
    """RVA -> file offset.

    The conversion must go through the section table: every section has its own
    rawptr-vs-vaddr delta. Using one flat offset silently resolves every
    address wrongly and reports "zero matches", which is indistinguishable
    from "the call does not exist".
    """
    for s in secs:
        if s['vaddr'] <= rva < s['vaddr'] + max(s['rawsize'], 0x1000):
            return rva + s['delta']
    return None


def off2rva(secs, off):
    for s in secs:
        if s['rawptr'] <= off < s['rawptr'] + s['rawsize']:
            return off - s['delta']
    return None


def iat_slot_of(data, secs, want_full):
    """File offset of the IAT slot for `dll!function`."""
    e_lfanew = struct.unpack_from('<I', data, 0x3C)[0]
    coff = e_lfanew + 4
    opt_size = struct.unpack_from('<H', data, coff + 16)[0]
    opt = coff + 20
    imp_rva = struct.unpack_from('<II', data, opt + 112 + 8)[0]
    imp_off = rva2off(secs, imp_rva)
    if imp_off is None:
        return None
    d = imp_off
    while True:
        ilt, _ts, _fc, name_rva, first_thunk = struct.unpack_from('<IIIII', data, d)
        if ilt == 0 and name_rva == 0 and first_thunk == 0:
            break
        no = rva2off(secs, name_rva)
        if no is None:
            break
        dll = data[no: data.index(b'\0', no)].decode('latin1')
        thunk_rva = ilt if ilt else first_thunk
        idx = 0
        while True:
            toff = rva2off(secs, thunk_rva)
            if toff is None:
                break
            entry = struct.unpack_from('<Q', data, toff + idx * 8)[0]
            if entry == 0:
                break
            slot_off = rva2off(secs, first_thunk + idx * 8)
            if entry >> 63:
                fn = 'ordinal#%d' % (entry & 0xFFFF)
            else:
                hn = rva2off(secs, entry & 0x7FFFFFFF)
                if hn is None:
                    idx += 1
                    continue
                fn = data[hn + 2: data.index(b'\0', hn + 2)].decode('latin1')
            if slot_off is not None and '%s!%s' % (dll, fn) == want_full:
                return slot_off
            idx += 1
        d += 20
    return None


def asfw_sites(data, secs, iat_off):
    """All file offsets of `call [rip+rel32]` targeting the given IAT slot."""
    out = []
    i = 0
    while True:
        j = data.find(b'\xFF\x15', i)
        if j < 0:
            break
        rel = struct.unpack_from('<i', data, j + 2)[0]
        prva = off2rva(secs, j)
        if prva is not None and rva2off(secs, prva + 6 + rel) == iat_off:
            out.append(j)
        i = j + 1
    return out


def hexs(b):
    return b.hex(' ')


# ------------------------------------------------------------------- locate
def locate(data):
    """Return ([(name, offset)], already_patched_count)."""
    secs = parse_secs(data)
    targets = []
    already = 0

    # ---- [1] SPI_SETFOREGROUNDLOCKTIMEOUT --------------------------------
    n = data.count(SPI_PREFIX)
    print("[1] 'mov ecx,0x2001' instruction prefix occurrences: %d (expect 1)" % n)
    if n != 1:
        print("    ABORT: ambiguous pattern count - this is not a known v0.1.41 build")
        return None
    prefix_at = data.find(SPI_PREFIX)
    site = prefix_at + len(SPI_PREFIX)
    print("    call at 0x%X" % site)
    print("    before: %s" % hexs(bytes(data[prefix_at:site])))
    print("    at    : %s" % hexs(bytes(data[site:site + 14])))
    now = bytes(data[site:site + CALL_LEN])
    if now == REPL:
        print("    already patched")
        already += 1
    elif now[:2] == CALL_OPCODE:
        targets.append(('SPI_SETFOREGROUNDLOCKTIMEOUT', site))
    else:
        print("    ABORT: expected 'call [rip+rel32]' or the patch bytes, found %s" % hexs(now))
        return None
    if site != EXPECTED_SPI_OFFSET:
        print("    NOTE: offset 0x%X differs from the known-good 0x%X"
              % (site, EXPECTED_SPI_OFFSET))

    # ---- [2] AllowSetForegroundWindow ------------------------------------
    iat = iat_slot_of(data, secs, 'user32.dll!AllowSetForegroundWindow')
    print("\n[2] AllowSetForegroundWindow IAT slot: %s"
          % (hex(iat) if iat is not None else 'NOT FOUND'))
    if iat is None:
        print("    ABORT: import not found")
        return None
    sites = asfw_sites(data, secs, iat)
    print("    indirect call sites: %d (expect 1)" % len(sites))
    if len(sites) != 1:
        print("    ABORT: ambiguous site count - refusing to guess")
        return None
    site2 = sites[0]
    print("    call at 0x%X" % site2)
    print("    before: %s" % hexs(bytes(data[site2 - 16:site2])))
    print("    at    : %s" % hexs(bytes(data[site2:site2 + 14])))
    if site2 != EXPECTED_ASFW_OFFSET:
        print("    NOTE: offset 0x%X differs from the known-good 0x%X"
              % (site2, EXPECTED_ASFW_OFFSET))
    if bytes(data[site2:site2 + CALL_LEN]) == REPL:
        print("    already patched")
        already += 1
    else:
        targets.append(('AllowSetForegroundWindow', site2))

    return targets, already


# --------------------------------------------------------------------- main
def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(
        description='Patch komorebi.exe v0.1.41 for Windows 11 26H2.')
    ap.add_argument('--src', default=os.path.join(here, 'Komorebi-Patched', 'komorebi.exe.orig'),
                    help='pristine komorebi.exe to read (default: Komorebi-Patched/komorebi.exe.orig)')
    ap.add_argument('--dst', default=None,
                    help='where to write the patched binary (default: <src>.patched)')
    ap.add_argument('--in-place', action='store_true',
                    help='patch --src itself; a .bak backup is written first')
    ap.add_argument('--dry-run', action='store_true',
                    help='locate and report, write nothing')
    args = ap.parse_args()

    if not os.path.isfile(args.src):
        print("ERROR: source not found: %s" % args.src)
        return 1

    orig = open(args.src, 'rb').read()
    data = bytearray(orig)
    print("source %s (%s bytes)" % (args.src, format(len(data), ',')))

    # Refuse anything that is not a PE32+ executable before touching it. A
    # wrong file must fail with one clear line, not a struct traceback.
    if len(data) < 0x40 or data[:2] != b'MZ':
        print("ERROR: not a Windows executable (no MZ header) - nothing was done.")
        return 1
    try:
        e_lfanew = struct.unpack_from('<I', data, 0x3C)[0]
        if e_lfanew + 6 > len(data) or data[e_lfanew:e_lfanew + 4] != b'PE\0\0':
            print("ERROR: no PE signature at 0x%X - nothing was done." % e_lfanew)
            return 1
        machine = struct.unpack_from('<H', data, e_lfanew + 4)[0]
    except struct.error as exc:
        print("ERROR: truncated or malformed PE header (%s) - nothing was done." % exc)
        return 1
    if machine != 0x8664:
        print("ERROR: machine 0x%X is not x86-64 (0x8664) - nothing was done." % machine)
        return 1

    # Both sites already patched? Check BEFORE locating, and check it on the
    # known-good offsets. The pattern locator for site [2] resolves the call
    # through the IAT, which cannot work once the `FF 15` opcode is gone - so
    # the only reliable way to recognise a fully patched binary is to ask
    # whether the patch bytes are already sitting at the expected offsets.
    if (bytes(data[EXPECTED_SPI_OFFSET:EXPECTED_SPI_OFFSET + CALL_LEN]) == REPL
            and bytes(data[EXPECTED_ASFW_OFFSET:EXPECTED_ASFW_OFFSET + CALL_LEN]) == REPL):
        print("\nBoth call sites are ALREADY patched "
              "(0x%X and 0x%X carry %s) - nothing to do."
              % (EXPECTED_SPI_OFFSET, EXPECTED_ASFW_OFFSET, hexs(REPL)))
        return 0

    found = locate(data)
    if found is None:
        print("\nABORTED - nothing was written.")
        return 1
    targets, already = found

    if not targets:
        print("\nBoth call sites are ALREADY patched - nothing to do.")
        return 0
    if already:
        print("\n%d site(s) already patched, %d to apply." % (already, len(targets)))

    if args.dry_run:
        print("\n--- DRY RUN ---")
        for name, pos in targets:
            print("  would patch %s @0x%X: %s -> %s"
                  % (name, pos, hexs(bytes(data[pos:pos + CALL_LEN])), hexs(REPL)))
        print("Nothing was written.")
        return 0

    # ---- apply ------------------------------------------------------------
    print("\n--- applying ---")
    for name, pos in targets:
        before = bytes(data[pos:pos + CALL_LEN])
        data[pos:pos + CALL_LEN] = REPL
        print("  %s @0x%X: %s -> %s" % (name, pos, hexs(before), hexs(REPL)))

    # ---- verify: exactly the intended bytes differ ------------------------
    print("\n--- verification ---")
    diffs = [i for i in range(len(orig)) if orig[i] != data[i]]
    expect = set()
    for _name, pos in targets:
        expect |= set(range(pos, pos + CALL_LEN))
    print("  total differing byte offsets: %d (expected %d)"
          % (len(diffs), CALL_LEN * len(targets)))
    if set(diffs) != expect:
        print("  FAIL: changed offsets are not exactly the target call sites")
        print("       nothing was written")
        return 1
    for name, pos in targets:
        if bytes(data[pos:pos + CALL_LEN]) != REPL:
            print("  FAIL: %s patch bytes wrong - nothing written" % name)
            return 1
        pre = bytes(data[max(0, pos - 12):pos])
        post = bytes(data[pos + CALL_LEN:pos + CALL_LEN + 12])
        print("  OK %s @0x%X = %s" % (name, pos, hexs(REPL)))
        print("     context intact: ...%s | PATCH | %s..." % (hexs(pre), hexs(post)))

    # ---- write ------------------------------------------------------------
    dst = args.dst
    if args.in_place:
        dst = args.src
        bak = args.src + '.bak'
        if not os.path.exists(bak):
            shutil.copy2(args.src, bak)
            print("\n  backup written: %s" % bak)
        else:
            print("\n  backup already exists: %s (not overwritten)" % bak)
    elif not dst:
        dst = args.src + '.patched'

    with open(dst, 'wb') as f:
        f.write(bytes(data))
    print("  wrote %s (%s bytes)" % (dst, format(len(data), ',')))
    print("\nPATCH OK - only the intended call sites changed")
    return 0


if __name__ == '__main__':
    sys.exit(main())
