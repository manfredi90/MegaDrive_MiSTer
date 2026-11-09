; Z80 side of the savestate test ROM: plays with the YM2612 and the PSG forever.
	org 0
	di
	ld sp, 1ff0h
	ld ix, 4000h
	; channel 1: algorithm 7, all operators audible
	ld a, 22h
	ld b, 0
	call ym1
	ld a, 27h
	ld b, 0
	call ym1
	ld a, 0b0h
	ld b, 7
	call ym1
	ld a, 0b4h
	ld b, 0c0h
	call ym1
	ld hl, opregs
	ld c, 16
oploop:
	ld a, (hl)
	inc hl
	ld b, (hl)
	inc hl
	call ym1
	dec c
	jr nz, oploop
	ld de, 0
main:
	; sweep frequency
	inc de
	ld a, d
	and 7
	or 20h
	ld b, a
	ld a, 0a4h
	call ym1
	ld b, e
	ld a, 0a0h
	call ym1
	; key on/off every 256 steps
	ld a, e
	or a
	jr nz, nokey
	ld a, d
	and 1
	ld a, 0f0h
	jr z, keyon
	xor a
keyon:
	ld b, a
	ld a, 28h
	call ym1
nokey:
	; PSG noise channel volume follows d
	ld a, d
	and 0fh
	or 0f0h
	ld (7f11h), a
	; count in Z80 RAM
	ld hl, (1000h)
	inc hl
	ld (1000h), hl
	jr main

ym1:	; write register a = b on YM2612 part I
	push af
wait1:
	ld a, (ix+0)
	rla
	jr c, wait1
	pop af
	ld (ix+0), a
	ld (ix+1), b
	ret

opregs:
	db 30h, 01h, 34h, 02h, 38h, 04h, 3ch, 01h
	db 40h, 10h, 44h, 18h, 48h, 08h, 4ch, 00h
	db 50h, 1fh, 54h, 1fh, 58h, 1fh, 5ch, 1fh
	db 80h, 0f5h, 84h, 0f5h, 88h, 0f5h, 8ch, 0f5h
