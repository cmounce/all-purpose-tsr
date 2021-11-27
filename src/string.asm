;; Helpers for working with strings
%ifndef STRING_ASM
%define STRING_ASM

;===============================================================================
; Macros
;-------------------------------------------------------------------------------

; Prepend a wstring length header to arbitrary assembly. Usage:
;       foo:
;       begin_wstring
;           ; Arbitrary assembly...
;       end_wstring
; In the above example, foo points to a wstring containing the assembled bytes
; of the code between the delimiters.
%macro begin_wstring 0
    %push fragment
    dw %$fragment_size
    %$fragment_start:
%endmacro
%macro end_wstring 0
    %$fragment_size equ $ - %$fragment_start
    %pop fragment
%endmacro

; Like db, but adds a two-byte length prefix before the given string.
; Example: 'db_wstring "ABC"' is equivalent to 'db 3, 0, "ABC"'
%macro db_wstring 1
    %strlen %%n %1
    dw %%n
    db %1
%endmacro

; Advance a register to point to the next wstring in a list.
; Usage: next_wstring si
; Does not stop at end of list; caller is responsible for checking [reg] == 0.
%macro next_wstring 1
    add %1, [%1]    ; Advance pointer by the number of bytes in the wstring
    add %1, 2       ; plus the number of bytes in the length header
%endmacro


;===============================================================================
; Functions
;-------------------------------------------------------------------------------
section .text

;-------------------------------------------------------------------------------
; Appends a single byte onto the wstring DI.
;
; Takes AL = the byte to copy.
;-------------------------------------------------------------------------------
concat_byte_wstring:
    push di

    ; Increment length header
    mov cx, [di]
    inc cx
    mov [di], cx

    ; Write byte to end of string
    inc cx          ; CX = old length + 2
    add di, cx      ; Skip past length header and all old characters
    mov [di], al

    pop di
    ret


;-------------------------------------------------------------------------------
; Copies bytes from SI onto the end of DI.
;
; Assumes that the bytes following the end of DI are safe to overwrite.
;-------------------------------------------------------------------------------
concat_wstring:
    push di
    push si

    ; Copy SI's bytes to end of DI
    mov cx, [si]    ; CX = number of bytes to append
    add si, 2       ; SI = first byte to copy
    next_wstring di ; DI = first byte to write to
    rep movsb

    ; Restore original wstring pointers
    pop si
    pop di

    ; Update DI's size
    mov cx, [si]
    add [di], cx

    ret

;-------------------------------------------------------------------------------
; Performs a case-insensitive comparison of SI and DI.
;
; Sets ZF = 0 if the two strings are equal.
;-------------------------------------------------------------------------------
icmp_wstring:
    push di
    push si

    ; Make sure the two strings are the same size
    mov cx, [si]
    cmp cx, [di]    ; Compare the two sizes,
    jne .ret        ; returning ZF = non-zero if they are different

    ; Advance to the contents of each string
    add si, 2
    add di, 2

    ; Compare the next CX characters
    .loop:
        lodsb                       ; Load character from SI
        call tolower_accumulator    ; and lower-case it
        mov ah, al
        mov al, [di]                ; Load character from DI
        inc di                      ; and lower-case it
        call tolower_accumulator
        cmp al, ah                  ; Compare the two characters,
        jne .ret                    ; returning ZF = non-zero if different.
        loop .loop

    ; If the above loop finishes, then our final comparison set ZF = 0,
    ; which we reuse as our return value when we return below.

    .ret:
    pop si
    pop di
    ret


;-------------------------------------------------------------------------------
; Make the character in AL lowercase.
; Clobbers no registers!
;-------------------------------------------------------------------------------
tolower_accumulator:
    cmp al, 'A'
    jb .ret
    cmp al, 'Z'
    ja .ret
    add al, ('a' - 'A')
    .ret:
    ret


; STRING_ASM
%endif
