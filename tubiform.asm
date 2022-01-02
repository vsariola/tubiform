org 100h

; at startup, we assume ax = 0x0000, cx = 0x00FF, si = 0x0100, sp = 0xFFFE and most flags zero
    mov     ax, 3508h			        ; int 21h: ah = 35h get interrupt handler, al = 08h which interrupt
    int     21h					        ; returns the handler in es:bx
    push    es                          ; save the current handler to be able to restore it
    push    bx
    xchg    ax, cx                      ; PIT counter divisor, al = 255. IRQ init based on superogue's and TomCat's code.
    scaleconst equ $-1
    mov     dx, irq                     ; dx = New handler address
    mov     bl, 0x13                    ; bl = New video mode, mode 13h
envs:                                   ; envs contains the envelopes of the channels. We put them here to have them initialized
    call    init                        ; into known values (in particular, to have chn 3 initialize as 0).
    push 	0xa000 - 10-20*3            ; set es to video segment, shifting 3.5 lines (the top three lines had some visual glitch).
    pop 	es
main:                                   ; basic tunnel effect, based on HellMood's original from http://www.sizecoding.org/wiki/Floating-point_Opcodes#The_.22Tunnel.22
    sub		dh, 0x68                    ; dh = y, shift it to center the coordinates
    pusha				                ; push all registers to stack 0xFFF8: ax, 0xFFF6: cx, 0xFFF4: dx, etc. bx, sp, bp, si, di
    mov     bx,-12                      ; 0xFFF4, where the dx is
    fild 	word [bx-1]	                ; fpu: x*256
    fild 	word [bx]                   ; fpu: y*256(+x) x*256
    fpatan				                ; fpu: theta
    fst 	st1			                ; fpu: theta theta
    fprem				                ; this instruction will be mutated with fsin so for proper tunnel, fpu: sin(theta) theta
    .effect equ $-1                     ; 0xF3, 0xF4, 0xFE and 0xFC are pretty cool visuals for the last byte
    fimul	dword [byte si+scaleconst]  ; fpu: const*cos(theta) theta, the constant is what ever the lines there assemble to
    fidiv	word [bx-1]	                ; fpu: const*sin(theta)/x/256=1/r theta
    fisub	word [byte si+time]         ; fpu: 1/r+offset theta
    fistp	dword [bx]                  ; store r+offset to where dx is, cx&dx affected after popa, fpu: theta
    fnop                                ; this fnop will mutated to something more interesting eventually
    .effect2 equ $-1
    fimul	word [byte si+time+3]	    ; fpu: t*theta (+3 is initially wrong, but will be replaced with time+0 i.e. correct)
    .thetascale equ $-1
    fistp	dword [bx+2]                ; store r+offset to where cx is, cx&ax affected after popa. We avoid messing the original IRQ address
    popa				                ; pop all registers from stack
    mov     al, byte [byte si+envs+2]   ; we rotate the tunnel based on the last channel envelope
    add     ch, al
    xor 	dh, ch		                ; dh = r, ch = theta
    shl     dh, 1
    and     dh, 64                      ; we select parts of the XOR-texture
    add     al, byte [byte si+envs+1]   ; we add together the last two envelopes
    mul     dh                          ; flash the tunnel color based on the sum of the last two envelopes
    mov     al, ah
    add     al, 16                      ; shift to gray palette, will be replaced with 64 in the last part for a more colorful effect
    .palette equ $-1
    stosb                               ; di = current pixel, write al to screen
    imul    di, 85                      ; traverse the pixels in slightly random order (tip from HellMood)
    mov 	ax, 0xCCCD		            ; Rrrola trick!
    mul 	di                          ; dh = y, dl = x
    xchg    bx, ax                      ; HellMood: put the low word of multiplication to bx, so we have more precision
    jc      main                        ; when loading it in FPU
    xchg    ax, dx                      ; dx guaranteed zero here
    in 		al, 0x60                    ; check for ESC key
    dec     ax
    jnz	    main                        ; when song ends, this mutates to jnz -3 so it loops back to dec ax until ax = 0
    .looptarget equ $-1
    pop     dx
    pop     ds
    mov     bl, 3                       ; text mode
