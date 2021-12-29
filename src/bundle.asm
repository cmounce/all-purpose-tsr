;; Code related to the bundle of config data appended to the .COM file
%ifndef BUNDLE_ASM
%define BUNDLE_ASM

%include "macros.asm"
%include "string.asm"

;-------------------------------------------------------------------------------
; Consts
;-------------------------------------------------------------------------------
section .data

%define DATA_HEADER " START OF DATA:"
%define PALETTE_KEY "PALETTE"
%define FONT_KEY "FONT"
%define SECONDARY_FONT_KEY "FONT2"
%define BLINK_KEY "BLINK"

; Define a list of all the valid keys
bundle_keys:
    .blink:     db_wstring BLINK_KEY
    .font:      db_wstring FONT_KEY
    .font2:     db_wstring SECONDARY_FONT_KEY
    .palette:   db_wstring PALETTE_KEY
    dw 0        ; Terminate the list of keys


;-------------------------------------------------------------------------------
; Bundled data
;-------------------------------------------------------------------------------
section .append

; Set up data header and save its address
db DATA_HEADER
start_of_bundle:

; Minor hack: initialize the .COM file with some palette data.
; In the future, we won't do this.
db_wstring PALETTE_KEY
begin_wstring
    incbin "../goodies/palettes/rgb332.pal"
end_wstring
db_wstring FONT_KEY
begin_wstring
    incbin "../goodies/fonts/fixed.f14"
end_wstring
db_wstring SECONDARY_FONT_KEY
begin_wstring
    incbin "../legacy/megazeux.chr"
end_wstring
db_wstring BLINK_KEY
begin_wstring
    db 0
end_wstring

; Terminate the data bundle
dw 0


;-------------------------------------------------------------------------------
; Data parsed from the bundle
;-------------------------------------------------------------------------------
section .bss

; Output of parse_bundled_data: the values for each key in the bundle.
; These are each pointers to wstrings, or null if not present.
parsed_bundle:
    .blink:         resw 1
    .font:          resw 1
    .font2:         resw 1
    .palette:       resw 1


;-------------------------------------------------------------------------------
; Code
;-------------------------------------------------------------------------------
section .text

; Reads bundled data from end of .COM file into BSS structs.
;
; Sets CF on failure.
parse_bundled_data:
    push si

    ; Before we parse the bundle, make sure the overall structure is valid.
    call validate_bundle_structure
    jc .failure

    ; Loop over each key-value pair in the bundle
    call load_values_from_bundle
    jc .failure

    ; Make sure that each value (if it exists) is valid
    ; Palette
    mov si, [parsed_bundle.palette]
    cmp si, 0
    begin_if ne
        call validate_palette_wstring
        jc .failure
    end_if

    ; Fonts
    mov si, [parsed_bundle.font]
    cmp si, 0
    begin_if ne
        ; There is a primary font: validate it
        call validate_font_wstring
        jc .failure

        ; Check for a secondary font
        mov si, [parsed_bundle.font2]
        cmp si, 0
        begin_if ne
            call validate_font_wstring
            jc .failure
        end_if
    else
        ; There isn't a primary font.
        ; Secondary fonts are only allowed if there's a primary.
        cmp word [parsed_bundle.font2], 0
        jne .failure
    end_if

    ; Blink flag
    mov si, [parsed_bundle.blink]
    cmp si, 0
    begin_if ne
        cmp word [si], 1    ; Make sure our boolean is exactly 1 byte
        jne .failure
    end_if

    ; Bundle parsed successfully!
    clc
    jmp .ret

    ; Something about the bundle was bad
    .failure:
    stc

    .ret:
    pop si
    ret


; Checks the given wstring to see if it is a valid font.
;
; Takes SI as the address of the wstring to check.
; Sets CF if the wstring fails validation, clears CF otherwise.
validate_font_wstring:
    mov cx, [si]    ; CX = length of wstring
    cmp cl, 0       ; Make sure font data is a multiple of 256 bytes
    jne .failure
    cmp ch, 1       ; Make sure 1 <= font height <= 32
    jb .failure
    cmp ch, 32
    ja .failure

    ; Return success
    clc
    ret

    .failure:
    stc
    ret


