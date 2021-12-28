org 100h

    ; at startup, ax = 0x0000, si = 0x0100, sp = 0xFFFE and most flags are zero
    push 	0xa000 - 10-20*3 ; set es to video segment, shifting 3.5 lines (the top three lines had some isual glitch ).
                                ; push = 0x68 is also used as the shift constant
    pop 	es
    scaleconst:
    dec     ax          ; PIT counter divisor, al = 255. Irq init based on superogue's code.
    mov     dx, irq     ; new handler address
    out     40h, al     ; write PIT counter divisor low byte
    salc                ; set AL = 0 (because carry is zero)
    out     40h, al	    ; write PIT counter divisor high byte
                        ; the frequency is now 1,19318181818 MHz / divisor
    mov     ax, 251ch   ; al = which PIT timer interrupt tos set: 08 or 1c. 1c gets called after 08
    int     21h         ; ah = 25h => set interrupt handler, al = which interrupt. Tomcat: "standard INT08 rutine call INT1C after its own business"
envs:
    mov		ax, 0x13	; set videomode 13h
    int 	0x10
main:                   ; basic tunnel effect, based on Hellmood's original from http://www.sizecoding.org/wiki/Floating-point_Opcodes#The_.22Tunnel.22
    sub		dh, [si]     ; dh = y, shift it to center the coordinates
    pusha				; push all registers to stack 0xFFFC: ax, 0xFFFA: cx, 0xFFF8: dx, bx, sp, bp, si, di
    xor     bx, bx
    fild 	word [bx-9]	; fpu: x*256               -9 = 0xFFF7, x is at 0xFFF8 and y is at 0xFFF9
    fild 	word [bx-8] ; fpu: y*256(+x) x*256
    fpatan				; fpu: theta
    fst 	st1			; fpu: theta theta
    fprem				; This instruction will be replaced with fsin so for proper tunnel, fpu: sin(theta) theta
    .effect equ $-1     ; 0xF3, 0xF4, 0xFE and 0xFC are pretty ok for the last byte
    fimul	dword [byte si+scaleconst]  ; fpu: const*cos(theta) theta, the constant is what ever the lines there assemble to
    .rscale equ $-1
    fidiv	word [bx-9]	; fpu: const*sin(theta)/x/256=1/r theta
    fisub	word [byte si+time]     ; fpu: 1/r+offset theta
    fistp	dword [bx-8]            ; store r+offset to where dx is, cx&dx affected after popa, fpu: theta
    fimul	word [byte si+time+3]	; fpu: t*theta (+2 is initially wrong, but will be replaced with time+0 i.e. correct)
    .thetascale equ $-1
    fistp	dword [bx-6] ; store r+offset to where cx is, cx&ax affected after popa,
    popa				; pop all registers from stack
    add     ch, byte [byte si+envs+2] ; we add together the last two envelopes
    xor 	dh, ch		; dh = r, ch = theta
    shl     dh, 1
    and     dh, 64      ; we select parts of the XOR-texture
    mov     al, byte [byte si+envs+2]
    add     al, byte [byte si+envs+1] ; we add together the last two envelopes
    mul     dh          ; flash the tunnel color based on the sum of the two envelopes
    mov     al, ah
    add     al, 16      ; shift to gray palette, will be replaced with 64 in the last part for a more colorful effect
    .palette equ $-1
    stosb                   ; di = current pixel, write al to screen
    imul    di, 85          ; traverse the pixels in slightly random order (tip from Hellmood)
    mov 	ax, 0xCCCD		; Rrrola trick!
    mul 	di              ; dh = y, dl = x
    xchg    bx, ax
    jo      main
    in 		al, 0x60        ; check for ESC key
    dec 	al
    jz 	    exit
    cmp     byte [irq.pattern],orderlist-time-1+40 ; check if the pattern is at end
    jne     main
exit:
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
    db     main.effect-main,   0xF4, 0x61, 0x61, 0x00
    db     main.effect-main,   0xFE, 0x91, 0x00, 0x91
    db     main.rscale-main, time+1, 0x81, 0x81, 0x81
    db    main.palette-main,     64, 0x61, 0x61, 0x61
    db     main.effect-main,   0xD0, 0x68, 0x00, 0x68
patterns:
    db 108, 96, 0,  81, 96, 108, 0, 54 ; patterns play from last to first
    db      54, 0, 108, 54,  54, 0, 54 ; 54 from previous pattern


irq:
    pusha
    xor     di, di
    mov     cx, 3               ; cx is the channel loop counter, we have three channels
    mov     si, time
    lea     bx, [patterns-1+si-time]
.loop:
    mov     bp, cx
    mov     al, byte [byte orderlist-1+si-time+bp] ; al = pattern number.
    .pattern equ $ - 1
    aam     16
    jz      .skipchannel        ; if pattern is zero, skip this channel
    mov     dx, [si]            ; si points to time
    shr     dx, cl              ; the bits shifted out of si are the position within note
    and     dh, 7               ; patterns are 8 notes long, dh is now the row within pattern
    add     al, dh              ; al is pattern + row
    shr     dl, 2               ; dl is now the envelope, 0..63
    xlat
    mul     ah
    shl     ax, cl              ; the channels are one octave apart
    imul    ax, word [si]       ; t*freq
    test    ah, 0x80            ; square wave
    jz      .skipchannel
    mov     byte [envs-1+bp+si-time], dl ; save the envelope for visuals
    add     di, dx              ; add channel to sample total
.skipchannel:
    loop    .loop
    xchg    ax, di
    mov     dx, 0378h   ; LPT1 parallel port address
    out     dx, al		; write 8 Bit sample data
    dec     word [si]   ; the time runs backwards to have decaying envelopes
    js      .skipnextpattern
    mov     word [si], cx ; cx guaranteed to be zero
    mov     bl, byte [.pattern+si-time] ; modify the movzx instruction
    add     bl, 5                       ; advance order list, each row is 5
    mov     byte [.pattern+si-time], bl ; save back
    mov     ax, word [byte bx+time-0x100-1]            ; al = value to mutate
    mov     bl, al
    mov     byte [byte bx-0x100+main], ah  ; change part of the code based on demo part
.skipnextpattern:
    popa
    iret
