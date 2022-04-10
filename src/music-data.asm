; music header offsets

MusicHeaderData:
	.db DeathMusHdr-MHD                          ; event music
	.db GameOverMusHdr-MHD
	.db VictoryMusHdr-MHD
	.db WinCastleMusHdr-MHD
	.db GameOverMusHdr-MHD
	.db EndOfLevelMusHdr-MHD
	.db TimeRunningOutHdr-MHD
	.db SilenceHdr-MHD

	.db GroundLevelPart1Hdr-MHD                  ; area music
	.db WaterMusHdr-MHD
	.db UndergroundMusHdr-MHD
	.db CastleMusHdr-MHD
	.db Star_CloudHdr-MHD
	.db GroundLevelLeadInHdr-MHD
	.db Star_CloudHdr-MHD
	.db SilenceHdr-MHD

	.db GroundLevelLeadInHdr-MHD                 ; ground level music layout
	.db GroundLevelPart1Hdr-MHD, GroundLevelPart1Hdr-MHD
	.db GroundLevelPart2AHdr-MHD, GroundLevelPart2BHdr-MHD, GroundLevelPart2AHdr-MHD, GroundLevelPart2CHdr-MHD
	.db GroundLevelPart2AHdr-MHD, GroundLevelPart2BHdr-MHD, GroundLevelPart2AHdr-MHD, GroundLevelPart2CHdr-MHD
	.db GroundLevelPart3AHdr-MHD, GroundLevelPart3BHdr-MHD, GroundLevelPart3AHdr-MHD, GroundLevelLeadInHdr-MHD
	.db GroundLevelPart1Hdr-MHD, GroundLevelPart1Hdr-MHD
	.db GroundLevelPart4AHdr-MHD, GroundLevelPart4BHdr-MHD, GroundLevelPart4AHdr-MHD, GroundLevelPart4CHdr-MHD
	.db GroundLevelPart4AHdr-MHD, GroundLevelPart4BHdr-MHD, GroundLevelPart4AHdr-MHD, GroundLevelPart4CHdr-MHD
	.db GroundLevelPart3AHdr-MHD, GroundLevelPart3BHdr-MHD, GroundLevelPart3AHdr-MHD, GroundLevelLeadInHdr-MHD
	.db GroundLevelPart4AHdr-MHD, GroundLevelPart4BHdr-MHD, GroundLevelPart4AHdr-MHD, GroundLevelPart4CHdr-MHD

; music headers
; header format is as follows:
; 1 byte - length byte offset
; 2 bytes -  music data address
; 1 byte - triangle data offset
; 1 byte - square 1 data offset
; 1 byte - noise data offset (not used by secondary music)

TimeRunningOutHdr:
	.db $08, <TimeRunOutMusData, >TimeRunOutMusData, $27, $18
Star_CloudHdr:
	.db $20, <Star_CloudMData, >Star_CloudMData, $2e, $1a, $40
EndOfLevelMusHdr:
	.db $20, <WinLevelMusData, >WinLevelMusData, $3d, $21
ResidualHeaderData:
	.db $20, $c4, $fc, $3f, $1d
UndergroundMusHdr:
	.db $18, <UndergroundMusData, >UndergroundMusData, $00, $00
SilenceHdr:
	.db $08, <SilenceData, >SilenceData, $00
CastleMusHdr:
	.db $00, <CastleMusData, >CastleMusData, $93, $62
VictoryMusHdr:
	.db $10, <VictoryMusData, >VictoryMusData, $24, $14
GameOverMusHdr:
	.db $18, <GameOverMusData, >GameOverMusData, $1e, $14
WaterMusHdr:
	.db $08, <WaterMusData, >WaterMusData, $a0, $70, $68
WinCastleMusHdr:
	.db $08, <EndOfCastleMusData, >EndOfCastleMusData, $4c, $24
GroundLevelPart1Hdr:
	.db $18, <GroundM_P1Data, >GroundM_P1Data, $2d, $1c, $b8
GroundLevelPart2AHdr:
	.db $18, <GroundM_P2AData, >GroundM_P2AData, $20, $12, $70
GroundLevelPart2BHdr:
	.db $18, <GroundM_P2BData, >GroundM_P2BData, $1b, $10, $44
GroundLevelPart2CHdr:
	.db $18, <GroundM_P2CData, >GroundM_P2CData, $11, $0a, $1c
GroundLevelPart3AHdr:
	.db $18, <GroundM_P3AData, >GroundM_P3AData, $2d, $10, $58