; Checks the given wstring to see if it is a valid color palette.
;
; Takes SI as the address of the wstring to check.
; Sets CF if the wstring fails validation, clears CF otherwise.
validate_palette_wstring:
    push si

    ; Make sure the palette has exactly 16 colors
    cmp word [si], 3*16 ; Each color occupies 3 bytes
    jne .failure

    ; Make sure all RGB values are in the range 0-63
    mov cx, 3*16        ; CX = number of channel values
    add si, 2           ; SI = start of wstring data
    .loop:
        lodsb           ; AL = channel value
        cmp al, 63      ; Reject if channel is not a 6-bit quantity
        ja .failure
    loop .loop

    ; All RGB values checked: return success
    clc

    .ret:
    pop si
    ret

    .failure:
    stc
    jmp .ret


;-------------------------------------------------------------------------------
; Internal helpers
;-------------------------------------------------------------------------------
section .text

; Check bundle to make sure it has a valid structure.
;
; This function only checks the overall structure, making sure the bundle fits
; in the allotted space and that every key has a corresponding value. It does
; not validate the keys and values themselves.
;
; Sets CF if bundle structure is invalid.
validate_bundle_structure:
    push bx
    push si

    ; Validate the list structure to make sure that it's both
    ; properly formed and not too long.
    xor cx, cx              ; CX = number of list items
    mov si, start_of_bundle ; SI = pointer to current list item
    while_condition
        cmp word [si], 0    ; Loop until we hit the list terminator
    begin_while ne
        ; Advance SI to point to the next string
        mov bx, si          ; BX = old value of pointer
        next_wstring si
        inc cx              ; Count number of list items

        ; Make sure that we didn't advance so far that we wrapped around
        cmp si, bx
        jbe .invalid

        ; Make sure that we didn't hit the BSS section
        cmp si, section..bss.start
        jae .invalid
    end_while

    ; Make sure that each key in the list has a corresponding value
    and cl, 1       ; If CX is even, return successful (CF = 0).
    jz .ret         ; We don't need `clc` because `and` already clears CF.

    ; Something's wrong with the bundle
    .invalid:
    stc

    .ret:
    pop si
    pop bx
    ret


; Sets pointers in parsed_bundle to point to their values in the bundled data.
;
; Sets CF on failure.
load_values_from_bundle:
    push si

    ; Loop through every key-value pair in the bundle
    mov si, start_of_bundle ; SI = first key in bundle
    while_condition
        cmp word [si], 0    ; Empty string signals end of key-value pairs
    begin_while ne
        ; Consume the next two tokens as a key-value pair
        call bundle_load_key_value
        jc .ret             ; On error, forward the error
    end_while

    ; We recognized every key in the bundle: return success
    clc

    .ret:
    pop si
    ret


; Reads a single key-value pair into the corresponding value in parsed_bundle
;
; Takes SI = wstring of a key, followed by wstring of a value.
; Advances SI past both the key and the value.
; Sets CF on failure.
bundle_load_key_value:
    push bx
    push di

    ; Iterate through our list of keys until we find one matching SI.
    mov di, bundle_keys     ; DI = key to compare SI against
    mov bx, parsed_bundle   ; BX = where the corresponding value would go
    while_condition
        cmp word [di], 0    ; While there are still keys in the allowed list
    begin_while ne
        ; Check whether SI == DI
        call cmp_wstring
        begin_if e
            ; We found our key!
            ; Make sure we don't already have a value for this key
            cmp word [bx], 0
            jne .failure

            ; Consume the key-value pair, saving the value
            next_wstring si     ; Consume key, set SI = value
            mov [bx], si        ; Save pointer to value at BX
            next_wstring si     ; Consume value

            ; Return success
            clc
            jmp .ret
        end_if

        ; Advance pointers
        next_wstring di     ; DI = next wstring
        add bx, 2           ; BX = next pointer in parsed_bundle
    end_while

    ; Return failure: we checked every key in our list, and SI wasn't on it.
    .failure:
    stc

    .ret:
    pop di
    pop bx
    ret


; BUNDLE_ASM
%endif
