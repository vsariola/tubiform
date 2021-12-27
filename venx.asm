org 100h

    ; at startup, ax = 0x0000, si = 0x0100, sp = 0xFFFE and most flags are zero
    dec     ax          ; PIT counter divisor, al = 255
    mov     dx, irq     ; new handler address
    out     40h, al     ; write PIT counter divisor low byte
    salc                ; set AL = 0 (because carry is zero)
    out     40h, al	    ; write PIT counter divisor high byte
                        ; the frequency is now 1,19318181818 MHz / divisor
    mov     ax, 251ch   ; al = which PIT timer interrupt tos set: 08 or 1c. 1c gets called after 08
    int     21h         ; ah = 25h => set interrupt handler, al = which interrupt
    mov		ax, 0x13	; set videomode 13h
    int 	0x10
    push 	0xa000 - 10 ; set es to video segment, shift half a line
    pop 	es
main:
    sub		dh, 100      ; dh = y, shift it to center the coordinates
    pusha				; push all registers to stack 0xFFFC: ax, 0xFFFA: cx, 0xFFF8: dx, bx, sp, bp, si, di
    fild 	word [bx-9]	; fpu: x*256             -9 = 0xFFF7, x is at 0xFFF8 and y is at 0xFFF9
    fild 	word [bx-8] ; fpu: y*256(+x) x*256
    fpatan				; fpu: theta
    fst 	st1			; fpu: theta theta
    fprem				; This instruction will be replaced with fcos so for proper tunnel, fpu: cos(theta) theta
    .effect equ $-1     ; 0xF3 and 0xFC are pretty ok for the last byte
    fimul	dword [byte si+0]  ; fpu: const*cos(theta) theta, the constant is what ever the beginning of the program assembles to
    .rscale equ $-1
    fidiv	word [bx-8]	; fpu: const*cos(theta)/x/256=1/r theta
    fisub	word [byte si+time]     ; fpu: r+offset theta
    fistp	dword [bx-7]            ; store r+offset to where dh is, fpu: theta
    fimul	word [byte si+time+3]	; fpu: t*theta (+2 is initially wrong, but will be replaced with time+0 i.e. correct)
    .thetascale equ $-1
    fistp	word [bx-5] ; store
    popa				; pop all registers from stack
    xor 	al, cl		; al = theta, cl = r
    mov     cl, byte [envs+2] ; when the last instrument kicks in, it adds more details to pattern
    mov     dl, cl
    or   	cl, 32      ; but at the start, we only show bit 5 of the pattern
    and     al, cl      ; we select parts of the texture
    add     dl, byte [envs+1] ; we add together the two first enveloeps
    mul     dl          ; flash the colors based on the sum of the two envelopes
    mov     al, ah
    add     al, 16      ; shift to gray palette, will be replaced with 64 in the last part
    .palette equ $-1
    stosb                   ; di = current pixel, write al to screen
    add     di, word [envs] ; advance di by "random value" (actually, the two first envelopes) for dithering
    mov 	ax, 0xCCCD		; Rrrola trick!
    mul 	di              ; dh = y, dl = x
    cmp     byte [irq.pattern],orderlist-time-1+40 ; check if the pattern is at end
    jne     main
    ret


time:
    db 0,0
; orderlist has: mutate address, mutate value, chn 1, chn 2, chn 3
; There is no need for "first pattern" script, because for the first
; pattern, everything is as loaded. So we place time in that slot.
orderlist:
    db                               0x00, 0x68, 0x00
    db main.thetascale-main,   time, 0x61, 0x61, 0x00
    db     main.effect-main,   0xF3, 0x81, 0x81, 0x00
    db     main.effect-main,   0xF2, 0x61, 0x61, 0x00
    db     main.effect-main,   0xFF, 0x91, 0x00, 0x91
    db     main.rscale-main, time+1, 0x81, 0x81, 0x81
    db    main.palette-main,     64, 0x61, 0x61, 0x61
    db main.thetascale-main, time+3, 0x68, 0x00, 0x68
patterns:
    db 108, 96, 0,  81, 96, 108, 0, 54 ; patterns play from last to first
    db      54, 0, 108, 54,  54, 0, 54 ; 54 from previous pattern


irq:
    pusha
    mov     al, 0
    mov     cx, 3               ; cx is the channel loop counter, we have three channels
    mov     si, time
.loop:
    mov     bp, cx
    movzx   bx, byte [byte orderlist-1+si-time+bp] ; bl = pattern number.
    .pattern equ $ - 1
    test    bx, bx              ; if pattern is zero...
    jz      .skipchannel        ; ... then skip this channel totally
    mov     di, bx
    and     bl, 15
    mov     dx, [si]            ; si points to time
    shr     dx, cl              ; the bits shifted out of si are the position within note
    and     dh, 7               ; patterns are 8 notes long, dh is now the row within pattern
    add     bl, dh              ; bl is pattern + row
    shr     dl, 2               ; dl is now the envelope, 0..63
    mov     bl, byte [patterns-1+bx+si-time] ; bl is the note frequency, bh guaranteed 0
    shl     bx, cl              ; the channels are one octave apart
    shr     di, 4
    imul    bx, di
    imul    bx, word [si]       ; t*freq
    test    bh, 0x80            ; square wave
    jz      .skipchannel
    mov     byte [envs-1+bp+si-time], dl ; save the envelope for visuals
    add     al, dl              ; add channel to sample total
.skipchannel:
    loop    .loop
    mov     dx, 0378h   ; LPT1 parallel port address
    out     dx, al		; write 8 Bit sample data
    dec     word [si]   ; the time runs backwards to have decaying envelopes
    js      .skipnextpattern
    mov     word [si], 0
    movzx   bx, byte [.pattern+si-time] ; modify the movzx instruction
    add     bx, 5                       ; advance order list, each row is 5
    mov     byte [.pattern+si-time], bl ; save back
    mov     al, byte [bx+si]            ; al = value to mutate
    mov     bl, byte [bx+si-1]          ; bl is the relative address of the code to change
    mov     byte [bx+si-time+main], al  ; change part of the code based on demo part
.skipnextpattern:
    popa
    iret

envs:
