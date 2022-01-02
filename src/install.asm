;; Code for installing/uninstalling the TSR
%include "macros.asm"
%include "string.asm"

;-------------------------------------------------------------------------------
; Constants
;-------------------------------------------------------------------------------

; The install/uninstall routines need a way to tell our TSR apart from any
; other TSRs in memory. This pseudorandom ID is how our TSR identifies itself.
section .data
tsr_id:
    begin_wstring .length, .contents
        ; First bytes of SHA-256 hash: "Quantum's all-purpose ZZT initializer"
        db 88, 175, 157, 250, 178, 228, 109, 45
    end_wstring


;-------------------------------------------------------------------------------
; Resident globals
;-------------------------------------------------------------------------------

; These memory addresses overlap with parts of the PSP and non-resident code.
; They only become valid after the resident code has been installed.
absolute 5ch    ; Start of FCB area in PSP

; Reserve stack space for our interrupt handlers to use.
; This overlaps with the top of the PSP space, specifically the two FCBs and
; the command-line string -- unused memory once the TSR is installed.
RESIDENT_STACK_SIZE equ 64
resb RESIDENT_STACK_SIZE
resident_stack_bottom:

; Storage for the old stack's SS:SP, so we can restore it on return
old_stack:
    .offset:    resw 1
    .segment:   resw 1

; Contains the TSR ID to identify this chunk of memory as our TSR
resident_nametag:   resb tsr_id.length

old_int_10h:        ; previous video interrupt
    .offset:        resw 1
    .segment:       resw 1

old_int_2fh:        ; TSR multiplex interrupt
    .offset:        resw 1
    .segment:       resw 1

; Expected value of AX when multiplex interrupt is called
multiplex_ax:
    .function:      resb 1  ; Function code for installation check = 0
    .id:            resb 1  ; TSR's 1-byte numeric ID (assigned at runtime)

; End of fixed-location resident globals, start of font/palette data
resident_data:


;-------------------------------------------------------------------------------
; Non-resident code
;-------------------------------------------------------------------------------
section .text

; Installs the TSR into memory.
;
; This routine never returns because it always terminates the process:
; - On success, the program terminates and stays resident.
; - On failure, the program quits with an error message.
install_tsr:
    ; Get AL = an available multiplex ID
    call scan_multiplex_ids
    cmp al, 0
    begin_if e
        cmp dx, 0       ; DX will be set if TSR already installed
        begin_if ne
            die EXIT_ERROR, "TSR already installed"
        else
            die EXIT_ERROR, "Install failed"
        end_if
    end_if

    ; Set the video mode to match what we're going to install
    push ax             ; Save multiplex ID
    call preview_mode
    pop ax

    ; Install the TSR
    jmp install_and_terminate


; Uninstall the TSR from memory.
uninstall_tsr:
    ; Get DX = TSR's memory segment
    call scan_multiplex_ids
    cmp dx, 0
    begin_if e
        die EXIT_ERROR, "Nothing to uninstall"
    end_if

    ; Attempt to remove TSR from memory
    call uninstall_tsr_at_segment
    cmp ax, 0
    begin_if e
        die EXIT_ERROR, "Uninstall failed"
    end_if

    ; TSR successfully removed. Reset video and return.
    call reset_video
    ret


;-------------------------------------------------------------------------------
; Internal helpers
;-------------------------------------------------------------------------------

; Given the resident code segment, safely remove our TSR from memory.
;
; DX = Resident segment
; Returns AX = 0 on failure, AX = 1 on success.
uninstall_tsr_at_segment:
    push bx
    push ds
    push es
    cli

    ; Make sure interrupt handlers haven't changed since we were installed.
    ; If they have, it means another TSR is installed on top of us.
    mov ax, 3510h   ; Get current 10h vector
    int 21h
    mov ax, es      ; Make sure segment hasn't changed. Technically, we should
    cmp ax, dx      ; also check the offset, but (1) that's hard to calculate,
    jne .fail       ; and (2) it's unlikely someone else is using our segment.

    mov ax, 352Fh   ; Get current 2Fh vector
    int 21h
    mov ax, es      ; Same as above: make sure segment hasn't changed,
    cmp ax, dx      ; and abort if it has.
    jne .fail

    ; Restore old interrupt handlers
    mov es, dx
    mov ax, 2510h                       ; Set 10h handler
    mov ds, [es:old_int_10h.segment]
    mov dx, [es:old_int_10h.offset]
    int 21h

    mov ax, 252Fh                       ; Set 2Fh handler
    mov ds, [es:old_int_2fh.segment]
    mov dx, [es:old_int_2fh.offset]
    int 21h

    ; Free resident memory
    mov ah, 49h                         ; ES = segment to free
    int 21h

    .success:
    mov ax, 1
    jmp .ret

    .fail:
    xor ax, ax

    .ret:
    sti
    pop es
    pop ds
    pop bx
    ret


