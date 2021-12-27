# All-Purpose TSR
A DOS TSR that changes the font, palette, and toggles high-intensity colors,
all in one command.

This is a rewrite of the original 2008 project, which is located under
`legacy/` for historical purposes.

## Building
Change to the `src/` folder and run `make`.

Alternatively, you can manually compile with NASM like so:

```
nasm -f bin main.asm -o TSR.COM
```

## Usage
Under DOS (or your favorite emulator, e.g., DOSBox), you can run
`TSR i` to initialize the TSR, and `TSR u` to uninstall it.

## License
Everything is under the MIT License, unless otherwise noted.
