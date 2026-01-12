; LEGEND:
; OUT: ... , IN: ...  - What subroutine outputs and what it expects to receive in registers or a stack
; R: ... - this registers will be changed by this function, register A is always expected to be changed

	device ZXSPECTRUM48
	org 0x6000

main:
	ld sp, addrStack		; Set stack pointer to the address of 65520
	ld a, 2					; Set screen channel
	call zxChOutput			; Open channel output
	call createCustomFont
	ld b, 0
	ld c, 10
	call getCharScreenAddr	; Will return a screen address in HL for row (B) = 0, column (C) = 10
	ld de, strHello			; Pointer to the array of characters/string
	call printStr
	call drawDiamonds
	;ret					; Return to BASIC
	jr $					; Infinite loop for the virtual debugging

; OUT: 0, IN: 0
createCustomFont:
	ld hl, zxAddrFontData	; Address of system font
	LD de, addrFont 		; address of new font
	LD bc, addrFont_end - addrFont
__createCustomFont_loop:
	ld a, (hl)
	rra						; Shift text graphics bits right and OR them to make the font fatter
	or (hl)					; A classic in ZX Spectrum software!
	ld (de), a
	inc hl
	inc de
	dec bc
	ld a, b					; If both B and C reached zero = Z flag will be marked using OR
	or c					; As A will be zero
	jr nz, __createCustomFont_loop

	; Change the system variable to point to the new font
	; Spectrum expects the pointer to the start of the ASCII table, which is just 32 symbols earlier
	; These symbols are "special" and are used in system calls, won't be needed by the custom text graphics drawing
	ld hl, addrFont - 0x100
	ld (zxAddrFontPtr), hl

	ret

; OUT: 0, IN: 0
drawDiamonds:
	ld b, 7
	push bc
__drawDiamonds_memInitLoop:
	ld a, b
	dec a					; -1 to make column index clamped to 0..4, as B is going to be decreased by 1 when executing DJNZ
	exx						; Use page 1 registers
	ld b, 2
	ld c, a
	sla c
	sla c
	ld d, a					; Push and pop value in A, which should preserve the index into the memory address array
	ld a, c
	add a, 3				; Adding + 3 to the column's value
	ld c, a
	ld a, d
	call storeCharAddrs
	exx						; Use page 0 registers
	djnz __drawDiamonds_memInitLoop
	pop bc
	ld hl, addrScreen
	ld a, %01010010			; Initial demo attribute value
__drawDiamonds_drawLoop
	push af					; Push an attribute value onto the stack

	; Retrieve MSB and LSB for the screen address of a character tile
	ld e, (hl)
	inc hl
	ld d, (hl)
	push hl
	ld hl, de
	ld de, artDiamond
	push bc
	call drawTile
	pop bc
	pop hl

	; Retrieve MSB and LSB for the attribute address of a character tile
	inc hl
	ld e, (hl)
	inc hl
	ld d, (hl)
	pop af					; Restore attribute value from the stack
	xor %00010000
	ld (de), a				; And set it for a chosen tile
	inc a
	inc hl
	djnz __drawDiamonds_drawLoop
	
	ret

;
; GROUP: Grid-based draw / print
;

; OUT: 0, IN: pScreenAddress (HL), pTileAddress (DE), R: DE, HL
drawTile:
	ld b, 8					; Tile is 8 bytes or 8x8 pixels
__drawTileLoop:
	ld a, (de)				; Get tile value
	ld (hl), a				; Store tile value
	inc de					; Move tile pointer forward by 1 byte
	inc h					; Move screen pointer to the next bit row (offset 256 bytes, see ZX screen memory structure)
	djnz __drawTileLoop

	ret

; OUT: 0, IN: char (A), pScreenAddr (HL), R: BC, DE, HL
printChar:
	; Store an address in the custom font table into DE
	sub 0x20				; Make the printable chars (start with space at value 32) have a base value of 0
	ex de, hl				; Store screen address in DE
	ld h, 0
	ld l, a
	add hl, hl				; Calculate a 16 bit offset into the custom font table: (char value - 32) * 8
	add hl, hl
	add hl, hl
	ld bc, addrFont
	add hl, bc				; Add custom font's base address to the offset
	ex de, hl				; Swap the result into DE, while restoring screen address to HL

	; Print character graphics, value in HL is used by this
	call drawTile

	ret