GroundLevelPart3BHdr:
	.db $18, <GroundM_P3BData, >GroundM_P3BData, $14, $0d, $3f
GroundLevelLeadInHdr:
	.db $18, <GroundMLdInData, >GroundMLdInData, $15, $0d, $21
GroundLevelPart4AHdr:
	.db $18, <GroundM_P4AData, >GroundM_P4AData, $18, $10, $7a
GroundLevelPart4BHdr:
	.db $18, <GroundM_P4BData, >GroundM_P4BData, $19, $0f, $54
GroundLevelPart4CHdr:
	.db $18, <GroundM_P4CData, >GroundM_P4CData, $1e, $12, $2b
DeathMusHdr:
	.db $18, <DeathMusData, >DeathMusData, $1e, $0f, $2d

; --------------------------------

; MUSIC DATA
; square 2/triangle format
; d7 - length byte flag (0-note, 1-length)
; if d7 is set to 0 and d6-d0 is nonzero:
; d6-d0 - note offset in frequency look-up table (must be even)
; if d7 is set to 1:
; d6-d3 - unused
; d2-d0 - length offset in length look-up table
; value of $00 in square 2 data is used as null terminator, affects all sound channels
; value of $00 in triangle data causes routine to skip note

; square 1 format
; d7-d6, d0 - length offset in length look-up table (bit order is d0,d7,d6)
; d5-d1 - note offset in frequency look-up table
; value of $00 in square 1 data is flag alternate control reg data to be loaded

; noise format
; d7-d6, d0 - length offset in length look-up table (bit order is d0,d7,d6)
; d5-d4 - beat type (0 - rest, 1 - short, 2 - strong, 3 - long)
; d3-d1 - unused
; value of $00 in noise data is used as null terminator, affects only noise

; all music data is organized into sections (unless otherwise stated):
; square 2, square 1, triangle, noise

Star_CloudMData:
	.db $84, $2c, $2c, $2c, $82, $04, $2c, $04, $85, $2c, $84, $2c, $2c
	.db $2a, $2a, $2a, $82, $04, $2a, $04, $85, $2a, $84, $2a, $2a, $00

	.db $1f, $1f, $1f, $98, $1f, $1f, $98, $9e, $98, $1f
	.db $1d, $1d, $1d, $94, $1d, $1d, $94, $9c, $94, $1d

	.db $86, $18, $85, $26, $30, $84, $04, $26, $30
	.db $86, $14, $85, $22, $2c, $84, $04, $22, $2c

	.db $21, $d0, $c4, $d0, $31, $d0, $c4, $d0, $00

GroundM_P1Data:
	.db $85, $2c, $22, $1c, $84, $26, $2a, $82, $28, $26, $04
	.db $87, $22, $34, $3a, $82, $40, $04, $36, $84, $3a, $34
	.db $82, $2c, $30, $85, $2a

SilenceData:
	.db $00

	.db $5d, $55, $4d, $15, $19, $96, $15, $d5, $e3, $eb
	.db $2d, $a6, $2b, $27, $9c, $9e, $59

	.db $85, $22, $1c, $14, $84, $1e, $22, $82, $20, $1e, $04, $87
	.db $1c, $2c, $34, $82, $36, $04, $30, $34, $04, $2c, $04, $26
	.db $2a, $85, $22

GroundM_P2AData:
	.db $84, $04, $82, $3a, $38, $36, $32, $04, $34
	.db $04, $24, $26, $2c, $04, $26, $2c, $30, $00

	.db $05, $b4, $b2, $b0, $2b, $ac, $84
	.db $9c, $9e, $a2, $84, $94, $9c, $9e

	.db $85, $14, $22, $84, $2c, $85, $1e
	.db $82, $2c, $84, $2c, $1e

GroundM_P2BData:
	.db $84, $04, $82, $3a, $38, $36, $32, $04, $34
	.db $04, $64, $04, $64, $86, $64, $00

	.db $05, $b4, $b2, $b0, $2b, $ac, $84
	.db $37, $b6, $b6, $45

	.db $85, $14, $1c, $82, $22, $84, $2c
	.db $4e, $82, $4e, $84, $4e, $22

GroundM_P2CData:
	.db $84, $04, $85, $32, $85, $30, $86, $2c, $04, $00

	.db $05, $a4, $05, $9e, $05, $9d, $85

	.db $84, $14, $85, $24, $28, $2c, $82
	.db $22, $84, $22, $14

	.db $21, $d0, $c4, $d0, $31, $d0, $c4, $d0, $00

