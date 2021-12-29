; Functionality for creating new TSRs
%include 'system.asm'

;-------------------------------------------------------------------------------
; Code
;-------------------------------------------------------------------------------
section .text

; Write a new TSR to a file.
create_new_tsr:
    push bx
    push si

    ; General flow:
    ; - For each option on command line, add that item to the bundle in memory
    ; - Open file as new file for writing
    ; - Copy from memory to file

    ; Before we begin, make sure we have an output file
    cmp word [parsed_options.output], 0
    begin_if e
        die EXIT_BAD_ARGS, "Output file not provided"
    end_if

    ; Build our bundle
    call build_new_bundle
    mov si, cx

    ; Create new file and save handle in BX
    mov dx, [parsed_options.output]
    call dos_create_new_file
    begin_if c
        die EXIT_ERROR, "Couldn't create file"
    end_if
    mov bx, ax      ; BX = file handle

    ; Write program code to file
    mov ah, 40h
    ; TODO: Create a global file with memory layout defines?
    mov dx, 100h                    ; End of PSP
    mov cx, start_of_bundle - 100h  ; Copy program code up to bundle
    int 21h
    ; TODO: It would be slightly more correct to check AX == CX as well
    begin_if c
        die EXIT_ERROR, "Couldn't write to file"
    end_if

    ; Write bundle data to file
    mov ah, 40h
    mov dx, global_buffer   ; DX = start of bundle to write
    mov cx, si              ; CX = size of bundle
    int 21h
    begin_if c
        ; TODO: Combine error messages/move this to a helper function
        die EXIT_ERROR, "Couldn't write to file"
    end_if

    ; Close file
    call dos_close_file
    begin_if c
        die EXIT_ERROR, "Couldn't close file"
    end_if

    pop si
    pop bx
    ret


;-------------------------------------------------------------------------------
; Internal helpers
;-------------------------------------------------------------------------------
section .text

; Build a new bundle in global_buffer based on the parsed command-line args.
;
; Returns CX = size of the bundle in bytes
build_new_bundle:
    push bx
    push di
    push si

    mov di, global_buffer

    ; Add palette to the buffer, if specified
    mov dx, [parsed_options.palette]
    cmp dx, 0
    begin_if ne
        ; Copy key "PALETTE" to buffer
        mov si, bundle_keys.palette
        call copy_wstring
        next_wstring di

        ; Copy palette data to buffer
        mov si, [parsed_options.palette]
        mov cx, 48 + 1          ; Read extra byte to detect too-large palettes
        mov dx, si              ; DX = path to palette file
        call read_wstring_from_path
        begin_if c
            die EXIT_ERROR, "Error reading %s", si
        end_if

        ; Validate palette data
        mov si, di
        call validate_palette_wstring
        begin_if c
            die EXIT_ERROR, "Invalid palette: %s", word [parsed_options.palette]
        end_if
        next_wstring di
    end_if

    ; Add font to the buffer, if specified
    mov dx, [parsed_options.font]
    cmp dx, 0
    begin_if ne
        ; Copy key "FONT" to buffer
        mov si, bundle_keys.font
        call copy_wstring
        next_wstring di

        ; Copy font data to buffer
        mov dx, [parsed_options.font]
        call read_font_from_path
        next_wstring di
    end_if

    ; Add secondary font to the buffer, if specified
    mov dx, [parsed_options.font2]
    cmp dx, 0
    begin_if ne
        ; Verify that a primary font was specified
        cmp word [parsed_options.font], 0
        begin_if e
            die EXIT_ERROR, "Can't use /F2 without /F"
        end_if

        ; Copy key "FONT2" to buffer
        mov si, bundle_keys.font2
        call copy_wstring
        next_wstring di

        ; Copy font data to buffer
        mov dx, [parsed_options.font2]
        call read_font_from_path
        next_wstring di
    end_if

    ; Terminate wstring list
    mov word [di], 0

    lea cx, [di + 2]        ; CX = end of buffer - start of buffer
    sub cx, global_buffer

    pop si
    pop di
    pop bx
    ret


; Read a font file into memory as a wstring
;
; DX = path to font file
; DI = location to write font data
read_font_from_path:
    push bx
    push si

    ; Save path so we can reference it multiple times
    mov bx, dx

    ; Read font data
    mov cx, 32*256 + 1      ; Max font size is at 32 bytes/character
    call read_wstring_from_path
    begin_if c
        die EXIT_ERROR, "Error reading %s", bx
    end_if

    ; Validate font data
    mov si, di
    call validate_font_wstring
    begin_if c
        die EXIT_ERROR, "Invalid font: %s", bx
    end_if

    pop si
    pop bx
    ret


; Open a file and read its contents into a wstring
;
; CX = maximum bytes to read
; DX = wstring containing a path to a file
; DI = location to write the result
; Sets CF on failure.
read_wstring_from_path:
    push bx

    ; Open file and set BX = handle
    push cx                     ; Don't overwrite our argument CX
    call dos_open_existing_file
    pop cx
    jc .ret                     ; Open failed: forward CF to caller
    mov bx, ax

    ; Read CX bytes from handle
    call read_wstring_from_handle
    begin_if c
        ; Read failed
        call dos_close_file     ; Attempt to clean up, but make sure
        stc                     ; we still return failure.
    else
        ; Read succeeded: clean up
        call dos_close_file
    end_if

    .ret:
    pop bx
    ret


; Read bytes from a file into a wstring
;
; BX = file handle to read from
; CX = maximum number of bytes to read
; DI = location to write the wstring
; Sets CF on failure.
read_wstring_from_handle:
    mov ah, 3fh         ; DOS read from handle
    lea dx, [di + 2]    ; DX = pointer to wstring data
    int 21h
    begin_if c
        ret             ; Error: forward CF to caller
    end_if
    mov [di], ax        ; Write actual number of bytes to wstring header

    ; Return successful.
    ; We don't need `clc` because CF should still be clear from the DOS call.
    ret
