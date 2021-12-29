;------------------------------------------------------------------------------
; Messages
;------------------------------------------------------------------------------
section .data

top_level_help:
begin_wstring
    db `All-Purpose TSR (prototype, compiled `, __?UTC_DATE?__, `)\r\n`
    db `\r\n`
    db `Subcommands:\r\n`
    db `  install    Install TSR\r\n`
    db `  new        Create a new TSR\r\n`
    db `  preview    Preview effects of TSR without installing it\r\n`
    db `  reset      Clear screen and reset (undoes effects of preview)\r\n`
    db `  uninstall  Uninstall TSR\r\n`
    db `\r\n`
    db `First letter can also be used: FOO I and FOO INSTALL both work.\r\n`
    db `Use /? with any of these subcommands to learn more.\r\n`
end_wstring

new_help:
begin_wstring
    db `new: Create a brand-new .COM file with different font/palette/etc.\r\n`
    db `\r\n`
    db `  /O output  The name of the .COM file to create.\r\n`
    db `             Call with just this option to get a raw TSR creator.\r\n`
    db `  /P palette Palette file with 16 colors (6-bit VGA palette format)\r\n`
end_wstring

install_help:
begin_wstring
    db `install: Install the TSR.\r\n`
    db `\r\n`
    db `No options\r\n`
end_wstring


;------------------------------------------------------------------------------
; Code
;------------------------------------------------------------------------------
section .text

; Exits with a help message corresponding to the parsed subcommand
show_help:
    ; Set DX = default help message: top-level list of subcommands
    mov dx, top_level_help

    ; If we have a more specific help message, set it
    mov ax, [parsed_subcommand]
    cmp ax, subcommands.install
    begin_if e
        mov dx, install_help
    else
    cmp ax, subcommands.new
    if e
        mov dx, new_help
    end_if

    ; Print the message
    push dx
    call printf_raw

    exit 0
