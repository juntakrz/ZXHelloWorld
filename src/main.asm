; LEGEND:
; OUT: ... , IN: ...  - What subroutine outputs and what it expects to receive in registers or a stack
; R: ... - this registers will be changed by this function, register A is always expected to be changed

	device ZXSPECTRUM48
	org 0x6000

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
	call setScreenGridPointers

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

; OUT: 0, IN: 0, R: BC, DE, HL
setScreenGridPointers:
	ld de, addrScreenRowPtrs
	ld a, 0
__setScreenGridPointers_loop:
	push af						; Preserve A value on top of the stack
	ld b, a
	call calcScreenCellAddr
	pop af
	ex de, hl					; Move screen cell address into DE and array address into HL
	ld (hl), e					; Store LSB of the screen cell address
	inc hl						; Advance HL to next address byte (MSB)
	ld (hl), d					; Store MSB of the screen cell address
	inc hl						; Advance HL to the next array member
	ex de, hl					; Swap DE and HL back
	inc a
	cp 24
	jr nz, __setScreenGridPointers_loop

	ret

;
; END INIT SUBROUTINES
;
	
;
; BEGIN PRINT SUBROUTINES
;

; OUT: 0, IN: char (A), pScreenAddr (HL), R: BC, DE, HL
printChar:
	; Store an address in the custom font table into DE
	sub 0x20					; Make the printable chars (start with space at value 32) have a base value of 0
	ex de, hl					; Store screen address in DE
	ld h, 0
	ld l, a
	add hl, hl					; Calculate a 16 bit offset into the custom font table: (char value - 32) * 8
	add hl, hl
	add hl, hl
	ld bc, addrFont
	add hl, bc					; Add custom font's base address to the offset
	ex de, hl					; Swap the result into DE, while restoring screen address to HL

	; Print character graphics, value in HL is used by this
	call drawTile

	ret

; OUT: 0, IN: pScreenAddr (HL), pString (DE), R: BC (printChar), DE, HL
printStr:
	; Any string provided must end with 0 to exit this function
	ld a, (de)
	cp 0
	jr z, __printStr_return

	; Print character, preserving pointers to move them to the next character/screen address
	push de
	push hl
	call printChar
	pop hl
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

; OUT: 0, IN: pScreenAddress (HL), pTileAddress (DE), R: DE, HL
drawTile:
	ld b, 8						; Tile is 8 bytes or 8x8 pixels
__drawTileLoop:
	ld a, (de)					; Get tile value
	ld (hl), a					; Store tile value
	inc de						; Move tile pointer forward by 1 byte
	inc h						; Move screen pointer to the next bit row (offset 256 bytes, see ZX screen memory structure)
	djnz __drawTileLoop

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

; OUT: HL, IN: row (B), column (C), R: BC, DE, HL
; Address = rowAddressMSB + column
getScreenCellPtr:
	ld de, addrScreenRowPtrs
	sla b
	ld h, 0
	ld l, b
	add hl, de
	ld a, (hl)					; Load LSB of a row address
	add a, c					; Add column offset to it
	inc hl						; Move the pointer to the MSB of a row address
	ld h, (hl)					; Load it into the MSB of the output address
	ld l, a						; Load precalculated LSB as well

	ret

; OUT: pAttributeAddress (HL), IN: row (B), column (C), R: DE, HL
getAttribCellPtr:
	ld h, 0
	ld l, b
	add hl, hl					; Each addition of the same registry with its previous result stored is equal to HL * 2^n
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl					; Row index * 32
	ld d, 0x58					; Attribute base address is 0x5800
	ld e, c						; Add column offset (0..31) to it, which will safely fit into the free 5 bits of current HL
	add hl, de					; Get the final attribute cell address

	ret

; OUT: pScreenAddress (HL), IN: row (B), column (C), R: HL
calcScreenCellAddr:
	; Get block row offset, (row % 8) * 32 + column
	ld a, b						; Get the original row index
	and 7
	sla a						; Bitshift of (a << n) is equal to a * (2^n)
	sla a
	sla a
	sla a
	sla a						; a * 32 (0 .. 224 bytes)
	add a, c					; Add column index (0 .. 31)
	ld l, a

	; Get block offset and store it in an MSB, each screen block is 2048 bytes or (a * 256) << 3
	ld a, b
	srl a						; Bitshift of (b >> n) is equal to b / (2^n)
	srl a
	srl a						; b / 8 and treat the result of B as if it was multiplied by 256, e.g. it's MSB
	sla a
	sla a
	sla a						; b * 2048
	add a, 0x40					; Screen bits start at 0x4000
	ld h, a						; Combine MSB and LSB for the final address

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

; Custom addresses
addrScreenRowPtrs:	equ 0xF000
	ds 0x30			; Pointers to the top left pixel of each row, column offsets are linear, so easy to add later
addrScreenRowPtrs_end

addrFont:			; Custom font address
	ds 0x300		; Printed symbols have a count of 96, which at 8 bytes per symbol equals 768 bytes
addrFont_end

addrStack:			equ 0xFFF0
addrStack_end: 		equ	0xFBF0	; Arbitrary targeted stack size limit of 1024 bytes

colors:
INK_BLACK			equ 0
INK_BLUE			equ 1
INK_RED				equ 2
INK_MAGENTA			equ 3
INK_GREEN			equ 4
INK_CYAN			equ 5
INK_YELLOW			equ 6
INK_WHITE			equ 7
PAPER_BLACK			equ 0
PAPER_BLUE			equ INK_BLUE << 3
PAPER_RED			equ INK_RED << 3
PAPER_MAGENTA		equ INK_MAGENTA << 3
PAPER_GREEN			equ INK_GREEN << 3
PAPER_CYAN			equ INK_CYAN << 3
PAPER_YELLOW		equ INK_YELLOW << 3
PAPER_WHITE			equ INK_WHITE << 3
CELL_BRIGHT			equ 1 << 6
CELL_FLASH			equ 1 << 7

	savetap "build/ZXHelloWorld.tap", main
	savesna "build/ZXHelloWorld.sna", main