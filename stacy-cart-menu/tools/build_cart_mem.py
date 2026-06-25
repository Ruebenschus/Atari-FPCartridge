#!/usr/bin/env python3

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: build_cart_mem.py <low.bin> <high.bin> <out.mem>", file=sys.stderr)
        return 1

    low_path = Path(sys.argv[1])
    high_path = Path(sys.argv[2])
    out_path = Path(sys.argv[3])

    low = low_path.read_bytes()
    high = high_path.read_bytes()

    if len(low) != len(high):
        print("LOW/HGH size mismatch", file=sys.stderr)
        return 1

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="ascii") as f:
        for hi, lo in zip(high, low):
            f.write(f"{hi:02X}{lo:02X}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