GroundM_P3AData:
	.db $82, $2c, $84, $2c, $2c, $82, $2c, $30
	.db $04, $34, $2c, $04, $26, $86, $22, $00

	.db $a4, $25, $25, $a4, $29, $a2, $1d, $9c, $95

GroundM_P3BData:
	.db $82, $2c, $2c, $04, $2c, $04, $2c, $30, $85, $34, $04, $04, $00

	.db $a4, $25, $25, $a4, $a8, $63, $04

; triangle data used by both sections of third part
	.db $85, $0e, $1a, $84, $24, $85, $22, $14, $84, $0c

GroundMLdInData:
	.db $82, $34, $84, $34, $34, $82, $2c, $84, $34, $86, $3a, $04, $00

	.db $a0, $21, $21, $a0, $21, $2b, $05, $a3

	.db $82, $18, $84, $18, $18, $82, $18, $18, $04, $86, $3a, $22

; noise data used by lead-in and third part sections
	.db $31, $90, $31, $90, $31, $71, $31, $90, $90, $90, $00

GroundM_P4AData:
	.db $82, $34, $84, $2c, $85, $22, $84, $24
	.db $82, $26, $36, $04, $36, $86, $26, $00

	.db $ac, $27, $5d, $1d, $9e, $2d, $ac, $9f

	.db $85, $14, $82, $20, $84, $22, $2c
	.db $1e, $1e, $82, $2c, $2c, $1e, $04

GroundM_P4BData:
	.db $87, $2a, $40, $40, $40, $3a, $36
	.db $82, $34, $2c, $04, $26, $86, $22, $00

	.db $e3, $f7, $f7, $f7, $f5, $f1, $ac, $27, $9e, $9d

	.db $85, $18, $82, $1e, $84, $22, $2a
	.db $22, $22, $82, $2c, $2c, $22, $04

DeathMusData:
	.db $86, $04                                 ; death music share data with fourth part c of ground level music

GroundM_P4CData:
	.db $82, $2a, $36, $04, $36, $87, $36, $34, $30, $86, $2c, $04, $00

	.db $00, $68, $6a, $6c, $45                  ; death music only

	.db $a2, $31, $b0, $f1, $ed, $eb, $a2, $1d, $9c, $95

	.db $86, $04                                 ; death music only

	.db $85, $22, $82, $22, $87, $22, $26, $2a, $84, $2c, $22, $86, $14

; noise data used by fourth part sections
	.db $51, $90, $31, $11, $00

CastleMusData:
	.db $80, $22, $28, $22, $26, $22, $24, $22, $26
	.db $22, $28, $22, $2a, $22, $28, $22, $26
	.db $22, $28, $22, $26, $22, $24, $22, $26
	.db $22, $28, $22, $2a, $22, $28, $22, $26
	.db $20, $26, $20, $24, $20, $26, $20, $28
	.db $20, $26, $20, $28, $20, $26, $20, $24
	.db $20, $26, $20, $24, $20, $26, $20, $28
	.db $20, $26, $20, $28, $20, $26, $20, $24
	.db $28, $30, $28, $32, $28, $30, $28, $2e
	.db $28, $30, $28, $2e, $28, $2c, $28, $2e
	.db $28, $30, $28, $32, $28, $30, $28, $2e
	.db $28, $30, $28, $2e, $28, $2c, $28, $2e, $00

	.db $04, $70, $6e, $6c, $6e, $70, $72, $70, $6e
	.db $70, $6e, $6c, $6e, $70, $72, $70, $6e
	.db $6e, $6c, $6e, $70, $6e, $70, $6e, $6c
	.db $6e, $6c, $6e, $70, $6e, $70, $6e, $6c
	.db $76, $78, $76, $74, $76, $74, $72, $74
	.db $76, $78, $76, $74, $76, $74, $72, $74

	.db $84, $1a, $83, $18, $20, $84, $1e, $83, $1c, $28
	.db $26, $1c, $1a, $1c

GameOverMusData:
	.db $82, $2c, $04, $04, $22, $04, $04, $84, $1c, $87
	.db $26, $2a, $26, $84, $24, $28, $24, $80, $22, $00

	.db $9c, $05, $94, $05, $0d, $9f, $1e, $9c, $98, $9d

	.db $82, $22, $04, $04, $1c, $04, $04, $84, $14
	.db $86, $1e, $80, $16, $80, $14

