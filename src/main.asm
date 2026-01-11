	device ZXSPECTRUM48
	org 0x6000

main:
	ld sp, 0xFFF0			; Set stack pointer to the address of 65520
	ld a, 2					; Upper screen channel
	call 0x1601				; Open channel output
	ld hl, strHello			; char* message
	ld b, 1					; bool newLine
	call printStr
	ld b, 5
	ld c, 4
	call drawDiamonds
	ld de, artDiamond
	call drawTile
	;ret					; Return to BASIC
	jr $					; Infinite loop for the virtual debugging

; OUT: 0, IN: 0
drawDiamonds:
	ld b, 5
__drawDiamonds_memInitLoop:
	ld a, b
	dec a
	exx						; Use page 1 registers
	ld b, 5
	ld c, a
	sla c
	sla c
	inc c
	inc c
	ld b, 5
	call storeCharScreenAddresses
	exx						; Use page 0 registers
	djnz __drawDiamonds_memInitLoop
	ld b, 5
	ld hl, addrScreen
	ld a, %00001010			; Initial demo attribute value
__drawDiamonds_drawLoop
	push af					; Push an attribute value onto the stack

	; Retrieve MSB and LSB for the screen address of a character tile
	ld d, (hl)
	inc hl
	ld e, (hl)
	push hl
	ld hl, de
	ld de, artDiamond
	push bc
	call drawTile
	pop bc
	pop hl

	; Retrieve MSB and LSB for the attribute address of a character tile
	inc hl
	ld d, (hl)
	inc hl
	ld e, (hl)
	pop af					; Restore attribute value from the stack
	ld (de), a				; And set it for a chosen tile
	inc a
	inc hl
	djnz __drawDiamonds_drawLoop
	ret

; OUT: 0, IN: pString (HL), bDoNewLine (B)
printStr:
	ld a, (hl)
	cp 0
	jr z, __printStr_return
	rst 0x10
	inc hl
	jr printStr
__printStr_newLine:
	ld a, 0x0D
	rst 0x10
	ret
__printStr_return:
	ld a, b					; If a new line is requested - "print" a carriage return character
	cp 1
	jr z, __printStr_newLine
	ret

; OUT: 0, IN: pScreenAddress (HL), pTileAddress (DE)
drawTile:
	ld b, 8					; Tile is 8 bytes or 8x8 pixels
__drawTileLoop:
	ld a, (de)				; Get tile value
	ld (hl), a				; Store tile value
	inc de					; Move tile pointer forward by 1 byte
	inc h					; Move screen pointer to the next bit row (offset 256 bytes, see ZX screen memory structure)
	djnz __drawTileLoop
	ret

; OUT: pScreenAddr (HL), pAttributeAddr (DE), IN: row (B), column (C)
getCharScreenAddresses:
	; Calculate attribute address
	ld h, 0
	ld l, b					; Store row value into a 16 bit register
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl
	add hl, hl				; HL * 32 (HL = HL + HL; HL = HL + HL; ...)
	ld d, 0x58
	ld e, c					; Attribute address now contains a column offset
	add de, hl				; Add the row offset for the final attribute address

	; Calculate screen address, start with local block row index (row % 8 or row AND 7)
	ld a, b					; Copy row index into the accumulator to get a local row index in a block of 8 rows
	and 7					; For (x % 2^n) it's possible to cheaply retrieve a correct result using bitwise AND with 2^n - 1
	sla a					; Multiply row index by 32 (row byte width) to get a correct char row offset in a block of 8
	sla a					; x * 32 = x << 5
	sla a
	sla a
	sla a
	add a, c				; Add column index, which is just a plain byte offset, to the current total offset value
	ld l, a					; Put this offset into the LSB of a total offset		

	; Get block index and offset to store it into the MSB of both screen and attribute addresses
	ld a, b					; Copy row index into the accumulator to get block index
	srl	a					; Divide it by 8 or 3 bitwise shifts right
	srl	a
	srl	a					; A contains a value of 0..2 because 3 lower bits were removed and the max row value is 23
	ld b, a					; Temporarily store block index to free up the accumulator
	add a, d
	ld d, a					; Adding block index to an MSB of an attribute address is effectively += 0..2 * 256
	ld a, b					; Restore the accumulator value
	sla a					; Because each block takes 2048 bytes the formula is 0..2 * 2048
	sla a					; Or 0..2 * 8 (or 0..2 << 3) if later treated as an MSB
	sla a
	add a, 0x40				; Effectively add the block offset to 0x4000
	ld h, a					; HL now contains the character pixel address, DE - character attribute address

	ret

; OUT: 0, IN: memory index (A), row (B), column (C),
storeCharScreenAddresses:
	; Calculate and store an offset into the memory array
	ld hl, addrScreen 		; Get the base address of a memory array to store address into
	sla a					; Multiply index by 4 to get an offset
	sla a
	ld d, 0					; Reset D to zero
	ld e, a					; Store an offset
	adc d, 0				; And any possible overflow using the carry bit
	add hl, de				; Add this offset to the base array address
	push hl					; Push the final address onto the stack

	; With B and C registers already preloaded - get appropriate screen memory locations
	call getCharScreenAddresses
	ld bc, hl
	pop hl
	ld (hl), b
	inc hl
	ld (hl), c
	inc hl
	ld (hl), d
	inc hl
	ld (hl), e

	ret

strHello:
	db "Hello World!", 0

artDiamond:
	db 0x18, 0x3C, 0x7E, 0xFF, 0xFF, 0x7E, 0x3C, 0x18	; 8x8 diamond

addrScreen:
	defb 0x40		; char[64]

	savetap "build/ZXHelloWorld.tap", main
	savesna "build/ZXHelloWorld.sna", main