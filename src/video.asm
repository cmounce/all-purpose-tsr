; Routines for setting font, palette, etc.
%include 'macros.asm'
%include 'string.asm'

;-------------------------------------------------------------------------------
; Helpers for changing video mode from non-resident code
;-------------------------------------------------------------------------------
section .text

; Set video mode as specified by the bundle
preview_mode:
    push di
    push si

    ; Clear global_buffer
    mov di, global_buffer
    mov [di], word 0

    ; Write data and code to global_buffer
    call concat_video_data_wstring          ; Write data
    next_wstring di                         ; New string
    mov [di], word 0
    call concat_video_code_wstring          ; Write code
    mov si, .ret_code                       ; Write ret to end of code
    call concat_wstring

    ; Call into the code we just wrote
    mov si, global_buffer + 2   ; SI = contents of data wstring
    add di, 2                   ; DI = contents of code wstring
    call di

    pop si
    pop di
    ret

    ; Helper shim to allow us to call video code as subroutine
    .ret_code:
    begin_wstring
        ret
    end_wstring


; Reset video mode
reset_video:
    ; TODO: Get the original video mode and store it somewhere, so we can
    ; return to the exact same settings (resolution, 8-vs-9 dot, etc)?
    ; Probably just a call to int 10, AH=1B
    mov ax, 0003h
    int 10h
    ret


;-------------------------------------------------------------------------------
; Functions for constructing resident code/data blobs
;-------------------------------------------------------------------------------

; Append video code to the wstring in DI.
;
; The generated code takes SI as a pointer to font/palette data to consume.
; When run, it will advance the SI register past all of the data it consumed.
concat_video_code_wstring:
    push si

    ; Append palette-setting code
    cmp [parsed_bundle.palette], word 0
    begin_if ne
        mov si, palette_code
        call concat_wstring
    end_if

    ; Append font-setting code
    cmp [parsed_bundle.font], word 0
    begin_if ne
        mov si, font_code
        call concat_wstring
    end_if

    ; If there are two fonts, append the secondary font code
    cmp word [parsed_bundle.font2], 0
    begin_if ne
        mov si, font2_code
        call concat_wstring
    end_if

    ; Append blink-vs-intensity code
    cmp [parsed_bundle.blink], word 0
    begin_if ne
        mov si, [parsed_bundle.blink]   ; Get blink string and interpret its
        cmp [si + 2], byte 0            ; first byte as a boolean (0 = false)
        begin_if e
            mov si, blink_off_code      ; SI = code to disable blinking
        else
            mov si, blink_on_code       ; SI = code to enable blinking
        end_if

        call concat_wstring             ; Append the appropriate code to result
    end_if

    pop si
    ret


; Append resident font/palette data to the wstring in DI.
concat_video_data_wstring:
    push si

    ; Copy palette data
    mov si, [parsed_bundle.palette]
    cmp si, 0
    begin_if ne
        call concat_wstring
    end_if

    ; Copy font data
    mov si, [parsed_bundle.font]
    cmp si, 0
    begin_if ne
        mov ax, [si]                ; AX = number of bytes in font
        mov al, ah                  ; AL = pixel height of font
        call concat_byte_wstring    ; Write height of font
        call concat_wstring         ; Write SI = actual font data

        ; Copy secondary font data
        mov si, [parsed_bundle.font2]
        cmp si, 0
        begin_if ne
            mov ax, [si]                ; AX = number of bytes in font
            mov al, ah                  ; AL = pixel height of font
            call concat_byte_wstring    ; Write height of font
            call concat_wstring         ; Write SI = actual font data
        end_if
    end_if

    pop si
    ret


;-------------------------------------------------------------------------------
; Internal helpers and code fragments
;-------------------------------------------------------------------------------

; Set text-mode palette to the given 16 color palette.
;
; Takes a pointer DS:SI to palette data.
; Advances SI to point just past the end of the palette data.
palette_code:
begin_wstring
    push bx
    push es

    ; Set palette colors 0-15
    mov ax, 1012h           ; Set block of DAC registers
    mov dx, ds              ; ES:DX = palette data located at DS:SI
    mov es, dx
    mov dx, si
    xor bx, bx              ; Starting color = 0
    mov cx, 16              ; Number of colors = 16
    int 10h

    ; Set palette registers 0-15 to point to colors 0-15.
    ; From the previous interrupt, BH/BL should still be 0,
    ; and CX should still be 16.
    .loop:
        mov ax, 1000h   ; Set palette register
        int 10h
        inc bh          ; Advance to next palette color
        inc bl          ; and next palette register
        loop .loop

    pop es
    pop bx
    add si, 3*16    ; Advance past all palette data
end_wstring


; Set font to the given font data
;
; Takes a pointer DS:SI to font data.
; Expects the first byte of data to represent the font height, to be followed
; by height*256 bytes worth of bitmap data.
; Advances SI to point just past the end of the video data.
font_code:
begin_wstring
    ; TODO: Save several bytes by consolidating most of the register-saving
    ; code into a prefix/suffix shared by palette_code, font_code, etc.
    push bp
    push bx
    push es

    ; Set font
    mov ax, 1110h   ; Load font data
    mov bl, 0       ; BL = table to load into
    mov bh, [si]    ; Read BH = height of font, advancing data pointer
    inc si
    mov cx, 256     ; CX = number of characters to write
    xor dx, dx      ; DX = first character to write
    mov bp, ds      ; Set ES:BP to our font data (DS:SI)
    mov es, bp
    mov bp, si
    int 10h

    ; Advance data pointer
    mov ax, si
    add ah, bh  ; AX += 256*height
    mov si, ax

    pop es
    pop bx
    pop bp
end_wstring


; Load a secondary font from the given font data
;
; Takes a pointer DS:SI to font data.
; Expects the first byte of data to represent the font height, to be followed
; by height*256 bytes worth of bitmap data.
; Advances SI to point just past the end of the video data.
font2_code:
begin_wstring
    ; TODO: A single code block that loads 2 fonts would save resident memory
    push bp
    push bx
    push es

    ; Set font
    mov ax, 1110h   ; Load font data
    mov bl, 1       ; BL = table to load into (primary = 0, secondary = 1)
    mov bh, [si]    ; Read BH = height of font, advancing data pointer
    inc si
    mov cx, 256     ; CX = number of characters to write
    xor dx, dx      ; DX = first character to write
    mov bp, ds      ; Set ES:BP to our font data (DS:SI)
    mov es, bp
    mov bp, si
    int 10h

    ; Set font pointers to point to two different blocks
    mov ax, 1103h
    mov bl, 04h     ; Bit pattern to point A -> 1 and B -> 0
    int 10h

    ; Advance data pointer
    mov ax, si
    add ah, bh  ; AX += 256*height
    mov si, ax

    pop es
    pop bx
    pop bp
end_wstring


; Enable blinking colors
blink_on_code:
begin_wstring
    push bx
    mov ax, 1003h   ; Set blink/intensity
    mov bx, 1       ; Blink = enabled
    int 10h
    pop bx
end_wstring


; Disable blinking colors/enable high intensity
blink_off_code:
begin_wstring
    push bx
    mov ax, 1003h   ; Set blink/intensity
    xor bx, bx      ; Blink = disabled
    int 10h
    pop bx
end_wstring