TimeRunOutMusData:
	.db $81, $1c, $30, $04, $30, $30, $04, $1e, $32, $04, $32, $32
	.db $04, $20, $34, $04, $34, $34, $04, $36, $04, $84, $36, $00

	.db $46, $a4, $64, $a4, $48, $a6, $66, $a6, $4a, $a8, $68, $a8
	.db $6a, $44, $2b

	.db $81, $2a, $42, $04, $42, $42, $04, $2c, $64, $04, $64, $64
	.db $04, $2e, $46, $04, $46, $46, $04, $22, $04, $84, $22

WinLevelMusData:
	.db $87, $04, $06, $0c, $14, $1c, $22, $86, $2c, $22
	.db $87, $04, $60, $0e, $14, $1a, $24, $86, $2c, $24
	.db $87, $04, $08, $10, $18, $1e, $28, $86, $30, $30
	.db $80, $64, $00

	.db $cd, $d5, $dd, $e3, $ed, $f5, $bb, $b5, $cf, $d5
	.db $db, $e5, $ed, $f3, $bd, $b3, $d1, $d9, $df, $e9
	.db $f1, $f7, $bf, $ff, $ff, $ff, $34
	.db $00                                      ; unused byte

	.db $86, $04, $87, $14, $1c, $22, $86, $34, $84, $2c
	.db $04, $04, $04, $87, $14, $1a, $24, $86, $32, $84
	.db $2c, $04, $86, $04, $87, $18, $1e, $28, $86, $36
	.db $87, $30, $30, $30, $80, $2c

; square 2 and triangle use the same data, square 1 is unused
UndergroundMusData:
	.db $82, $14, $2c, $62, $26, $10, $28, $80, $04
	.db $82, $14, $2c, $62, $26, $10, $28, $80, $04
	.db $82, $08, $1e, $5e, $18, $60, $1a, $80, $04
	.db $82, $08, $1e, $5e, $18, $60, $1a, $86, $04
	.db $83, $1a, $18, $16, $84, $14, $1a, $18, $0e, $0c
	.db $16, $83, $14, $20, $1e, $1c, $28, $26, $87
	.db $24, $1a, $12, $10, $62, $0e, $80, $04, $04
	.db $00

; noise data directly follows square 2 here unlike in other songs
WaterMusData:
	.db $82, $18, $1c, $20, $22, $26, $28
	.db $81, $2a, $2a, $2a, $04, $2a, $04, $83, $2a, $82, $22
	.db $86, $34, $32, $34, $81, $04, $22, $26, $2a, $2c, $30
	.db $86, $34, $83, $32, $82, $36, $84, $34, $85, $04, $81, $22
	.db $86, $30, $2e, $30, $81, $04, $22, $26, $2a, $2c, $2e
	.db $86, $30, $83, $22, $82, $36, $84, $34, $85, $04, $81, $22
	.db $86, $3a, $3a, $3a, $82, $3a, $81, $40, $82, $04, $81, $3a
	.db $86, $36, $36, $36, $82, $36, $81, $3a, $82, $04, $81, $36
	.db $86, $34, $82, $26, $2a, $36
	.db $81, $34, $34, $85, $34, $81, $2a, $86, $2c, $00

	.db $84, $90, $b0, $84, $50, $50, $b0, $00

	.db $98, $96, $94, $92, $94, $96, $58, $58, $58, $44
	.db $5c, $44, $9f, $a3, $a1, $a3, $85, $a3, $e0, $a6
	.db $23, $c4, $9f, $9d, $9f, $85, $9f, $d2, $a6, $23
	.db $c4, $b5, $b1, $af, $85, $b1, $af, $ad, $85, $95
	.db $9e, $a2, $aa, $6a, $6a, $6b, $5e, $9d

	.db $84, $04, $04, $82, $22, $86, $22
	.db $82, $14, $22, $2c, $12, $22, $2a, $14, $22, $2c
	.db $1c, $22, $2c, $14, $22, $2c, $12, $22, $2a, $14
	.db $22, $2c, $1c, $22, $2c, $18, $22, $2a, $16, $20
	.db $28, $18, $22, $2a, $12, $22, $2a, $18, $22, $2a
	.db $12, $22, $2a, $14, $22, $2c, $0c, $22, $2c, $14, $22, $34, $12
	.db $22, $30, $10, $22, $2e, $16, $22, $34, $18, $26
	.db $36, $16, $26, $36, $14, $26, $36, $12, $22, $36
	.db $5c, $22, $34, $0c, $22, $22, $81, $1e, $1e, $85, $1e
	.db $81, $12, $86, $14

