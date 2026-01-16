; LEGEND:
; OUT: ... , IN: ...  - What subroutine outputs and what it expects to receive in registers or a stack
; R: ... - this registers will be changed by this function, register A is always expected to be changed

	device ZXSPECTRUM48

; RAM allocations
	org 0xF800
addrFont
	ds 0x300		; Accounting for 96 printable characters, at 8 bytes per character, requires 768 bytes
addrFont_end		; 0xF800 .. 0xFAFF

; Program
	org 0x8000

main:
	ld sp, addrStack		; Set stack pointer to the address of 65520
	call setup
	call demo
	call loopMain

;
; BEGIN SETUP SUBROUTINES
;

setup:
	call createCustomFont

	ret

;
; END SETUP SUBROUTINES
;

;
; BEGIN MAIN LOOP SUBROUTINES
;

loopMain:
	jr $

;
; END MAIN LOOP SUBROUTINES
;

;
; BEGIN DEMO SUBROUTINES
;

demo:
	ld b, 11
	ld c, 10
	call getScreenCellPtr
	ld de, strHello
	call printStr
	ld b, 0						; This is also a Loop index 0 = 0 as it propagates safely through the loops
	ld c, 8
	call getAttribCellPtr
	xor a						; Reset A to 0
__demo_colourLoop
	cpl
	add 8						; Paper color = 7 - ink color
	sla a						; 3 bits of paper color need to be << 3
	sla a
	sla a
	or b						; Store B as ink colour together with paper colour
	ld c, a						; Note: setCellInkAndPaper normally requires them separate in B and C respectively
	xor a						; Loop index 1 = 0
	ld d, a						; Make MSB of DE 0 for the duration of the column loop
__demo_colourColumnLoop
	ex af, af'					; Store loop index 1 in a shadow register A

	; setCellInkAndPaper (faster inline variant)
	ld a, (hl)					; Set ink (B) and paper (C) at cell attribute address (HL)
	and %11000000				; This subroutine is an optimized 'call setCellInkAndPaper' with C containing both colours
	or c						; While B is used to propagate loop_index_0 through the whole loop safely
	ld (hl), a

	ld a, b						; Write the same colors at column_index + 14 - (loop_index_0 * 2)
	add a, a
	cpl
	add a, 15					; Because of NOT A (CPL) an extra 1 is required to be added to the value
	ld e, a
	add hl, de
	
	; setCellInkAndPaper (faster inline variant)
	ld a, (hl)
	and %11000000
	or c
	ld (hl), a

	ld a, b						; Next cell attribute row is exactly at column_index + 32 bytes (or 14 + 18)
	add a, a					; So need to add loop_index_0 * 2 (which is equal with ink color in B)
	add a, 18					; To compensate for the negative offset
	ld e, a
	add hl, de
	ex af, af'
	inc a
	cp 24
	jr nz, __demo_colourColumnLoop
	ld de, 767					; Attribute buffer is exactly 768, so the base address in HL ends up advanced by 1 byte here
	sub hl, de
	inc b						; Ink colour (B) is exactly the same as loop index 0
	ld a, b						; It can be increased in-place to avoid juggling the value between registers
	cp 8
	jr nz, __demo_colourLoop

	ret
;
; END DEMO SUBROUTINES
;

;
; BEGIN INIT SUBROUTINES
;

; OUT: 0, IN: 0
createCustomFont:
	ld hl, zxAddrFontData		; Address of system font
	ld de, addrFont 			; address of new font
	ld bc, addrFont_end - addrFont
__createCustomFont_loop:
	ld a, (hl)
	rra							; Shift text graphics bits right and OR them to make the font fatter
	or (hl)						; A classic in ZX Spectrum software!
	ld (de), a
	inc hl
	inc de
	dec bc
	ld a, b						; If both B and C reached zero = Z flag will be marked using OR
	or c						; As A will be zero
	jr nz, __createCustomFont_loop

	; Change the system variable to point to the new font
	; Spectrum expects the pointer to the start of the ASCII table, which is just 32 symbols earlier
	; These symbols are "special" and are used in system calls, won't be needed by the custom text graphics drawing
	ld hl, addrFont - 0x100
	ld (zxAddrFontPtr), hl

	ret
;
; END INIT SUBROUTINES
;
	
;
; BEGIN PRINT SUBROUTINES
;

; OUT: 0, IN: char (A), pScreenAddr (HL), R: BC (drawTile), DE, HL
printChar:
	; Store an address in the custom font table into DE
	sub 0x20					; Make the printable chars (start with space at value 32) have a base value of 0
	ex de, hl					; Store screen address in DE
	ld h, 0
	ld l, a
	add hl, hl					; Calculate a 16 bit offset into the custom font table: (char value - 32) * 8
	add hl, hl
	add hl, hl
	ld a, h
	add a, HIGH addrFont		; Add the MSB of the custom font address, as LSB is defined as 0
	ld h, a
	ex de, hl					; Swap the result into DE, while restoring screen address to HL

	; Print character graphics, values in DE and HL are used and modified by this subroutine
	call drawTile

	ret

