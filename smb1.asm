


	.db "NES", $1a ; identification of the iNES header

	.db 2 ; number of 16KB PRG-ROM pages
	.db 1 ; number of 8KB CHR-ROM pages


	.db 1 ; mapper/mirroring/whatever
	.dsb 9, $00 ; clear the remaining bytes



; -----------------------------------------
; Add definitions
.enum $0000
.include "src/defs.asm"
.ende

; Add RAM definitions
.enum $0000
.include "src/ram.asm"
.ende



.base $8000
.include "src/prg.asm"

; -----------------------------------------
; include CHR-ROM
.incbin "smb1.chr"