EndOfCastleMusData:
	.db $81, $2c, $22, $1c, $2c, $22, $1c, $85, $2c, $04
	.db $81, $2e, $24, $1e, $2e, $24, $1e, $85, $2e, $04
	.db $81, $32, $28, $22, $32, $28, $22, $85, $32
	.db $87, $36, $36, $36, $84, $3a, $00

	.db $5c, $54, $4c, $5c, $54, $4c
	.db $5c, $1c, $1c, $5c, $5c, $5c, $5c
	.db $5e, $56, $4e, $5e, $56, $4e
	.db $5e, $1e, $1e, $5e, $5e, $5e, $5e
	.db $62, $5a, $50, $62, $5a, $50
	.db $62, $22, $22, $62, $e7, $e7, $e7, $2b

	.db $86, $14, $81, $14, $80, $14, $14, $81, $14, $14, $14, $14
	.db $86, $16, $81, $16, $80, $16, $16, $81, $16, $16, $16, $16
	.db $81, $28, $22, $1a, $28, $22, $1a, $28, $80, $28, $28
	.db $81, $28, $87, $2c, $2c, $2c, $84, $30

VictoryMusData:
	.db $83, $04, $84, $0c, $83, $62, $10, $84, $12
	.db $83, $1c, $22, $1e, $22, $26, $18, $1e, $04, $1c, $00

	.db $e3, $e1, $e3, $1d, $de, $e0, $23
	.db $ec, $75, $74, $f0, $f4, $f6, $ea, $31, $2d

	.db $83, $12, $14, $04, $18, $1a, $1c, $14
	.db $26, $22, $1e, $1c, $18, $1e, $22, $0c, $14

; unused space
	.db $ff, $ff, $ff

FreqRegLookupTbl:
	.db $00, $88, $00, $2f, $00, $00
	.db $02, $a6, $02, $80, $02, $5c, $02, $3a
	.db $02, $1a, $01, $df, $01, $c4, $01, $ab
	.db $01, $93, $01, $7c, $01, $67, $01, $53
	.db $01, $40, $01, $2e, $01, $1d, $01, $0d
	.db $00, $fe, $00, $ef, $00, $e2, $00, $d5
	.db $00, $c9, $00, $be, $00, $b3, $00, $a9
	.db $00, $a0, $00, $97, $00, $8e, $00, $86
	.db $00, $77, $00, $7e, $00, $71, $00, $54
	.db $00, $64, $00, $5f, $00, $59, $00, $50
	.db $00, $47, $00, $43, $00, $3b, $00, $35
	.db $00, $2a, $00, $23, $04, $75, $03, $57
	.db $02, $f9, $02, $cf, $01, $fc, $00, $6a

MusicLengthLookupTbl:
	.db $05, $0a, $14, $28, $50, $1e, $3c, $02
	.db $04, $08, $10, $20, $40, $18, $30, $0c
	.db $03, $06, $0c, $18, $30, $12, $24, $08
	.db $36, $03, $09, $06, $12, $1b, $24, $0c
	.db $24, $02, $06, $04, $0c, $12, $18, $08
	.db $12, $01, $03, $02, $06, $09, $0c, $04

EndOfCastleMusicEnvData:
	.db $98, $99, $9a, $9b

AreaMusicEnvData:
	.db $90, $94, $94, $95, $95, $96, $97, $98

WaterEventMusEnvData:
	.db $90, $91, $92, $92, $93, $93, $93, $94
	.db $94, $94, $94, $94, $94, $95, $95, $95
	.db $95, $95, $95, $96, $96, $96, $96, $96
	.db $96, $96, $96, $96, $96, $96, $96, $96
	.db $96, $96, $96, $96, $95, $95, $94, $93

BowserFlameEnvData:
	.db $15, $16, $16, $17, $17, $18, $19, $19
	.db $1a, $1a, $1c, $1d, $1d, $1e, $1e, $1f
	.db $1f, $1f, $1f, $1e, $1d, $1c, $1e, $1f
	.db $1f, $1e, $1d, $1c, $1a, $18, $16, $14

BrickShatterEnvData:
	.db $15, $16, $16, $17, $17, $18, $19, $19
	.db $1a, $1a, $1c, $1d, $1d, $1e, $1e, $1f
