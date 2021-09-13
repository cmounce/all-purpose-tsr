#!/usr/bin/env python
import argparse
import struct

DATA_HEADER = b" START OF DATA:"
PALETTE = b"PALETTE"
FONT = b"FONT"
BLINK = b"BLINK"

FALSE_BYTE = b"\x00"
TRUE_BYTE = b"\x01"

parser = argparse.ArgumentParser(
    description="A tool for creating customized TSRs."
)
parser.add_argument(
    "base_file", type=argparse.FileType("rb"), metavar="BASE-FILE",
    help="an existing .com file to copy program code from"
)
parser.add_argument(
    "-p", "--palette", type=argparse.FileType("rb"),
    help="palette file to include"
)
parser.add_argument(
    "-f", "--font", type=argparse.FileType("rb"),
    help="font file to include"
)
parser.add_argument(
    "--blink", dest="blink", action="store_true",
    help="enable blinking (disable high-intensity backgrounds)"
)
parser.add_argument(
    "--no-blink", dest="blink", action="store_false",
    help="disable blinking (enable high-intensity backgrounds)"
)
parser.set_defaults(blink=None)
parser.add_argument(
    "-o", "--output", type=argparse.FileType("wb"), required=True,
    help="destination of customized .com file"
)
args = parser.parse_args()

# Read base .com file
com_data = args.base_file.read()
header_index = com_data.index(DATA_HEADER)
if header_index == -1:
    raise ValueError(f"{args.base_file.name} is not a valid base .com file")
program_code = com_data[:header_index]

# Build config based on command-line options
config = {}
if args.palette:
    config[PALETTE] = args.palette.read()
    if len(config[PALETTE]) != 3*16:
        raise ValueError(f"{args.palette.name} is not a valid palette")
if args.font:
    config[FONT] = args.font.read()
    font_len = len(config[FONT])
    font_height = font_len // 256
    if font_len % 256 != 0 or font_height < 1 or font_height > 32:
        raise ValueError(f"{args.font.name} is not a valid font")
if args.blink is not None:
    config[BLINK] = TRUE_BYTE if args.blink else FALSE_BYTE

# Generate output TSR
parts = [program_code, DATA_HEADER]
for k, v in config.items():
    line = b"".join([k, b"=", v])
    parts.append(struct.pack("<H", len(line)))
    parts.append(line)
parts.append(b"\x00\x00")
result = b"".join(parts)
args.output.write(result)
