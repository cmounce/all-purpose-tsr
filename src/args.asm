;; Code for parsing command-line arguments
%include 'macros.asm'
%include 'print.asm'
%include 'string.asm'

;==============================================================================
; Consts
;------------------------------------------------------------------------------

; The command-line string in the PSP.
arg_string_length      equ 80h
arg_string_contents    equ 81h


;===============================================================================
; Strings
;-------------------------------------------------------------------------------
section .data

; Define a list of all the subcommand strings, with a named label for each one.
; These labels are used like enum values, allowing storage in registers and
; convenient comparisons: e.g., does AX == subcommands.install?
%macro db_subcommand 1
    %deftok %%t %1
    .%[%%t]:
    db_wstring %1
%endmacro
subcommands:
    ; Each subcommand begins with a different letter, in order to allow the
    ; user to make single-character abbreviations (e.g., "foo i" to install).
    db_subcommand "about"
    db_subcommand "install"
    db_subcommand "new"
    db_subcommand "preview"
    db_subcommand "reset"
    db_subcommand "uninstall"
    dw 0    ; end of list


; Define some boolean flags
_flags:
    .help:      db_wstring "/?"

; Define some key-value options
_options:
    .output:    db_wstring "/o"
    .palette:   db_wstring "/p"


;==============================================================================
; Parsed data
;------------------------------------------------------------------------------
section .bss

; String list representing the tokenized argument string.
; How much space do we need? We could have up to 127 tokens, each token taking
; up three bytes (2 byte string header, 1 byte content). Additionally, the list
; itself is terminated with an empty string (2 byte header, no content).
MAX_TOKENS equ 127  ; Worst case: arg string is nothing but forward-slashes
_arg_tokens:
    resb MAX_TOKENS * 3 + 2

; Pointer to a wstring from the subcommands list, e.g., subcommands.install
subcommand_arg:
    resw 1

; Booleans representing flags that are present/absent
parsed_flags:
    .help:      resb 1

; Pointers to wstrings representing option values
parsed_options:
    .output:    resw 1
    .palette:   resw 1


;==============================
; Subroutines
;------------------------------
section .text

;-------------------------------------------------------------------------------
; Read command line flags and initialize status variables accordingly.
;
; This is the main subroutine for parsing the command line, from start to
; end. It takes no parameters and returns nothing: it just mutates the global
; variables to match what the command line args specify.
;-------------------------------------------------------------------------------
parse_command_line:
    push si

    ; Set up SI = start of token list
    call tokenize_arg_string    ; _arg_tokens = string list of tokens
    mov si, _arg_tokens         ; SI = first token

    ; Parse first word as a subcommand, if it exists
    call _parse_subcommand
    cmp word [subcommand_arg], 0

    ; Consume all remaining arguments
    jmp .loop_condition
    .loop:
        call _parse_argument
        cmp ax, 0
        begin_if e
            die EXIT_BAD_ARGS, "Unknown argument: ", si
        end_if

        .loop_condition:
        cmp word [si], 0
        jne .loop

    pop si
    ret


;-------------------------------------------------------------------------------
; Tries to consume the token in SI as a subcommand.
;
; On success: sets subcommand_arg and consumes the token, advancing SI.
; On failure: leaves subcommand_arg untouched (should be zero).
;-------------------------------------------------------------------------------
_parse_subcommand:
    push di

    mov di, subcommands             ; Loop DI = each possible subcommand
    .for_each:
        cmp word [di], 0            ; Break if we run out of subcommands
        je .not_found

        call icmp_wstring           ; If SI == DI, this is a full subcommand.
        je .found
        call _is_short_subcommand   ; If the first letters of SI and DI match,
        je .found                   ; this is an abbreviated subcommand.

        next_wstring di             ; Otherwise, advance DI to the next one.
        jmp .for_each

    .found:
    mov [subcommand_arg], di        ; SI is a valid subcommand. Record it and
    next_wstring si                 ; advance to the next token.

    .not_found:
    pop di
    ret


;-------------------------------------------------------------------------------
; Tries to consume 1-2 tokens from SI as a single argument.
;
; 1-token args are boolean flags, e.g., "/?".
; 2-token args are key-value options, e.g., "/foo=bar" or "/foo bar".
;-------------------------------------------------------------------------------
_parse_argument:
    ; Try to parse SI as a 1-token flag
    call _parse_flag
    cmp ax, 0
    begin_if ne
        ; Success: return AX = 1
        ret
    end_if

    call _parse_option
    cmp ax, 0
    begin_if ne
        ; Success: return AX = 1
        ret
    end_if

    ; Failure: return AX = 0
    ret


