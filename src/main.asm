; LEGEND:
; OUT: ... , IN: ...  - What subroutine outputs and what it expects to receive in registers or a stack
; r - the input register value is preserved after the subroutine returns, r* - the register value will be changed

	device ZXSPECTRUM48
	org 0x6000

main:
	ld sp, 0xFFF0			; Set stack pointer to the address of 65520
	ld a, 2					; Set screen channel
	call 0x1601				; Open channel output
	ld hl, strHello			; char* message
	ld b, 1					; bool newLine
	call printStr
	call drawDiamonds
	;ret					; Return to BASIC
	jr $					; Infinite loop for the virtual debugging

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

; OUT: 0, IN: pString (HL), bAddNewLine (B)
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

; OUT: pScreenAddress (HL), IN: row (B*), column (C*)
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

; OUT: pAttributeAddress (HL), IN: row (B), column (C)
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

; OUT: pScreenAddr (HL), pAttributeAddr (DE), IN: getMode (A*), row (B*), column (C*)
; A == 1: OUT: pAttributeAddr(DE), IN: getMode (A*), row (B), column (C)
; A: 0 = screen address only, 1 = attribute address only, other = both
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

addrScreen:
	ds 0x40		; char[64]8x8

	savetap "build/ZXHelloWorld.tap", main
	savesna "build/ZXHelloWorld.sna", main