; Checks to see if our TSR is already resident in memory.
;
; Returns:
; - AL = an available multiplex ID, or 0 if TSR cannot be installed
; - DX = memory segment of our TSR, or 0 if it is not installed
scan_multiplex_ids:
    .MIN_ID equ 0C0h    ; Range of multiplex IDs reserved for applications
    .MAX_ID equ 0FFh

    push bx

    mov bh, .MAX_ID     ; BH = the ID we're currently scanning
    xor bl, bl          ; BL = an unoccupied ID (0 if none found)

    ; Scan all multiplex IDs, from high to low
    begin_do_while
        ; Scan current multiplex ID
        mov ah, bh
        call check_single_multiplex_id
        cmp dx, 0       ; If installed segment is non-zero, we found our TSR
        jne .found

        ; Save the first unoccupied ID we find
        cmp al, 0
        begin_if e
            ; AL == 0: This ID is available
            cmp bl, 0
            begin_if e
                ; BL == 0: This is the first available ID we've found
                mov bl, bh
            end_if
        end_if
    do_while_condition
        dec bh
        cmp bh, .MIN_ID
    end_do_while ae

    ; We finished scanning without finding our TSR
    mov al, bl  ; AL = available multiplex ID, if any
    xor dx, dx  ; DX = 0 means our TSR not found
    jmp .ret

    ; We found our TSR
    .found:
    xor al, al  ; AL = 0 means TSR cannot be installed
                ; DX = resident segment (set by check_single_multiplex_id)

    .ret:
    pop bx
    ret


; Checks to see if a given multiplex ID is occupied.
;
; Takes AH = the multiplex ID to check.
; Returns AL = 0 if that multiplex ID is available.
; Returns DX = resident segment if our TSR is installed here, 0 otherwise.
check_single_multiplex_id:
    ; We're about to call an unknown TSR. Save all 16-bit registers except for:
    ; - Caller-saved registers: AX, CX, DX are acceptable to clobber
    ; - Registers considered to be safe: CS:IP and SS:SP
    push bp
    push bx
    push di
    push ds
    push es
    push si

    ; Call multiplex: AX = ??00h, where ?? is the ID to check
    xor al, al
    xor bx, bx      ; Ralf Brown recommends clearing BX through DX
    xor cx, cx
    xor dx, dx
    int 2fh

    ; Is there a TSR at this multiplex ID?
    cmp al, 0       ; If not, AL will remain 0.
    je .unoccupied  ; We reuse this 0 as part of our return value.

    ; Is the TSR at this multiplex ID our TSR?
    mov si, cs                  ; DS:SI = expected string (tsr_id)
    mov ds, si
    mov si, tsr_id.contents
    mov es, dx                  ; ES:DI = actual string
    mov di, resident_nametag
    mov cx, tsr_id.length       ; CX = number of bytes to compare
    rep cmpsb
    jne .not_us

    ; We found our TSR!
    ; Our return registers should already be populated at this point, because
    ; the TSR multiplex handler sets AL = non-zero and DX = resident segment.
    jmp .ret

    .unoccupied:
    .not_us:
    xor dx, dx      ; Set DX = 0 to indicate our TSR is not installed here

    .ret:
    pop si
    pop es
    pop ds
    pop di
    pop bx
    pop bp
    ret


; Installs TSR and terminates program.
;
; AL = Available multiplex ID to install into (found via scan_multiplex_ids)
install_and_terminate:
    ; Save AL = multiplex ID so we can use it later
    push ax

    ; Initialize buffer to empty string
    mov di, global_buffer
    mov [di], word 0

    ; TODO: Does this belong in string.asm? What should it be called?
    %macro append_empty_wstring 0
        next_wstring di
        mov [di], word 0
    %endmacro

    ; String 1: TSR ID hash
    mov si, tsr_id
    call concat_wstring
    append_empty_wstring

    ; String 2: video data
    call concat_video_data_wstring
    append_empty_wstring

    ; String 3: int 10h handler
    mov si, int_10h_handler_prefix          ; Handler consists of prefix...
    call concat_wstring
    call concat_video_code_wstring          ; video code...
    mov si, int_10h_handler_suffix          ; and suffix, all in one wstring.
    call concat_wstring
    append_empty_wstring

    ; String 4: int 2fh handler
    mov si, int_2fh_handler
    call concat_wstring
    append_empty_wstring

    ; Bundle assembled: install it.
    pop ax                  ; AL = TSR multiplex ID
    jmp finalize_install


