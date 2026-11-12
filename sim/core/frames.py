#!/usr/bin/env python3
"""Pictures, picture size, pixel stream and audio from the V1 testbench output.

Usage:
  frames.py <stream.bin> --info
  frames.py <stream.bin> --png N[,N...] [--outdir DIR] [--active]
  frames.py <stream.bin> --stream FIRST COUNT <out.hex>
  frames.py <audio.bin> --wav <out.wav>

stream.bin (written by tb_v1.vhd): 2 bytes per pixel enable of the core, from
the first pixel enable after reset, 384 x 272 = 104448 per frame:
  byte 0: r[2:0] g[2:0] b[1:0] (bit 7 = r[2] ... bit 0 = b[0])
  byte 1: bit 0 hblank, bit 1 vblank, bit 2 hs, bit 3 vs, bit 4 screen_flipped
Frame N is samples N*104448 to (N+1)*104448-1, drawn 384 wide, 272 high.

--info: the active picture (hblank = 0 and vblank = 0) of every frame: its size
and position in the 384 x 272 raster, and whether it is the same in all frames.

--png: frame N as <outdir>/frame_NNNN.png (whole raster, blanking dimmed and
tinted; with --active, only the active picture).

--stream: the pixel stream for the frame buffer test (V2): COUNT whole frames
starting at the first vblank rising edge (vblank 0 -> 1) at or after frame
FIRST. Text, one line per pixel enable, 4 hex digits ($readmemh):
  bits 7:0  pixel, RGB 3:3:2: r[2:0] g[2:0] b[1:0] (as video_r, video_g, video_b)
  bit 8     hblank        bit 9   vblank
  bit 10    hs            bit 11  vs
  bit 12    screen_flipped
Each frame is 104448 lines: the vertical blanking first, then the 240 active
lines. Consecutive frames continue the stream without a gap (the core's
timing: 384 pixel enables per line, 272 lines, at 6 MHz = 57.44 Hz).

--wav: audio.bin (16-bit little-endian samples of the core's 11-bit unsigned
audio_out, one per audio update, 6 MHz / 256 = 23437.5 Hz) as a WAV file.
"""
import argparse
import os
import struct
import sys
import zlib

W, H = 384, 272
FRAME = W * H


def load(path):
    with open(path, 'rb') as f:
        d = f.read()
    return d[0::2], d[1::2]


def png(path, w, h, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)

    def chunk(t, b):
        c = struct.pack('>I', len(b)) + t + b
        return c + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b'IDAT', zlib.compress(raw, 9)))
        f.write(chunk(b'IEND', b''))


def rgb(p):
    r, g, b = p >> 5, (p >> 2) & 7, p & 3
    return (r * 255 // 7, g * 255 // 7, b * 255 // 3)


def active_box(ctl, n):
    base = n * FRAME
    xs, ys, count = set(), set(), 0
    for i in range(FRAME):
        if ctl[base + i] & 3 == 0:
            xs.add(i % W)
            ys.add(i // W)
            count += 1
    if not count:
        return None
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    rect = count == (x1 - x0 + 1) * (y1 - y0 + 1)
    return (x0, y0, x1 - x0 + 1, y1 - y0 + 1, rect)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file')
    ap.add_argument('--info', action='store_true')
    ap.add_argument('--png')
    ap.add_argument('--active', action='store_true')
    ap.add_argument('--outdir', default='.')
    ap.add_argument('--stream', nargs=3, metavar=('FIRST', 'COUNT', 'OUT'))
    ap.add_argument('--wav')
    a = ap.parse_args()

    if a.wav:
        with open(a.file, 'rb') as f:
            d = f.read()
        s = struct.unpack('<%dH' % (len(d) // 2), d)
        pcm = b''.join(struct.pack('<h', (v << 5) - 32768) for v in s)
        rate = 23437
        with open(a.wav, 'wb') as f:
            f.write(b'RIFF' + struct.pack('<I', 36 + len(pcm)) + b'WAVE')
            f.write(b'fmt ' + struct.pack('<IHHIIHH', 16, 1, 1, rate, rate * 2, 2, 16))
            f.write(b'data' + struct.pack('<I', len(pcm)) + pcm)
        print('%s: %d samples, min %d, max %d, %d distinct values' %
              (a.wav, len(s), min(s), max(s), len(set(s))))
        return

    pix, ctl = load(a.file)
    frames = len(ctl) // FRAME
    print('%s: %d samples, %d whole frames' % (a.file, len(ctl), frames))

    if a.info:
        boxes = {}
        for n in range(frames):
            boxes.setdefault(active_box(ctl, n), []).append(n)
        for b, ns in boxes.items():
            if b is None:
                print('no active picture: %d frames (%d..%d)' % (len(ns), ns[0], ns[-1]))
            else:
                print('active %d x %d at x %d, y %d of the 384 x 272 raster%s: %d frames (%d..%d)' %
                      (b[2], b[3], b[0], b[1], '' if b[4] else ' (NOT a rectangle)',
                       len(ns), ns[0], ns[-1]))

    if a.png:
        os.makedirs(a.outdir, exist_ok=True)
        for n in [int(x) for x in a.png.split(',')]:
            base = n * FRAME
            if a.active:
                b = active_box(ctl, n)
                x0, y0, w, h = b[0], b[1], b[2], b[3]
            else:
                x0, y0, w, h = 0, 0, W, H
            rows = []
            for y in range(y0, y0 + h):
                row = []
                for x in range(x0, x0 + w):
                    i = base + y * W + x
                    c = rgb(pix[i])
                    if ctl[i] & 3:
                        c = (c[0] // 3 + 40, c[1] // 3, c[2] // 3 + 40)
                    row.extend(c)
                rows.append(row)
            path = os.path.join(a.outdir, 'frame_%04d.png' % n)
            png(path, w, h, rows)
            print(path)

    if a.stream:
        first, count, out = int(a.stream[0]), int(a.stream[1]), a.stream[2]
        i = max(first * FRAME, 1)
        while i < len(ctl) and not (ctl[i] & 2 and not ctl[i - 1] & 2):
            i += 1
        if i + count * FRAME > len(ctl):
            sys.exit('not enough samples for %d frames from sample %d' % (count, i))
        with open(out, 'w') as f:
            for k in range(i, i + count * FRAME):
                f.write('%04x\n' % (((ctl[k] & 0x1f) << 8) | pix[k]))
        print('%s: %d frames from sample %d (frame %d, line %d, pixel %d)' %
              (out, count, i, i // FRAME, (i % FRAME) // W, i % W))


if __name__ == '__main__':
    main()
