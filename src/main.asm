	device ZXSPECTRUM48
	org 0x8000

main:
	ld a, 2					; Upper screen channel
	call 0x1601				; Open channel output
	ld hl, message			; char* message
	ld b, 1					; bool newLine
	call printStr			; C: printStr(char* message, bool newLine)
	ld de, message
	ret						; return to BASIC
	;jr $

printStr:
	ld a, (hl)
	cp 0
	jr z, printStrReturn
	rst 0x10
	inc hl
	jr printStr

printStrNewLine:
	ld a, 0x0D
	rst 0x10
	ret

printStrReturn:
	ld a, b					; If a new line is requested - "print" a carriage return character
	cp 1
	jr z, printStrNewLine
	ret

message:
	db "Hello World!", 0

	savetap "build/ZXHelloWorld.tap", main
	savesna "build/ZXHelloWorld.sna", main