; Install code: Overwrite in-memory code with buffer and terminate
;
; AL = TSR ID to use for multiplex identification
; global_buffer = list of 4 wstrings:
;   0. TSR ID hash value
;   1. Data blob (palette/font)
;   2. Code for video interrupt handler
;   3. Code for TSR multiplex handler
finalize_install:
    ; Copy function body to stack.
    ; This is to guarantee that the installation code will be located in
    ; memory at a location where it won't accidentally overwrite itself.
    sub sp, .CODE_SIZE
    mov cx, .CODE_SIZE
    mov si, .CODE
    mov di, sp
    rep movsb

    ; This starts executing at the beginning of the wstring below.
    jmp sp

begin_wstring .CODE_SIZE, .CODE
    ; Save TSR handler ID in resident global
    mov [multiplex_ax.id], al
    mov byte [multiplex_ax.function], 0

    ; Copy TSR ID hash value to resident header
    mov si, global_buffer
    mov di, resident_nametag
    call .transfer_wstring

    ; Copy data blob
    mov di, resident_data
    call .transfer_wstring

    ; Copy interrupt handlers and save their addresses
    push di
    call .transfer_wstring  ; Video interrupt handler
    push di
    call .transfer_wstring  ; TSR multiplex handler

    cli     ; Install interrupts...

    ; Patch TSR multiplex interrupt
    mov     ax, 352Fh                   ; Get old 2Fh vector
    int     21h
    mov     [old_int_2fh.offset], bx    ; Save old vector
    mov     [old_int_2fh.segment], es
    mov     ax, 252Fh                   ; Set new 2Fh vector
    pop     dx
    int     21h

    ; Patch video interrupt
    mov     ax, 3510h                   ; Get old 10h vector
    int     21h
    mov     [old_int_10h.offset], bx    ; Save old vector
    mov     [old_int_10h.segment], es
    mov     ax, 2510h                   ; Set new 10h vector
    pop     dx
    int     21h

    sti     ; Interrupts installed.

    ; Free environment block before exiting
    mov ah, 49h
    mov es, [2ch]   ; Environment segment from PSP
    int 21h

    ; Terminate and stay resident
    mov ax, 3100h   ; TSR, return code 0
    mov dx, di      ; DX = number of bytes that should remain resident
    add dx, 16 - 1  ; Make sure division by 16 gets rounded up
    shr dx, 4       ; DX = number of paragraphs
    int 21h

    ; Helper: Given SI = wstring, copy its raw contents to DI.
    ; Advances SI to next wstring in list, DI to next location to write to.
    .transfer_wstring:
        mov cx, [si]
        add si, 2
        rep movsb
        ret
end_wstring



;-------------------------------------------------------------------------------
; Resident code and code fragments
;-------------------------------------------------------------------------------
section .text

; Code fragments for int 10h (video) handler
int_10h_handler_prefix:
begin_wstring
    ; Silently ignore attempts to change vertical resolution
    cmp ah, 12h
    begin_if e
        cmp bl, 30h
        begin_if e
            mov al, 12h     ; Return success
            iret
        end_if
    end_if

    ; Make sure that this call is changing the video mode
    cmp ah, 0
    je .set_video_mode
    jmp far [cs:old_int_10h]    ; It isn't; defer to the old int 10h handler
    .set_video_mode:

    ; Switch to our own stack, so we don't depend on the caller's
    mov [cs:old_stack.offset], sp   ; Save old SS:SP
    mov [cs:old_stack.segment], ss
    mov sp, cs                      ; New SS:SP = CS:resident_stack_bottom
    mov ss, sp
    mov sp, resident_stack_bottom

    ; Call the old handler as if it was a regular subroutine
    pushf
    call far [cs:old_int_10h]

    ; Prepare registers for running resident code
    pusha           ; Save clobber-able registers returned from old handler
    push ds         ; Set DS = CS
    mov ax, cs
    mov ds, ax

    ; Finally, tell the video code where the video data lives
    mov si, resident_data
end_wstring
    ; Video code goes here...
int_10h_handler_suffix:
begin_wstring
    pop ds                          ; Restore registers, including whatever the
    popa                            ; old int 10h handler returned.
    mov sp, [cs:old_stack.offset]   ; Restore stack.
    mov ss, [cs:old_stack.segment]
    iret
end_wstring

; TSR multiplex handler (int 2Fh)
;
; Sets AL to a non-zero value and returns BX = the resident code segment.
int_2fh_handler:
begin_wstring
    ; Make sure this call is for us
    cmp ax, [cs:multiplex_ax]
    je .match
    jmp far [cs:old_int_2fh]
    .match:

    ; Identify ourselves
    mov al, 0ffh        ; Indicate installed status
    mov dx, cs          ; Return CS so caller can verify CS:resident_nametag
    iret
end_wstring
