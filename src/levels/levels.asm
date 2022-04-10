; GAME LEVELS DATA

WorldAddrOffsets:
	.db World1Areas-AreaAddrOffsets, World2Areas-AreaAddrOffsets
	.db World3Areas-AreaAddrOffsets, World4Areas-AreaAddrOffsets
	.db World5Areas-AreaAddrOffsets, World6Areas-AreaAddrOffsets
	.db World7Areas-AreaAddrOffsets, World8Areas-AreaAddrOffsets

AreaAddrOffsets:
World1Areas:
	.db $25, $29, $c0, $26, $60
World2Areas:
	.db $28, $29, $01, $27, $62
World3Areas:
	.db $24, $35, $20, $63
World4Areas:
	.db $22, $29, $41, $2c, $61
World5Areas:
	.db $2a, $31, $26, $62
World6Areas:
	.db $2e, $23, $2d, $60
World7Areas:
	.db $33, $29, $01, $27, $64
World8Areas:
	.db $30, $32, $21, $65

; bonus area data offsets, included here for comparison purposes
; underground bonus area  - c2
; cloud area 1 (day)      - 2b
; cloud area 2 (night)    - 34
; water area (5-2/6-2)    - 00
; water area (8-4)        - 02
; warp zone area (4-2)    - 2f

EnemyAddrHOffsets:
	.db $1f, $06, $1c, $00

EnemyDataAddrLow:
	.db <E_CastleArea1, <E_CastleArea2, <E_CastleArea3, <E_CastleArea4, <E_CastleArea5, <E_CastleArea6
	.db <E_GroundArea1, <E_GroundArea2, <E_GroundArea3, <E_GroundArea4, <E_GroundArea5, <E_GroundArea6
	.db <E_GroundArea7, <E_GroundArea8, <E_GroundArea9, <E_GroundArea10, <E_GroundArea11, <E_GroundArea12
	.db <E_GroundArea13, <E_GroundArea14, <E_GroundArea15, <E_GroundArea16, <E_GroundArea17, <E_GroundArea18
	.db <E_GroundArea19, <E_GroundArea20, <E_GroundArea21, <E_GroundArea22, <E_UndergroundArea1
	.db <E_UndergroundArea2, <E_UndergroundArea3, <E_WaterArea1, <E_WaterArea2, <E_WaterArea3

EnemyDataAddrHigh:
	.db >E_CastleArea1, >E_CastleArea2, >E_CastleArea3, >E_CastleArea4, >E_CastleArea5, >E_CastleArea6
	.db >E_GroundArea1, >E_GroundArea2, >E_GroundArea3, >E_GroundArea4, >E_GroundArea5, >E_GroundArea6
	.db >E_GroundArea7, >E_GroundArea8, >E_GroundArea9, >E_GroundArea10, >E_GroundArea11, >E_GroundArea12
	.db >E_GroundArea13, >E_GroundArea14, >E_GroundArea15, >E_GroundArea16, >E_GroundArea17, >E_GroundArea18
	.db >E_GroundArea19, >E_GroundArea20, >E_GroundArea21, >E_GroundArea22, >E_UndergroundArea1
	.db >E_UndergroundArea2, >E_UndergroundArea3, >E_WaterArea1, >E_WaterArea2, >E_WaterArea3

AreaDataHOffsets:
	.db $00, $03, $19, $1c

AreaDataAddrLow:
	.db <L_WaterArea1, <L_WaterArea2, <L_WaterArea3, <L_GroundArea1, <L_GroundArea2, <L_GroundArea3
	.db <L_GroundArea4, <L_GroundArea5, <L_GroundArea6, <L_GroundArea7, <L_GroundArea8, <L_GroundArea9
	.db <L_GroundArea10, <L_GroundArea11, <L_GroundArea12, <L_GroundArea13, <L_GroundArea14, <L_GroundArea15
	.db <L_GroundArea16, <L_GroundArea17, <L_GroundArea18, <L_GroundArea19, <L_GroundArea20, <L_GroundArea21
	.db <L_GroundArea22, <L_UndergroundArea1, <L_UndergroundArea2, <L_UndergroundArea3, <L_CastleArea1
	.db <L_CastleArea2, <L_CastleArea3, <L_CastleArea4, <L_CastleArea5, <L_CastleArea6

AreaDataAddrHigh:
	.db >L_WaterArea1, >L_WaterArea2, >L_WaterArea3, >L_GroundArea1, >L_GroundArea2, >L_GroundArea3
	.db >L_GroundArea4, >L_GroundArea5, >L_GroundArea6, >L_GroundArea7, >L_GroundArea8, >L_GroundArea9
	.db >L_GroundArea10, >L_GroundArea11, >L_GroundArea12, >L_GroundArea13, >L_GroundArea14, >L_GroundArea15
	.db >L_GroundArea16, >L_GroundArea17, >L_GroundArea18, >L_GroundArea19, >L_GroundArea20, >L_GroundArea21
	.db >L_GroundArea22, >L_UndergroundArea1, >L_UndergroundArea2, >L_UndergroundArea3, >L_CastleArea1
	.db >L_CastleArea2, >L_CastleArea3, >L_CastleArea4, >L_CastleArea5, >L_CastleArea6


	.include "src/levels/enemies.asm"
	.include "src/levels/objects.asm"
