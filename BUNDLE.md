# Bundled-data format
All of the TSR's settings are located at the tail end of the .COM file, in a blob of data called the bundle. The bundle format is a sort of API between the TSR and external programs:

- By inspecting the bundle, programs can read a TSR's font/palette data without having to execute the code.
- By appending a new bundle, programs can create new TSRs without knowledge of how the code works.

## An example bundle
Here is a hex dump from the end of an example TSR, showing what the bundle looks like.

![
% xxd EXAMPLE.COM | tail -n7
00000e00: 7320 636f 7272 7570 740d 0a00 2053 5441  s corrupt... STA
00000e10: 5254 204f 4620 4441 5441 3a07 0050 414c  RT OF DATA:..PAL
00000e20: 4554 5445 3000 0607 0b0a 0d1b 0e2d 1909  ETTE0........-..
00000e30: 1c1e 2c0f 1517 0a17 151b 2125 2b30 0d0f  ..,.......!%+0..
00000e40: 150f 1732 293b 1c1c 3b3d 3b1f 1510 293d  ...2);..;=;...)=
00000e50: 3f33 1d3c 3c3c 0500 424c 494e 4b01 0000  ?3.<<<..BLINK...
00000e60: 0000                                     ..
](images/bundle.png)

The string `START OF DATA:` appears at the very end of the TSR's code. This is for the sake of human readers, but it also enables programs to automatically locate the bundle without knowing the specific byte offset. The bundle itself begins immediately after this string.

The bundle is composed of a series of length-delimited strings. All lengths are 16-bit, little-endian quantities.

- `07 00`, followed by the 7 bytes `PALETTE`. This indicates that palette data follows.
- `30 00`, or 48 in decimal, followed by 48 bytes of palette data.
- `05 00`, followed by the 5 bytes `BLINK`. This indicates that the blinking-text setting follows.
- `01 00`, followed by a 1-byte boolean value. In this example, it's a zero byte, meaning false: blinking text is disabled.
- Finally, `00 00`: the empty string. This signals the end of the bundle.

The whole bundle is just a list of key-value pairs, alternating keys and values. This format was designed to be easy to parse for a program in a typical DOS environment (e.g., assembly or C running in real mode).


## Defined bundle keys
These keys are all optional, and they may appear in the bundle in any order.

- `BLINK`: Whether or not the high bit of text's background color should cause the text to blink. Value is a 1-byte boolean: 0x00 is false (disables blinking), and any other value is true (enables blinking).
- `FONT`: A custom 256-character font in EGA format. Font heights from 1 row (256 bytes total) to 32 rows (8,192 bytes) are supported, although some heights will obviously work better than others. The font height is implied by the number of bytes in the font.
- `FONT2`: A 256-character secondary font that can appear on-screen simultaneously with the primary font, bringing the total number of displayable characters to 512. The high bit of the text's foreground color determines which of the two fonts is used. Requires `FONT` (the primary font) to also be present in the bundle.
- `PALETTE`: A 16-color VGA palette to use for text mode. RGB values are all 6-bit (0 to 63).