init:
    out     40h, al                     ; write PIT counter divisor low byte
    salc                                ; set AL = 0 (because carry is zero)
    out     40h, al	                    ; write PIT counter divisor high byte (freq = 1,19318181818 MHz / divisor)
    xchg    al, bl                      ; set video mode
    int     10h
    mov     ax, 2508h
    int     21h                         ; ah = 25h => set interrupt handler, al = which interrupt
    ret


time:
    db 0,0                              ; time initialized to zero
patterns:
    db 108, 96, 0,  81, 96, 108, 0, 54  ; patterns play from last to first
    db      54, 0, 108, 54,  54, 0, 54  ; one 54 from previous pattern
; orderlist has: chn 1, chn 2, chn 3
orderlist:
    db 0x00, 0x6A, 0x00                 ; the first nibble is chord, second nibble is offset to pattern table
    db 0x64, 0x63, 0x00                 ; note that you should add channel number to the pattern offset to get
    db 0x84, 0x83, 0x00                 ; the actual offset
    db 0x64, 0x63, 0x00
    db 0x94, 0x00, 0x92
    db 0x84, 0x83, 0x82
    db 0x64, 0x63, 0x62
    db 0x6B, 0x00, 0x69


irq:
    pusha
    push    ds                              ; practically only cs is guaranteed to be correct in interrupt
    push    cs                              ; so we save current ds and put ds = cs
    pop     ds
    xor     bp, bp                          ; bp is the total sample value
    mov     cx, 3                           ; cx is the channel loop counter, we have three channels
    mov     si, time
    mov     bx, si
.loop:
    mov     al, byte [byte orderlist-patterns+bx+4]
    .pattern equ $ - 1
    aam     16
    mov     dx, [si]                        ; si points to time
    shr     dx, cl                          ; the bits shifted out of si are the position within note
    and     dh, 7                           ; patterns are 8 notes long, dh is now the row within pattern
    add     al, dh                          ; al is pattern + row
    shr     dl, 2                           ; dl is now the envelope, 0..63
    xlat
    mul     ah
    shl     ax, cl                          ; the channels are one octave apart
    imul    ax, word [si]                   ; t*freq, we cannot do mul word [si] because that would trash dl
    sahf                                    ; square wave, test the highest bit of ax for phase
    jns      .skipchannel                   ; you can test different flags here to shift song up/down octaves
    mov     byte [envs+bx-patterns+4], dl   ; save the envelope for visuals
    add     bp, dx                          ; add channel to sample total
.skipchannel:
    dec     bx
    loop    .loop
    xchg    ax, bp
    mov     dx, 0378h                       ; LPT1 parallel port address for COVOX
    out     dx, al		                    ; write 8 bit sample data
    dec     word [si]                       ; the time runs backwards to have decaying envelopes
    js      .skipnextpattern                ; after 32768 samples, advance orderlist
    mov     word [si], cx                   ; cx guaranteed to be zero
    mov     ax, word [script]
    .scriptpos equ $-2
    mov     bl, ah
    mov     byte [bx], al                   ; change part of the code based on demo part
    add     byte [.pattern+si-time],3       ; modify the movzx instruction
    add     word [.scriptpos+si-time],2
.skipnextpattern:
    pop     ds
    mov     al, 20h
    out     20h, al                         ; end of interrupt signal
    popa
    iret


script:
    db time, main.thetascale ; the tunnel theta multiplier points now to time, so the tunnel changes with time
    db 0xF3,     main.effect ; D9 F3 = fpatan
    db 0xF4,     main.effect ; D9 F4 = fxtract
    db 0xFE,     main.effect ; D9 FE = fsin, hey we have a normal tunnel finally
    db 0xFF,    main.effect2 ; D9 FF = fcos
    db   64,    main.palette
    db 0xE8,     main.effect ; D9 E8 = fld1
    db 0xFD, main.looptarget ; last mutation: change the jnz main after dec ax to jump back to dec ax, so it loops until ax guaranteed 0
