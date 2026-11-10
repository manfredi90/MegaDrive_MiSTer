; Master System mode test program (tb.sv with -DSMS): mode 4 with more sprites per line
; than the VDP can show, sprites moving every frame, PSG tones changing every frame and
; port reads in between, like a game's main loop.
	org 0
	di
	im 1
	ld sp, 0dff0h
	ld hl, vdpregs
	ld b, 22
	ld c, 0bfh
	otir
	; clear the VRAM
	xor a
	out (0bfh), a
	ld a, 40h
	out (0bfh), a
	ld bc, 4000h
clr:	xor a
	out (0beh), a
	dec bc
	ld a, b
	or c
	jr nz, clr
	; tiles 1-2
	ld a, 20h
	out (0bfh), a
	ld a, 40h
	out (0bfh), a
	ld hl, tiles
	ld b, 64
	ld c, 0beh
	otir
	; palettes
	xor a
	out (0bfh), a
	ld a, 0c0h
	out (0bfh), a
	ld hl, pal
	ld b, 32
	otir
	; name table at 3800h: a diagonal of tile 2
	ld de, 3800h
	ld b, 24
nt:	ld a, e
	out (0bfh), a
	ld a, d
	or 40h
	out (0bfh), a
	ld a, 2
	out (0beh), a
	xor a
	out (0beh), a
	ld hl, 66
	add hl, de
	ex de, hl
	djnz nt
	; display on
	ld a, 0c0h
	out (0bfh), a
	ld a, 81h
	out (0bfh), a
	ld ix, 0c000h		; frame counter
	ld (ix+0), 0
main:	in a, (0bfh)		; wait for the frame interrupt flag
	and 80h
	jr z, main
	inc (ix+0)
	; sprite Y table at 3f00h: 20 sprites in two bands, moving down
	xor a
	out (0bfh), a
	ld a, 7fh
	out (0bfh), a
	ld b, 20
	ld c, (ix+0)
sy:	ld a, b
	and 1
	add a, a
	add a, a
	add a, c
	add a, 40
	out (0beh), a
	djnz sy
	ld a, 0d0h		; end of the list
	out (0beh), a
	; X/tile table at 3f80h, moving right
	ld a, 80h
	out (0bfh), a
	ld a, 7fh
	out (0bfh), a
	ld b, 20
	ld d, (ix+0)
sx:	ld a, b
	add a, a
	add a, a
	add a, a
	add a, b
	add a, d
	out (0beh), a
	ld a, 1
	out (0beh), a
	djnz sx
	; PSG: channel 0 tone follows the frame counter, channel 1 and noise on every other frame
	ld a, (ix+0)
	and 0fh
	or 80h
	out (7fh), a
	ld a, (ix+0)
	rrca
	rrca
	and 3fh
	out (7fh), a
	ld a, 90h
	out (7fh), a
	ld a, (ix+0)
	and 1
	jr z, quiet
	ld a, 0a5h
	out (7fh), a
	ld a, 0ch
	out (7fh), a
	ld a, 0b2h
	out (7fh), a
	ld a, 0e4h
	out (7fh), a
	ld a, 0f3h
	out (7fh), a
	jr pads
quiet:	ld a, 0bfh
	out (7fh), a
	ld a, 0ffh
	out (7fh), a
pads:	in a, (0dch)
	in a, (0ddh)
	in a, (7eh)		; V counter
	jp main

vdpregs:
	db 04h, 80h		; mode 4
	db 80h, 81h		; display off for now
	db 0ffh, 82h		; name table 3800h
	db 0ffh, 83h
	db 0ffh, 84h
	db 0ffh, 85h		; sprite table 3f00h
	db 0fbh, 86h		; sprite tiles from 0000h
	db 00h, 87h
	db 00h, 88h
	db 00h, 89h
	db 0ffh, 8ah

tiles:
	; tile 1: a solid square in colour 1-3
	db 0ffh, 00h, 00h, 00h, 0ffh, 00h, 00h, 00h, 0ffh, 0ffh, 00h, 00h, 0ffh, 0ffh, 00h, 00h
	db 0ffh, 00h, 0ffh, 00h, 0ffh, 00h, 0ffh, 00h, 0ffh, 0ffh, 0ffh, 00h, 0ffh, 0ffh, 0ffh, 00h
	; tile 2: stripes
	db 0aah, 55h, 00h, 00h, 55h, 0aah, 00h, 00h, 0aah, 55h, 00h, 00h, 55h, 0aah, 00h, 00h
	db 0aah, 55h, 00h, 00h, 55h, 0aah, 00h, 00h, 0aah, 55h, 00h, 00h, 55h, 0aah, 00h, 00h

pal:
	db 00h, 03h, 0ch, 30h, 0fh, 3ch, 33h, 3fh, 01h, 04h, 10h, 05h, 14h, 11h, 15h, 2ah
	db 00h, 3fh, 30h, 0ch, 03h, 33h, 3ch, 0fh, 2ah, 15h, 11h, 14h, 05h, 10h, 04h, 01h
