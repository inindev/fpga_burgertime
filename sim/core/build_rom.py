#!/usr/bin/env python3
"""Build the BurgerTime ROM image (64 KB) from a MAME zip as an MRA describes it.

Usage: build_rom.py <btime.zip> <out.rom> [--mra <file.mra>]

The parts of the MRA's <rom index="0"> are taken in order: a part with a crc is
the zip member with that CRC-32, a part with repeat="N" is its hex byte N times,
any other part is its hex bytes. The default MRA is releases/Burger Time (Set 1).mra
in this repository. The image's MD5 is checked against the MRA's md5 attribute.
ROM images are game data: write them only to ignored paths (sim/out/).
"""
import argparse
import hashlib
import os
import sys
import xml.etree.ElementTree as ET
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MRA = os.path.join(HERE, '..', '..', 'releases', 'Burger Time (Set 1).mra')


def hexbytes(text):
    return bytes(int(t, 16) for t in (text or '').split())


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('zip')
    ap.add_argument('out')
    ap.add_argument('--mra', default=DEFAULT_MRA)
    a = ap.parse_args()

    rom = ET.parse(a.mra).getroot().find("rom[@index='0']")
    by_crc = {}
    with zipfile.ZipFile(a.zip) as z:
        for info in z.infolist():
            by_crc.setdefault('%08x' % info.CRC, info)
        img = bytearray()
        for part in rom.findall('part'):
            crc = part.get('crc')
            if crc:
                info = by_crc.get(crc.lower())
                if info is None:
                    sys.exit('no file with crc %s (%s) in %s' % (crc, part.get('name'), a.zip))
                img += z.read(info)
            elif part.get('repeat'):
                img += hexbytes(part.text) * int(part.get('repeat'), 0)
            else:
                img += hexbytes(part.text)

    md5 = hashlib.md5(img).hexdigest()
    want = rom.get('md5', 'none')
    if want != 'none' and md5 != want:
        sys.exit('md5 %s does not match the MRA (%s)' % (md5, want))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, 'wb') as f:
        f.write(img)
    print('%s: %d bytes (0x%x), md5 %s%s' % (a.out, len(img), len(img), md5,
          ' (matches the MRA)' if want != 'none' else ''))


if __name__ == '__main__':
    main()