; OUT: 0, IN: pScreenAddr (HL), pString (DE), R: BC (drawTile), DE, HL
printStr:
	; Any string provided must end with 0 to exit this function
	ld a, (de)
	cp 0
	jr z, __printStr_return

	; Print character, DE and HL are pushed onto the stack because drawTile will modify them
	push de
	call printChar
	pop de
	inc hl
	inc de
	jr printStr
__printStr_return:
	ret

;
; END PRINT SUBROUTINES
;

;
; BEGIN GRAPHICS SUBROUTINES
;

; OUT: 0, IN: pScreenAddress (HL), pTileAddress (DE), R: BC, DE
drawTile:
	ld b, 8						; Tile is 8 bytes or 8x8 pixels
__drawTileLoop:
	ld a, (de)					; Get tile value
	ld (hl), a					; Store tile value
	inc de						; Move tile pointer forward by 1 byte
	inc h						; Move screen pointer to the next bit row (offset 256 bytes, see ZX screen memory structure)
	djnz __drawTileLoop
	ld a, h						; Restore HL to its previous value
	sub 8						; This is faster than preserving HL with PUSH and POP (15 vs 21 cycles)
	ld h, a

	ret

;
; END GRAPHICS SUBROUTINES
;

;
; BEGIN COLOUR SUBROUTINES
;

; OUT: 0, IN: ink (B), paper (C), pAttribAddress (HL)
setCellInkAndPaper:
	ld a, (hl)
	and %11000000
	or b
	or c
	ld (hl), a
	
	ret

; OUT: 0, IN: value (B), pAttribAddress (HL)
setCellInk:
	ld a, (hl)
	and %11111000
	or b
	ld (hl), a
	
	ret

setCellPaper:
	ld a, (hl)
	and %11000111
	or b
	ld (hl), a
	
	ret

setCellBright:
	ld a, (hl)
	and %10111111
	or b
	ld (hl), a
	
	ret

setCellFlash:
	ld a, (hl)
	and %01111111
	or b
	ld (hl), a
	
	ret

;
; END COLOUR SUBROUTINES
;

;
; BEGIN GRAPHICS MEMORY SUBROUTINES
;

; OUT: pScreenAddress (HL), IN: row (B), column (C), R: HL
getScreenCellPtr:
	; Get block row offset, (row % 8) * 32 + column
	ld a, b						; Get the original row index
	and %00000111
	rrca						; Bit shift of (a << n) is equal to a * (2^n)
	rrca						; Or bit rotation (a >> 8 - n) if n > 4 to save cycles
	rrca						; a * 32 (0 .. 224)
	or c						; Add column index (0 .. 31) which OR nicely into empty bits
	ld l, a

	; Get block offset and store it in an MSB, each screen block is 2048 bytes or (a * 256) << 3
	ld a, b
	and %00011000				; Each screen block is 2048 bytes, using this mask is effectively row / 8 * 2048
	or 0x40						; Because this byte is treated as MSB of address, adding 0x40 for the final address
	ld h, a						; Combine MSB and LSB for the final address

	ret

; OUT: pAttributeAddress (HL), IN: row (B), column (C), R: HL
getAttribCellPtr:
	ld a, b						; Calculate address MSB
	and %00011000
	rra
	rra
	rra
	add a, 0x58
	ld h, a
	
	ld a, b						; Calculate address LSB
	and %00000111
	rrca
	rrca
	rrca
	or c
	ld l, a

	ret
;
; END GRAPHICS MEMORY SUBROUTINES
;

strHello:
	db "Hello World!", 0

artDiamond:
	db 0x18, 0x3C, 0x7E, 0xFF, 0xFF, 0x7E, 0x3C, 0x18	; 8x8 diamond

; ZX Spectrum ROM routines and data
zxChOutput: 		equ 0x1601

zxPrint:			equ 0x230C

zxAddrFontData:		equ 0x3D00

zxAddrFontPtr:		equ 0x5C36

addrStack:			equ 0xFFF0
addrStack_end: 		equ	0xFBF0	; Arbitrary targeted stack size limit of 1024 bytes

colors:
BLACK				equ 0
BLUE				equ 1
RED					equ 2
MAGENTA				equ 3
GREEN				equ 4
CYAN				equ 5
YELLOW				equ 6
WHITE				equ 7
PAPER_BLACK			equ 0
PAPER_BLUE			equ BLUE << 3
PAPER_RED			equ RED << 3
PAPER_MAGENTA		equ MAGENTA << 3
PAPER_GREEN			equ GREEN << 3
PAPER_CYAN			equ CYAN << 3
PAPER_YELLOW		equ YELLOW << 3
PAPER_WHITE			equ WHITE << 3
CELL_BRIGHT			equ 1 << 6
CELL_FLASH			equ 1 << 7

	savetap "build/ZXHelloWorld.tap", main
	savesna "build/ZXHelloWorld.sna", main