; OUT: 0, IN: pScreenAddr (HL), pString (DE), R: DE, HL
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

; OUT: pScreenAddress (HL), IN: row (B), column (C), R: BC, HL
getCharScreenAddr:
	; Get block row offset, (row % 8) * 32 + column
	ld a, b					; Get the original row index
	and 7
	sla a					; Bitshift of (a << n) is equal to a * (2^n)
	sla a
	sla a
	sla a
	sla a					; a * 32
	add a, c				; Add column index, each column is an offset of a single byte
	ld c, a					; The result will never overflow a single byte, so store it in the LSB of BC

	; Get block offset and store it in an MSB, each screen block is 2048 bytes or (a * 256) << 3
	srl b					; Bitshift of (b >> n) is equal to b / (2^n)
	srl b
	srl b					; b / 8 and treat the result of B as if it was multiplied by 256, e.g. it's MSB
	sla b
	sla b
	sla b					; b * 2048
	ld hl, 0x4000			; Screen bits start at 0x4000
	add hl, bc				; Add the total offset to the base address in HL for the final address

	ret

; OUT: pAttributeAddress (HL), IN: row (B), column (C), R: HL
getCharAttribAddr:
	ld h, 0
	ld l, b
	add hl, hl				; Each addition of the same registry with its previous result stored is equal to HL * 2^n
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl				; Row index * 32
	ld a, c					; Multiplying anything by 32 effectively shifts it right by 5 bits making them free
	add a, l				; A column index of 0..31 can be safely added without an overflow
	ld l, a
	ld a, 0x58				; Add the base attribute address to the stored offset to get the final address
	add a, h
	ld h, a

	ret

; OUT: pScreenAddr (HL), pAttributeAddr (DE), IN: getMode (A), row (B), column (C), R: BC, DE, HL
; A == 1: OUT: pAttributeAddr(DE), IN: getMode (A), row (B), column (C), R: HL
; A: 0 = screen address only, 1 = attribute address only, 2+ = both
getCharAddrs:
	cp 0
	jr z, __getCharAddrs_screenAddr
	call getCharAttribAddr
	cp 1
	jr z, __getCharAddrs_return
	ld de, hl

__getCharAddrs_screenAddr:
	call getCharScreenAddr

__getCharAddrs_return:
	ret

;
; END: grid based draw / print
;

; OUT: 0, IN: memory index (A), row (B), column (C)
storeCharAddrs:
	; Calculate and store an offset into the memory array
	ld hl, addrScreen 		; Get the base address of an array to store address into
	ld d, 0
	ld e, a
	add de, de
	add de, de				; Multiply memory index by 4 to get a correct array offset
	add hl, de				; Add this offset to the base array address
	push hl					; Preserve array address by pushing it onto the stack

	; Get screen and attribute addresses using row and column indices from B and C
	ld a, 2					; Option 2 will have HL and DE contain screen and attribute addresses respectively
	call getCharAddrs
	ld bc, hl				; Store screen address in BC
	pop hl					; So that array address can be restored into the HL from the top of the stack
	ld (hl), c				; Addresses are big endian in registers, store them as little endian
	inc hl
	ld (hl), b
	inc hl
	ld (hl), e
	inc hl
	ld (hl), d

	ret

strHello:
	db "Hello World!", 0

artDiamond:
	db 0x18, 0x3C, 0x7E, 0xFF, 0xFF, 0x7E, 0x3C, 0x18	; 8x8 diamond

; ZX Spectrum ROM routines and data
zxChOutput: 	equ 0x1601

zxPrint:		equ 0x230C

zxAddrFontData:	equ 0x3D00

zxAddrFontPtr:	equ 0x5C36

; Custom addresses
addrScreen:		equ 0xF8B0
	ds 0x40		; char[64]8x8

addrFont:		equ 0xF8F0	; Custom font address
	ds 0x300	; Printed symbols have a count of 96, which at 8 bytes per symbol equals 768 bytes
addrFont_end:	equ 0xFBF0

addrStack:		equ 0xFFF0
addrStack_end: 	equ	0xFDF0	; Arbitrary targeted stack size limit of 512 bytes

	savetap "build/ZXHelloWorld.tap", main
	savesna "build/ZXHelloWorld.sna", main