;-------------------------------------------------------------------------------
; Tries to consume a 1-token boolean flag from SI, e.g., "/?"
;-------------------------------------------------------------------------------
_parse_flag:
    push di

    ; Compare SI against each of the flag strings
    mov di, _flags.help
    call icmp_wstring
    begin_if e
        mov byte [parsed_flags.help], 1
    else
        ; Return failure: flag not recognized
        xor ax, ax
        jmp .ret
    end_if

    ; Consume token and return success
    next_wstring si
    mov ax, 1
    .ret:
    pop di
    ret

;-------------------------------------------------------------------------------
; Tries to consume a 2-token option from SI, e.g., "/foo=bar"
;
; Returns AX = 1 on success, AX = 0 on failure.
;-------------------------------------------------------------------------------
_parse_option:
    push bx
    push di

    ; Set SI = option key, BX = option value
    mov bx, si
    cmp word [bx], 0
    je .ret             ; Not enough tokens (0)
    next_wstring bx
    cmp word [bx], 0
    je .ret             ; Not enough tokens (1)

    ; Compare SI against each of the option strings
    mov di, _options.output
    call icmp_wstring
    begin_if e
        mov [parsed_options.output], bx
        ; TODO: Move consume-token, return-success logic to central place
        next_wstring bx                 ; Consume the last token
        mov si, bx
        mov ax, 1                       ; Return success
    else
    mov di, _options.palette
    call icmp_wstring
    if e
        mov [parsed_options.palette], bx
        next_wstring bx                 ; Consume the last token
        mov si, bx
        mov ax, 1                       ; Return success
    else
        xor ax, ax                      ; Return failure
    end_if

    .ret:
    pop di
    pop bx
    ret


;-------------------------------------------------------------------------------
; Returns whether SI is a one-character abbreviation of the string in DI.
;
; Examples: "i" or "I" would match "install", but "x" or "inst" would not.
; Returns ZF = 0 if there's a match, nonzero otherwise.
;-------------------------------------------------------------------------------
_is_short_subcommand:
    cmp word [si], 1            ; Is the input string one character long?
    jne .ret
    mov al, [si+2]              ; Get the only character of SI
    call tolower_accumulator
    mov ah, al
    mov al, [di+2]              ; Get first character of DI
    call tolower_accumulator
    cmp ah, al                  ; Do a case-insensitive comparison
    .ret:
    ret


;-------------------------------------------------------------------------------
; Tokenize the PSP argument string and store the result in _arg_tokens.
;-------------------------------------------------------------------------------
tokenize_arg_string:
    push bx
    push di
    push si

    ; Set up all our pointers
    mov si, arg_string_contents     ; SI = argument string to read from
    mov bl, [arg_string_length]     ; BL = number of characters in string
    mov di, _arg_tokens             ; DI = token list to write to

    ; Loop over each char in the arg string
    .for_each:
        cmp bl, 0
        je .break
        dec bl

        ; Read next character into AL
        lodsb

        ; Whitespace and '=' are never included in tokens.
        ; If we see these, skip the character and start a new token.
        call _is_token_separator
        begin_if e
            call .flush_current_token
            jmp .for_each
        end_if

        ; Forward slashes always indicate the start of a new token.
        cmp al, '/'
        begin_if e
            call .flush_current_token
        end_if

        ; Append the character to the current token in DI.
        call concat_byte_wstring

        jmp .for_each
    .break:

    ; Terminate the list if it isn't terminated already
    call .flush_current_token

    pop si
    pop di
    pop bx
    ret

    ; Helper: Make DI point to an empty string at the end of the token list.
    ; This is a no-op if DI already points to an empty string.
    .flush_current_token:
        cmp word [di], 0
        begin_if ne
            next_wstring di     ; Advance DI to point after current contents
            mov word [di], 0    ; Write length header for empty string
        end_if
        ret


;-------------------------------------------------------------------------------
; Returns ZF=1 if the character in AL is a token separator.
;
; Token separators are spaces, tabs, and any other ASCII control characters.
; Additionally, '=' is counted as a separator character: this is so that
; arguments like "/foo=bar" are separated into two tokens.
;
; Clobbers no registers!
;-------------------------------------------------------------------------------
_is_token_separator:
    cmp al, ' ' ; Is it an ASCII control character or a space?
    jbe .true
    cmp al, '=' ; Is it a '='?
    ret
    .true:
    cmp al, al
    ret
