
; -------------------------------------------------------------------------------------

Start:
	SEI                                          ; pretty standard 6502 type init here
	CLD
	LDA #%00010000                               ; init PPU control register 1
	STA PPU_CTRL_REG1
	LDX #$ff                                     ; reset stack pointer
	TXS
VBlank1:
	LDA PPU_STATUS                               ; wait two frames
	BPL VBlank1
VBlank2:
	LDA PPU_STATUS
	BPL VBlank2
	LDY #ColdBootOffset                          ; load default cold boot pointer
	LDX #$05                                     ; this is where we check for a warm boot
WBootCheck:
	LDA TopScoreDisplay,x                        ; check each score digit in the top score
	CMP #10                                      ; to see if we have a valid digit
	BCS ColdBoot                                 ; if not, give up and proceed with cold boot
	DEX
	BPL WBootCheck
	LDA WarmBootValidation                       ; second checkpoint, check to see if
	CMP #$a5                                     ; another location has a specific value
	BNE ColdBoot
	LDY #WarmBootOffset                          ; if passed both, load warm boot pointer
ColdBoot:
	JSR InitializeMemory                         ; clear memory using pointer in Y
	STA SND_DELTA_REG+1                          ; reset delta counter load register
	STA OperMode                                 ; reset primary mode of operation
	LDA #$a5                                     ; set warm boot flag
	STA WarmBootValidation
	STA PseudoRandomBitReg                       ; set seed for pseudorandom register
	LDA #%00001111
	STA SND_MASTERCTRL_REG                       ; enable all sound channels except dmc
	LDA #%00000110
	STA PPU_CTRL_REG2                            ; turn off clipping for OAM and background
	JSR MoveAllSpritesOffscreen
	JSR InitializeNameTables                     ; initialize both name tables
	INC DisableScreenFlag                        ; set flag to disable screen output
	LDA Mirror_PPU_CTRL_REG1
	ORA #%10000000                               ; enable NMIs
	JSR WritePPUReg1
EndlessLoop:
	JMP EndlessLoop                              ; endless loop, need I say more?

; -------------------------------------------------------------------------------------
; $00 - vram buffer address table low, also used for pseudorandom bit
; $01 - vram buffer address table high

VRAM_AddrTable_Low:
	.db <VRAM_Buffer1, <WaterPaletteData, <GroundPaletteData
	.db <UndergroundPaletteData, <CastlePaletteData, <VRAM_Buffer1_Offset
	.db <VRAM_Buffer2, <VRAM_Buffer2, <BowserPaletteData
	.db <DaySnowPaletteData, <NightSnowPaletteData, <MushroomPaletteData
	.db <MarioThanksMessage, <LuigiThanksMessage, <MushroomRetainerSaved
	.db <PrincessSaved1, <PrincessSaved2, <WorldSelectMessage1
	.db <WorldSelectMessage2

VRAM_AddrTable_High:
	.db >VRAM_Buffer1, >WaterPaletteData, >GroundPaletteData
	.db >UndergroundPaletteData, >CastlePaletteData, >VRAM_Buffer1_Offset
	.db >VRAM_Buffer2, >VRAM_Buffer2, >BowserPaletteData
	.db >DaySnowPaletteData, >NightSnowPaletteData, >MushroomPaletteData
	.db >MarioThanksMessage, >LuigiThanksMessage, >MushroomRetainerSaved
	.db >PrincessSaved1, >PrincessSaved2, >WorldSelectMessage1
	.db >WorldSelectMessage2

VRAM_Buffer_Offset:
	.db <VRAM_Buffer1_Offset, <VRAM_Buffer2_Offset

NonMaskableInterrupt:
	LDA Mirror_PPU_CTRL_REG1                     ; disable NMIs in mirror reg
	AND #%01111111                               ; save all other bits
	STA Mirror_PPU_CTRL_REG1
	AND #%01111110                               ; alter name table address to be $2800
	STA PPU_CTRL_REG1                            ; (essentially $2000) but save other bits
	LDA Mirror_PPU_CTRL_REG2                     ; disable OAM and background display by default
	AND #%11100110
	LDY DisableScreenFlag                        ; get screen disable flag
	BNE ScreenOff                                ; if set, used bits as-is
	LDA Mirror_PPU_CTRL_REG2                     ; otherwise reenable bits and save them
	ORA #%00011110
ScreenOff:
	STA Mirror_PPU_CTRL_REG2                     ; save bits for later but not in register at the moment
	AND #%11100111                               ; disable screen for now
	STA PPU_CTRL_REG2
	LDX PPU_STATUS                               ; reset flip-flop and reset scroll registers to zero
	LDA #$00
	JSR InitScroll
	STA PPU_SPR_ADDR                             ; reset spr-ram address register
	LDA #$02                                     ; perform spr-ram DMA access on $0200-$02ff
	STA SPR_DMA
	LDX VRAM_Buffer_AddrCtrl                     ; load control for pointer to buffer contents
	LDA VRAM_AddrTable_Low,x                     ; set indirect at $00 to pointer
	STA $00
	LDA VRAM_AddrTable_High,x
	STA $01
	JSR UpdateScreen                             ; update screen with buffer contents
	LDY #$00
	LDX VRAM_Buffer_AddrCtrl                     ; check for usage of $0341
	CPX #$06
	BNE InitBuffer
	INY                                          ; get offset based on usage
InitBuffer:
	LDX VRAM_Buffer_Offset,y
	LDA #$00                                     ; clear buffer header at last location
	STA VRAM_Buffer1_Offset,x
	STA VRAM_Buffer1,x
	STA VRAM_Buffer_AddrCtrl                     ; reinit address control to $0301
	LDA Mirror_PPU_CTRL_REG2                     ; copy mirror of $2001 to register
	STA PPU_CTRL_REG2
	JSR SoundEngine                              ; play sound
	JSR ReadJoypads                              ; read joypads
	JSR PauseRoutine                             ; handle pause
	JSR UpdateTopScore
	LDA GamePauseStatus                          ; check for pause status
	LSR
	BCS PauseSkip
	LDA TimerControl                             ; if master timer control not set, decrement
	BEQ DecTimers                                ; all frame and interval timers
	DEC TimerControl
	BNE NoDecTimers
DecTimers:
	LDX #$14                                     ; load end offset for end of frame timers
	DEC IntervalTimerControl                     ; decrement interval timer control,
	BPL DecTimersLoop                            ; if not expired, only frame timers will decrement
	LDA #$14
	STA IntervalTimerControl                     ; if control for interval timers expired,
	LDX #$23                                     ; interval timers will decrement along with frame timers
DecTimersLoop:
	LDA Timers,x                                 ; check current timer
	BEQ SkipExpTimer                             ; if current timer expired, branch to skip,
	DEC Timers,x                                 ; otherwise decrement the current timer
SkipExpTimer:
	DEX                                          ; move onto next timer
	BPL DecTimersLoop                            ; do this until all timers are dealt with
NoDecTimers:
	INC FrameCounter                             ; increment frame counter
PauseSkip:
	LDX #$00
	LDY #$07
	LDA PseudoRandomBitReg                       ; get first memory location of LSFR bytes
	AND #%00000010                               ; mask out all but d1
	STA $00                                      ; save here
	LDA PseudoRandomBitReg+1                     ; get second memory location
	AND #%00000010                               ; mask out all but d1
	EOR $00                                      ; perform exclusive-OR on d1 from first and second bytes
	CLC                                          ; if neither or both are set, carry will be clear
	BEQ RotPRandomBit
	SEC                                          ; if one or the other is set, carry will be set
RotPRandomBit:
	ROR PseudoRandomBitReg,x                     ; rotate carry into d7, and rotate last bit into carry
	INX                                          ; increment to next byte
	DEY                                          ; decrement for loop
	BNE RotPRandomBit
	LDA Sprite0HitDetectFlag                     ; check for flag here
	BEQ SkipSprite0
Sprite0Clr:
	LDA PPU_STATUS                               ; wait for sprite 0 flag to clear, which will
	AND #%01000000                               ; not happen until vblank has ended
	BNE Sprite0Clr
	LDA GamePauseStatus                          ; if in pause mode, do not bother with sprites at all
	LSR
	BCS Sprite0Hit
	JSR MoveSpritesOffscreen
	JSR SpriteShuffler
Sprite0Hit:
	LDA PPU_STATUS                               ; do sprite #0 hit detection
	AND #%01000000
	BEQ Sprite0Hit
	LDY #$14                                     ; small delay, to wait until we hit horizontal blank time
HBlankDelay:
	DEY
	BNE HBlankDelay
SkipSprite0:
	LDA HorizontalScroll                         ; set scroll registers from variables
	STA PPU_SCROLL_REG
	LDA VerticalScroll
	STA PPU_SCROLL_REG
	LDA Mirror_PPU_CTRL_REG1                     ; load saved mirror of $2000
	PHA
	STA PPU_CTRL_REG1
	LDA GamePauseStatus                          ; if in pause mode, do not perform operation mode stuff
	LSR
	BCS SkipMainOper
	JSR OperModeExecutionTree                    ; otherwise do one of many, many possible subroutines
SkipMainOper:
	LDA PPU_STATUS                               ; reset flip-flop
	PLA
	ORA #%10000000                               ; reactivate NMIs
	STA PPU_CTRL_REG1
	RTI                                          ; we are done until the next frame!

; -------------------------------------------------------------------------------------

PauseRoutine:
	LDA OperMode                                 ; are we in victory mode?
	CMP #VictoryModeValue                        ; if so, go ahead
	BEQ ChkPauseTimer
	CMP #GameModeValue                           ; are we in game mode?
	BNE ExitPause                                ; if not, leave
	LDA OperMode_Task                            ; if we are in game mode, are we running game engine?
	CMP #$03
	BNE ExitPause                                ; if not, leave
ChkPauseTimer:
	LDA GamePauseTimer                           ; check if pause timer is still counting down
	BEQ ChkStart
	DEC GamePauseTimer                           ; if so, decrement and leave
	RTS
ChkStart:
	LDA SavedJoypad1Bits                         ; check to see if start is pressed
	AND #Start_Button                            ; on controller 1
	BEQ ClrPauseTimer
	LDA GamePauseStatus                          ; check to see if timer flag is set
	AND #%10000000                               ; and if so, do not reset timer (residual,
	BNE ExitPause                                ; joypad reading routine makes this unnecessary)
	LDA #$2b                                     ; set pause timer
	STA GamePauseTimer
	LDA GamePauseStatus
	TAY
	INY                                          ; set pause sfx queue for next pause mode
	STY PauseSoundQueue
	EOR #%00000001                               ; invert d0 and set d7
	ORA #%10000000
	BNE SetPause                                 ; unconditional branch
ClrPauseTimer:
	LDA GamePauseStatus                          ; clear timer flag if timer is at zero and start button
	AND #%01111111                               ; is not pressed
SetPause:
	STA GamePauseStatus
ExitPause:
	RTS

; -------------------------------------------------------------------------------------
; $00 - used for preset value

SpriteShuffler:
	LDY AreaType                                 ; load level type, likely residual code
	LDA #$28                                     ; load preset value which will put it at
	STA $00                                      ; sprite #10
	LDX #$0e                                     ; start at the end of OAM data offsets
ShuffleLoop:
	LDA SprDataOffset,x                          ; check for offset value against
	CMP $00                                      ; the preset value
	BCC NextSprOffset                            ; if less, skip this part
	LDY SprShuffleAmtOffset                      ; get current offset to preset value we want to add
	CLC
	ADC SprShuffleAmt,y                          ; get shuffle amount, add to current sprite offset
	BCC StrSprOffset                             ; if not exceeded $ff, skip second add
	CLC
	ADC $00                                      ; otherwise add preset value $28 to offset
StrSprOffset:
	STA SprDataOffset,x                          ; store new offset here or old one if branched to here
NextSprOffset:
	DEX                                          ; move backwards to next one
	BPL ShuffleLoop
	LDX SprShuffleAmtOffset                      ; load offset
	INX
	CPX #$03                                     ; check if offset + 1 goes to 3
	BNE SetAmtOffset                             ; if offset + 1 not 3, store
	LDX #$00                                     ; otherwise, init to 0
SetAmtOffset:
	STX SprShuffleAmtOffset
	LDX #$08                                     ; load offsets for values and storage
	LDY #$02
SetMiscOffset:
	LDA SprDataOffset+5,y                        ; load one of three OAM data offsets
	STA Misc_SprDataOffset-2,x                   ; store first one unmodified, but
	CLC                                          ; add eight to the second and eight
	ADC #$08                                     ; more to the third one
	STA Misc_SprDataOffset-1,x                   ; note that due to the way X is set up,
	CLC                                          ; this code loads into the misc sprite offsets
	ADC #$08
	STA Misc_SprDataOffset,x
	DEX
	DEX
	DEX
	DEY
	BPL SetMiscOffset                            ; do this until all misc spr offsets are loaded
	RTS

; -------------------------------------------------------------------------------------

OperModeExecutionTree:
	LDA OperMode                                 ; this is the heart of the entire program,
	JSR JumpEngine                               ; most of what goes on starts here

	.dw TitleScreenMode
	.dw GameMode
	.dw VictoryMode
	.dw GameOverMode

; -------------------------------------------------------------------------------------

MoveAllSpritesOffscreen:
	LDY #$00                                     ; this routine moves all sprites off the screen
	.db $2c                                      ; BIT instruction opcode

MoveSpritesOffscreen:
	LDY #$04                                     ; this routine moves all but sprite 0
	LDA #$f8                                     ; off the screen
SprInitLoop:
	STA Sprite_Y_Position,y                      ; write 248 into OAM data's Y coordinate
	INY                                          ; which will move it off the screen
	INY
	INY
	INY
	BNE SprInitLoop
	RTS

; -------------------------------------------------------------------------------------

TitleScreenMode:
	LDA OperMode_Task
	JSR JumpEngine

	.dw InitializeGame
	.dw ScreenRoutines
	.dw PrimaryGameSetup
	.dw GameMenuRoutine

; -------------------------------------------------------------------------------------

WSelectBufferTemplate:
	.db $08, $20, $73, $03, $00, $28, $00, $00

GameMenuRoutine:
	LDY #$00
	LDA SavedJoypad1Bits                         ; check to see if either player pressed
	ORA SavedJoypad2Bits                         ; only the start button (either joypad)
	CMP #Start_Button
	BEQ StartGame
	CMP #A_Button+Start_Button                   ; check to see if A + start was pressed
	BNE ChkSelect                                ; if not, branch to check select button
StartGame:
	JMP ChkContinue                              ; if either start or A + start, execute here
ChkSelect:
	;LDX DemoTimer                                ; otherwise check demo timer
	;BNE ChkWorldSel                              ; if demo timer not expired, branch to check world selection
	;STA SelectTimer                              ; set controller bits here if running demo
	;JSR DemoEngine                               ; run through the demo actions
	;BCS ResetTitle                               ; if carry flag set, demo over, thus branch
	;JMP RunDemo                                  ; otherwise, run game engine for demo

ChkWorldSel:
	LDY #0
	LDA JoypadPressed
	CMP #B_Button                                ; if so, check to see if the B button was pressed
	BNE +
	LDX WorldSelectNumber                        ; increment world select number
	INX
	TXA
	AND #%00000111                               ; mask out higher bits
	STA WorldSelectNumber                        ; store as current world select number
	INY

+	LDA JoypadPressed
	CMP #A_Button
	BNE +                              ; note this will not be run if world selection is disabled
	LDX LevelNumber                        ; increment world select number
	INX
	TXA
	AND #%00000011                               ; mask out higher bits
	STA LevelNumber                        ; store as current world select number
	INY

+	CPY #00
	BEQ NullJoypad
	JSR GoContinue

	LDX #0
UpdateShroom:
	LDA WSelectBufferTemplate,x                  ; write template for world select in vram buffer
	STA VRAM_Buffer1-1,x                         ; do this until all bytes are written
	INX
	CPX #$08
	BMI UpdateShroom
	LDY WorldNumber                              ; get world number from variable and increment for
	INY                                          ; proper display, and put in blank byte before
	STY VRAM_Buffer1+3                           ; null terminator
	LDY LevelNumber                              ; get world number from variable and increment for
	INY                                          ; proper display, and put in blank byte before
	STY VRAM_Buffer1+5                           ; null terminator

NullJoypad:
	LDA #$00                                     ; clear joypad bits for player 1
	STA SavedJoypad1Bits
RunDemo:
	JSR GameCoreRoutine                          ; run game engine
	LDA GameEngineSubroutine                     ; check to see if we're running lose life routine
	CMP #$06
	BNE ExitMenu                                 ; if not, do not do all the resetting below
ResetTitle:
	LDA #$00                                     ; reset game modes, disable
	STA OperMode                                 ; sprite 0 check and disable
	STA OperMode_Task                            ; screen output
	STA Sprite0HitDetectFlag
	INC DisableScreenFlag
	RTS
ChkContinue:
	LDY DemoTimer                                ; if timer for demo has expired, reset modes
	BEQ ResetTitle
	ASL                                          ; check to see if A button was also pushed
	BCC StartWorld1                              ; if not, don't load continue function's world number
	LDA ContinueWorld                            ; load previously saved world number for secret
	JSR GoContinue                               ; continue function when pressing A + start
StartWorld1:
	JSR LoadAreaPointer
	INC Hidden1UpFlag                            ; set 1-up box flag for both players
	INC OffScr_Hidden1UpFlag
	INC FetchNewGameTimerFlag                    ; set fetch new game timer flag
	INC OperMode                                 ; set next game mode
	LDA WorldSelectEnableFlag                    ; if world select flag is on, then primary
	STA PrimaryHardMode                          ; hard mode must be on as well
	LDA #$00
	STA OperMode_Task                            ; set game mode here, and clear demo timer
	STA DemoTimer
	LDX #$17
	LDA #$00
InitScores:
	STA ScoreAndCoinDisplay,x                    ; clear player scores and coin displays
	DEX
	BPL InitScores
ExitMenu:
	RTS
GoContinue:
	LDA WorldSelectNumber
	STA WorldNumber                              ; start both players at the first area
	ASL
	ASL
	CLC
	ADC LevelNumber
	TAX
	LDA WorldLevelToArea,X
	STA AreaNumber
	RTS

; -------------------------------------------------------------------------------------

MushroomIconData:
	.db $07, $22, $49, $83, $ce, $24, $24, $00

DrawMushroomIcon:
	LDY #$07                                     ; read eight bytes to be read by transfer routine
IconDataRead:
	LDA MushroomIconData,y                       ; note that the default position is set for a
	STA VRAM_Buffer1-1,y                         ; 1-player game
	DEY
	BPL IconDataRead
	LDA NumberOfPlayers                          ; check number of players
	BEQ ExitIcon                                 ; if set to 1-player game, we're done
	LDA #$24                                     ; otherwise, load blank tile in 1-player position
	STA VRAM_Buffer1+3
	LDA #$ce                                     ; then load shroom icon tile in 2-player position
	STA VRAM_Buffer1+5
ExitIcon:
	RTS

; -------------------------------------------------------------------------------------

DemoActionData:
	.db $01, $80, $02, $81, $41, $80, $01
	.db $42, $c2, $02, $80, $41, $c1, $41, $c1
	.db $01, $c1, $01, $02, $80, $00

DemoTimingData:
	.db $9b, $10, $18, $05, $2c, $20, $24
	.db $15, $5a, $10, $20, $28, $30, $20, $10
	.db $80, $20, $30, $30, $01, $ff, $00

DemoEngine:
	LDX DemoAction                               ; load current demo action
	LDA DemoActionTimer                          ; load current action timer
	BNE DoAction                                 ; if timer still counting down, skip
	INX
	INC DemoAction                               ; if expired, increment action, X, and
	SEC                                          ; set carry by default for demo over
	LDA DemoTimingData-1,x                       ; get next timer
	STA DemoActionTimer                          ; store as current timer
	BEQ DemoOver                                 ; if timer already at zero, skip
DoAction:
	LDA DemoActionData-1,x                       ; get and perform action (current or next)
	STA SavedJoypad1Bits
	DEC DemoActionTimer                          ; decrement action timer
	CLC                                          ; clear carry if demo still going
DemoOver:
	RTS

; -------------------------------------------------------------------------------------

VictoryMode:
	JSR VictoryModeSubroutines                   ; run victory mode subroutines
	LDA OperMode_Task                            ; get current task of victory mode
	BEQ AutoPlayer                               ; if on bridge collapse, skip enemy processing
	LDX #$00
	STX ObjectOffset                             ; otherwise reset enemy object offset
	JSR EnemiesAndLoopsCore                      ; and run enemy code
AutoPlayer:
	JSR RelativePlayerPosition                   ; get player's relative coordinates
	JMP PlayerGfxHandler                         ; draw the player, then leave

VictoryModeSubroutines:
	LDA OperMode_Task
	JSR JumpEngine

	.dw BridgeCollapse
	.dw SetupVictoryMode
	.dw PlayerVictoryWalk
	.dw PrintVictoryMessages
	.dw PlayerEndWorld

; -------------------------------------------------------------------------------------

SetupVictoryMode:
	LDX ScreenRight_PageLoc                      ; get page location of right side of screen
	INX                                          ; increment to next page
	STX DestinationPageLoc                       ; store here
	LDA #EndOfCastleMusic
	STA EventMusicQueue                          ; play win castle music
	JMP IncModeTask_B                            ; jump to set next major task in victory mode

; -------------------------------------------------------------------------------------

PlayerVictoryWalk:
	LDY #$00                                     ; set value here to not walk player by default
	STY VictoryWalkControl
	LDA Player_PageLoc                           ; get player's page location
	CMP DestinationPageLoc                       ; compare with destination page location
	BNE PerformWalk                              ; if page locations don't match, branch
	LDA Player_X_Position                        ; otherwise get player's horizontal position
	CMP #$60                                     ; compare with preset horizontal position
	BCS DontWalk                                 ; if still on other page, branch ahead
PerformWalk:
	INC VictoryWalkControl                       ; otherwise increment value and Y
	INY                                          ; note Y will be used to walk the player
DontWalk:
	TYA                                          ; put contents of Y in A and
	JSR AutoControlPlayer                        ; use A to move player to the right or not
	LDA ScreenLeft_PageLoc                       ; check page location of left side of screen
	CMP DestinationPageLoc                       ; against set value here
	BEQ ExitVWalk                                ; branch if equal to change modes if necessary
	LDA ScrollFractional
	CLC                                          ; do fixed point math on fractional part of scroll
	ADC #$80
	STA ScrollFractional                         ; save fractional movement amount
	LDA #$01                                     ; set 1 pixel per frame
	ADC #$00                                     ; add carry from previous addition
	TAY                                          ; use as scroll amount
	JSR ScrollScreen                             ; do sub to scroll the screen
	JSR UpdScrollVar                             ; do another sub to update screen and scroll variables
	INC VictoryWalkControl                       ; increment value to stay in this routine
ExitVWalk:
	LDA VictoryWalkControl                       ; load value set here
	BEQ IncModeTask_A                            ; if zero, branch to change modes
	RTS                                          ; otherwise leave

; -------------------------------------------------------------------------------------

PrintVictoryMessages:
	LDA SecondaryMsgCounter                      ; load secondary message counter
	BNE IncMsgCounter                            ; if set, branch to increment message counters
	LDA PrimaryMsgCounter                        ; otherwise load primary message counter
	BEQ ThankPlayer                              ; if set to zero, branch to print first message
	CMP #$09                                     ; if at 9 or above, branch elsewhere (this comparison
	BCS IncMsgCounter                            ; is residual code, counter never reaches 9)
	LDY WorldNumber                              ; check world number
	CPY #World8
	BNE MRetainerMsg                             ; if not at world 8, skip to next part
	CMP #$03                                     ; check primary message counter again
	BCC IncMsgCounter                            ; if not at 3 yet (world 8 only), branch to increment
	SBC #$01                                     ; otherwise subtract one
	JMP ThankPlayer                              ; and skip to next part
MRetainerMsg:
	CMP #$02                                     ; check primary message counter
	BCC IncMsgCounter                            ; if not at 2 yet (world 1-7 only), branch
ThankPlayer:
	TAY                                          ; put primary message counter into Y
	BNE SecondPartMsg                            ; if counter nonzero, skip this part, do not print first message
	LDA CurrentPlayer                            ; otherwise get player currently on the screen
	BEQ EvalForMusic                             ; if mario, branch
	INY                                          ; otherwise increment Y once for luigi and
	BNE EvalForMusic                             ; do an unconditional branch to the same place
SecondPartMsg:
	INY                                          ; increment Y to do world 8's message
	LDA WorldNumber
	CMP #World8                                  ; check world number
	BEQ EvalForMusic                             ; if at world 8, branch to next part
	DEY                                          ; otherwise decrement Y for world 1-7's message
	CPY #$04                                     ; if counter at 4 (world 1-7 only)
	BCS SetEndTimer                              ; branch to set victory end timer
	CPY #$03                                     ; if counter at 3 (world 1-7 only)
	BCS IncMsgCounter                            ; branch to keep counting
EvalForMusic:
	CPY #$03                                     ; if counter not yet at 3 (world 8 only), branch
	BNE PrintMsg                                 ; to print message only (note world 1-7 will only
	LDA #VictoryMusic                            ; reach this code if counter = 0, and will always branch)
	STA EventMusicQueue                          ; otherwise load victory music first (world 8 only)
PrintMsg:
	TYA                                          ; put primary message counter in A
	CLC                                          ; add $0c or 12 to counter thus giving an appropriate value,
	ADC #$0c                                     ; ($0c-$0d = first), ($0e = world 1-7's), ($0f-$12 = world 8's)
	STA VRAM_Buffer_AddrCtrl                     ; write message counter to vram address controller
IncMsgCounter:
	LDA SecondaryMsgCounter
	CLC
	ADC #$04                                     ; add four to secondary message counter
	STA SecondaryMsgCounter
	LDA PrimaryMsgCounter
	ADC #$00                                     ; add carry to primary message counter
	STA PrimaryMsgCounter
	CMP #$07                                     ; check primary counter one more time
SetEndTimer:
	BCC ExitMsgs                                 ; if not reached value yet, branch to leave
	LDA #$06
	STA WorldEndTimer                            ; otherwise set world end timer
IncModeTask_A:
	INC OperMode_Task                            ; move onto next task in mode
ExitMsgs:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------

PlayerEndWorld:
	LDA WorldEndTimer                            ; check to see if world end timer expired
	BNE EndExitOne                               ; branch to leave if not
	LDY WorldNumber                              ; check world number
	CPY #World8                                  ; if on world 8, player is done with game,
	BCS EndChkBButton                            ; thus branch to read controller
	LDA #$00
	STA AreaNumber                               ; otherwise initialize area number used as offset
	STA LevelNumber                              ; and level number control to start at area 1
	STA OperMode_Task                            ; initialize secondary mode of operation
	INC WorldNumber                              ; increment world number to move onto the next world
	JSR LoadAreaPointer                          ; get area address offset for the next area
	INC FetchNewGameTimerFlag                    ; set flag to load game timer from header
	LDA #GameModeValue
	STA OperMode                                 ; set mode of operation to game mode
EndExitOne:
	RTS                                          ; and leave
EndChkBButton:
	LDA SavedJoypad1Bits
	ORA SavedJoypad2Bits                         ; check to see if B button was pressed on
	AND #B_Button                                ; either controller
	BEQ EndExitTwo                               ; branch to leave if not
	LDA #$01                                     ; otherwise set world selection flag
	STA WorldSelectEnableFlag
	LDA #$ff                                     ; remove onscreen player's lives
	STA NumberofLives
	JSR TerminateGame                            ; do sub to continue other player or end game
EndExitTwo:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------

; data is used as tiles for numbers
; that appear when you defeat enemies
FloateyNumTileData:
	.db $ff, $ff                                 ; dummy
	.db $f6, $fb                                 ; "100"
	.db $f7, $fb                                 ; "200"
	.db $f8, $fb                                 ; "400"
	.db $f9, $fb                                 ; "500"
	.db $fa, $fb                                 ; "800"
	.db $f6, $50                                 ; "1000"
	.db $f7, $50                                 ; "2000"
	.db $f8, $50                                 ; "4000"
	.db $f9, $50                                 ; "5000"
	.db $fa, $50                                 ; "8000"
	.db $f6, $fd                                 ; "10 K"

; high nybble is digit number, low nybble is number to
; add to the digit of the player's score
ScoreUpdateData:
	.db $ff                                      ; dummy
	.db $41, $42, $44, $45, $48
	.db $31, $32, $34, $35, $38, $21

FloateyNumbersRoutine:
	LDA FloateyNum_Control,x                     ; load control for floatey number
	BEQ EndExitOne                               ; if zero, branch to leave
	CMP #$0b                                     ; if less than $0b, branch
	BCC ChkNumTimer
	LDA #$0b                                     ; otherwise set to $0b, thus keeping
	STA FloateyNum_Control,x                     ; it in range
ChkNumTimer:
	TAY                                          ; use as Y
	LDA FloateyNum_Timer,x                       ; check value here
	BNE DecNumTimer                              ; if nonzero, branch ahead
	STA FloateyNum_Control,x                     ; initialize floatey number control and leave
	RTS
DecNumTimer:
	DEC FloateyNum_Timer,x                       ; decrement value here
	CMP #$2b                                     ; if not reached a certain point, branch
	BNE ChkTallEnemy
	;CPY #$0b                                     ; check offset for $0b
	;BNE LoadNumTiles                             ; branch ahead if not found
	;INC NumberofLives                            ; give player one extra life (1-up)
	;LDA #Sfx_ExtraLife
	;STA Square2SoundQueue                        ; and play the 1-up sound
LoadNumTiles:
	LDA ScoreUpdateData,y                        ; load point value here
	LSR                                          ; move high nybble to low
	LSR
	LSR
	LSR
	TAX                                          ; use as X offset, essentially the digit
	LDA ScoreUpdateData,y                        ; load again and this time
	AND #%00001111                               ; mask out the high nybble
	STA DigitModifier,x                          ; store as amount to add to the digit
	JSR AddToScore                               ; update the score accordingly
ChkTallEnemy:
	LDY Enemy_SprDataOffset,x                    ; get OAM data offset for enemy object
	LDA Enemy_ID,x                               ; get enemy object identifier
	CMP #Spiny
	BEQ FloateyPart                              ; branch if spiny
	CMP #PiranhaPlant
	BEQ FloateyPart                              ; branch if piranha plant
	CMP #HammerBro
	BEQ GetAltOffset                             ; branch elsewhere if hammer bro
	CMP #GreyCheepCheep
	BEQ FloateyPart                              ; branch if cheep-cheep of either color
	CMP #RedCheepCheep
	BEQ FloateyPart
	CMP #TallEnemy
	BCS GetAltOffset                             ; branch elsewhere if enemy object => $09
	LDA Enemy_State,x
	CMP #$02                                     ; if enemy state defeated or otherwise
	BCS FloateyPart                              ; $02 or greater, branch beyond this part
GetAltOffset:
	LDX SprDataOffset_Ctrl                       ; load some kind of control bit
	LDY Alt_SprDataOffset,x                      ; get alternate OAM data offset
	LDX ObjectOffset                             ; get enemy object offset again
FloateyPart:
	LDA FloateyNum_Y_Pos,x                       ; get vertical coordinate for
	CMP #$18                                     ; floatey number, if coordinate in the
	BCC SetupNumSpr                              ; status bar, branch
	SBC #$01
	STA FloateyNum_Y_Pos,x                       ; otherwise subtract one and store as new
SetupNumSpr:
	LDA FloateyNum_Y_Pos,x                       ; get vertical coordinate
	SBC #$08                                     ; subtract eight and dump into the
	JSR DumpTwoSpr                               ; left and right sprite's Y coordinates
	LDA FloateyNum_X_Pos,x                       ; get horizontal coordinate
	STA Sprite_X_Position,y                      ; store into X coordinate of left sprite
	CLC
	ADC #$08                                     ; add eight pixels and store into X
	STA Sprite_X_Position+4,y                    ; coordinate of right sprite
	LDA #$02
	STA Sprite_Attributes,y                      ; set palette control in attribute bytes
	STA Sprite_Attributes+4,y                    ; of left and right sprites
	LDA FloateyNum_Control,x
	ASL                                          ; multiply our floatey number control by 2
	TAX                                          ; and use as offset for look-up table
	LDA FloateyNumTileData,x
	STA Sprite_Tilenumber,y                      ; display first half of number of points
	LDA FloateyNumTileData+1,x
	STA Sprite_Tilenumber+4,y                    ; display the second half
	LDX ObjectOffset                             ; get enemy object offset and leave
	RTS

; -------------------------------------------------------------------------------------

ScreenRoutines:
	LDA ScreenRoutineTask                        ; run one of the following subroutines
	JSR JumpEngine

	.dw InitScreen
	.dw SetupIntermediate
	.dw WriteTopStatusLine
	.dw WriteBottomStatusLine
	.dw DisplayTimeUp
	.dw ResetSpritesAndScreenTimer
	.dw DisplayIntermediate
	.dw ResetSpritesAndScreenTimer
	.dw AreaParserTaskControl
	.dw GetAreaPalette
	.dw GetBackgroundColor
	.dw GetAlternatePalette1
	.dw DrawTitleScreen
	.dw ClearBuffersDrawIcon
	.dw WriteTopScore

; -------------------------------------------------------------------------------------

InitScreen:
	JSR MoveAllSpritesOffscreen                  ; initialize all sprites including sprite #0
	JSR InitializeNameTables                     ; and erase both name and attribute tables
	LDA OperMode
	BEQ NextSubtask                              ; if mode still 0, do not load
	LDX #$03                                     ; into buffer pointer
	JMP SetVRAMAddr_A

; -------------------------------------------------------------------------------------

SetupIntermediate:
	LDA BackgroundColorCtrl                      ; save current background color control
	PHA                                          ; and player status to stack
	LDA PlayerStatus
	PHA
	LDA #$00                                     ; set background color to black
	STA PlayerStatus                             ; and player status to not fiery
	LDA #$02                                     ; this is the ONLY time background color control
	STA BackgroundColorCtrl                      ; is set to less than 4
	JSR GetPlayerColors
	PLA                                          ; we only execute this routine for
	STA PlayerStatus                             ; the intermediate lives display
	PLA                                          ; and once we're done, we return bg
	STA BackgroundColorCtrl                      ; color ctrl and player status from stack
	JMP IncSubtask                               ; then move onto the next task

; -------------------------------------------------------------------------------------

AreaPalette:
	.db $01, $02, $03, $04

GetAreaPalette:
	LDY AreaType                                 ; select appropriate palette to load
	LDX AreaPalette,y                            ; based on area type
SetVRAMAddr_A:
	STX VRAM_Buffer_AddrCtrl                     ; store offset into buffer control
NextSubtask:
	JMP IncSubtask                               ; move onto next task

; -------------------------------------------------------------------------------------
; $00 - used as temp counter in GetPlayerColors

BGColorCtrl_Addr:
	.db $00, $09, $0a, $04

BackgroundColors:
	.db $22, $22, $0f, $0f                       ; used by area type if bg color ctrl not set
	.db $0f, $22, $0f, $0f                       ; used by background color control if set

PlayerColors:
	.db $22, $16, $27, $18                       ; mario's colors
	.db $22, $30, $27, $19                       ; luigi's colors
	.db $22, $37, $27, $16                       ; fiery (used by both)

GetBackgroundColor:
	LDY BackgroundColorCtrl                      ; check background color control
	BEQ NoBGColor                                ; if not set, increment task and fetch palette
	LDA BGColorCtrl_Addr-4,y                     ; put appropriate palette into vram
	STA VRAM_Buffer_AddrCtrl                     ; note that if set to 5-7, $0301 will not be read
NoBGColor:
	INC ScreenRoutineTask                        ; increment to next subtask and plod on through

GetPlayerColors:
	LDX VRAM_Buffer1_Offset                      ; get current buffer offset
	LDY #$00
	LDA CurrentPlayer                            ; check which player is on the screen
	BEQ ChkFiery
	LDY #$04                                     ; load offset for luigi
ChkFiery:
	LDA PlayerStatus                             ; check player status
	CMP #$02
	BNE StartClrGet                              ; if fiery, load alternate offset for fiery player
	LDY #$08
StartClrGet:
	LDA #$03                                     ; do four colors
	STA $00
ClrGetLoop:
	LDA PlayerColors,y                           ; fetch player colors and store them
	STA VRAM_Buffer1+3,x                         ; in the buffer
	INY
	INX
	DEC $00
	BPL ClrGetLoop
	LDX VRAM_Buffer1_Offset                      ; load original offset from before
	LDY BackgroundColorCtrl                      ; if this value is four or greater, it will be set
	BNE SetBGColor                               ; therefore use it as offset to background color
	LDY AreaType                                 ; otherwise use area type bits from area offset as offset
SetBGColor:
	LDA BackgroundColors,y                       ; to background color instead
	STA VRAM_Buffer1+3,x
	LDA #$3f                                     ; set for sprite palette address
	STA VRAM_Buffer1,x                           ; save to buffer
	LDA #$10
	STA VRAM_Buffer1+1,x
	LDA #$04                                     ; write length byte to buffer
	STA VRAM_Buffer1+2,x
	LDA #$00                                     ; now the null terminator
	STA VRAM_Buffer1+7,x
	TXA                                          ; move the buffer pointer ahead 7 bytes
	CLC                                          ; in case we want to write anything else later
	ADC #$07
SetVRAMOffset:
	STA VRAM_Buffer1_Offset                      ; store as new vram buffer offset
	RTS

; -------------------------------------------------------------------------------------

GetAlternatePalette1:
	LDA AreaStyle                                ; check for mushroom level style
	CMP #$01
	BNE NoAltPal
	LDA #$0b                                     ; if found, load appropriate palette
SetVRAMAddr_B:
	STA VRAM_Buffer_AddrCtrl
NoAltPal:
	JMP IncSubtask                               ; now onto the next task

; -------------------------------------------------------------------------------------

WriteTopStatusLine:
	LDA #$00                                     ; select main status bar
	JSR WriteGameText                            ; output it
	JMP IncSubtask                               ; onto the next task

; -------------------------------------------------------------------------------------

WriteBottomStatusLine:
	JSR GetSBNybbles                             ; write player's score and coin tally to screen
	LDX VRAM_Buffer1_Offset
	LDA #$20                                     ; write address for world-area number on screen
	STA VRAM_Buffer1,x
	LDA #$73
	STA VRAM_Buffer1+1,x
	LDA #$03                                     ; write length for it
	STA VRAM_Buffer1+2,x
	LDY WorldNumber                              ; first the world number
	INY
	TYA
	STA VRAM_Buffer1+3,x
	LDA #$28                                     ; next the dash
	STA VRAM_Buffer1+4,x
	LDY LevelNumber                              ; next the level number
	INY                                          ; increment for proper number display
	TYA
	STA VRAM_Buffer1+5,x
	LDA #$00                                     ; put null terminator on
	STA VRAM_Buffer1+6,x
	TXA                                          ; move the buffer offset up by 6 bytes
	CLC
	ADC #$06
	STA VRAM_Buffer1_Offset
	JMP IncSubtask

; -------------------------------------------------------------------------------------

DisplayTimeUp:
	LDA GameTimerExpiredFlag                     ; if game timer not expired, increment task
	BEQ NoTimeUp                                 ; control 2 tasks forward, otherwise, stay here
	LDA #$00
	STA GameTimerExpiredFlag                     ; reset timer expiration flag
	LDA #$02                                     ; output time-up screen to buffer
	JMP OutputInter
NoTimeUp:
	INC ScreenRoutineTask                        ; increment control task 2 tasks forward
	JMP IncSubtask

; -------------------------------------------------------------------------------------

DisplayIntermediate:
	LDA OperMode                                 ; check primary mode of operation
	BEQ NoInter                                  ; if in title screen mode, skip this
	CMP #GameOverModeValue                       ; are we in game over mode?
	BEQ GameOverInter                            ; if so, proceed to display game over screen
	LDA AltEntranceControl                       ; otherwise check for mode of alternate entry
	BNE NoInter                                  ; and branch if found
	LDY AreaType                                 ; check if we are on castle level
	CPY #$03                                     ; and if so, branch (possibly residual)
	BEQ PlayerInter
	LDA DisableIntermediate                      ; if this flag is set, skip intermediate lives display
	BNE NoInter                                  ; and jump to specific task, otherwise
PlayerInter:
	JSR DrawPlayer_Intermediate                  ; put player in appropriate place for
	LDA #$01                                     ; lives display, then output lives display to buffer
OutputInter:
	JSR WriteGameText
	JSR ResetScreenTimer
	LDA #$00
	STA DisableScreenFlag                        ; reenable screen output
	RTS
GameOverInter:
	LDA #$12                                     ; set screen timer
	STA ScreenTimer
	LDA #$03                                     ; output game over screen to buffer
	JSR WriteGameText
	JMP IncModeTask_B
NoInter:
	LDA #$08                                     ; set for specific task and leave
	STA ScreenRoutineTask
	RTS

; -------------------------------------------------------------------------------------

AreaParserTaskControl:
	INC DisableScreenFlag                        ; turn off screen
TaskLoop:
	JSR AreaParserTaskHandler                    ; render column set of current area
	LDA AreaParserTaskNum                        ; check number of tasks
	BNE TaskLoop                                 ; if tasks still not all done, do another one
	DEC ColumnSets                               ; do we need to render more column sets?
	BPL OutputCol
	INC ScreenRoutineTask                        ; if not, move on to the next task
OutputCol:
	LDA #$06                                     ; set vram buffer to output rendered column set
	STA VRAM_Buffer_AddrCtrl                     ; on next NMI
	RTS

; -------------------------------------------------------------------------------------

; $00 - vram buffer address table low
; $01 - vram buffer address table high

DrawTitleScreen:
	LDA OperMode                                 ; are we in title screen mode?
	BNE IncModeTask_B                            ; if not, exit
	LDA #>TitleScreenDataOffset                  ; load address $1ec0 into
	STA PPU_ADDRESS                              ; the vram address register
	LDA #<TitleScreenDataOffset
	STA PPU_ADDRESS
	LDA #$03                                     ; put address $0300 into
	STA $01                                      ; the indirect at $00
	LDY #$00
	STY $00
	LDA PPU_DATA                                 ; do one garbage read
OutputTScr:
	LDA PPU_DATA                                 ; get title screen from chr-rom
	STA ($00),y                                  ; store 256 bytes into buffer
	INY
	BNE ChkHiByte                                ; if not past 256 bytes, do not increment
	INC $01                                      ; otherwise increment high byte of indirect
ChkHiByte:
	LDA $01                                      ; check high byte?
	CMP #$04                                     ; at $0400?
	BNE OutputTScr                               ; if not, loop back and do another
	CPY #$3a                                     ; check if offset points past end of data
	BCC OutputTScr                               ; if not, loop back and do another
	LDA #$05                                     ; set buffer transfer control to $0300,
	JMP SetVRAMAddr_B                            ; increment task and exit

; -------------------------------------------------------------------------------------

ClearBuffersDrawIcon:
	LDA OperMode                                 ; check game mode
	BNE IncModeTask_B                            ; if not title screen mode, leave
	LDX #$00                                     ; otherwise, clear buffer space
TScrClear:
	STA VRAM_Buffer1-1,x
	STA VRAM_Buffer1-1+$100,x
	DEX
	BNE TScrClear
	JSR DrawMushroomIcon                         ; draw player select icon
IncSubtask:
	INC ScreenRoutineTask                        ; move onto next task
	RTS

; -------------------------------------------------------------------------------------

WriteTopScore:
	LDA #$fa                                     ; run display routine to display top score on title
	JSR UpdateNumber
IncModeTask_B:
	INC OperMode_Task                            ; move onto next mode
	RTS

; -------------------------------------------------------------------------------------

GameText:
TopStatusBarLine:
	.db $20, $43, $05, $16, $0a, $1b, $12, $18   ; "MARIO"
	.db $20, $52, $0b, $20, $18, $1b, $15, $0d   ; "WORLD  TIME"
	.db $24, $24, $1d, $12, $16, $0e
	.db $20, $68, $05, $00, $24, $24, $2e, $29   ; score trailing digit and coin display
	.db $23, $c0, $7f, $aa                       ; attribute table data, clears name table 0 to palette 2
	.db $23, $c2, $01, $ea                       ; attribute table data, used for coin icon in status bar
	.db $ff                                      ; end of data block

WorldLivesDisplay:
	.db $21, $cd, $07, $24, $24                  ; cross with spaces used on
	.db $29, $24, $24, $24, $24                  ; lives display
	.db $21, $4b, $09, $20, $18                  ; "WORLD  - " used on lives display
	.db $1b, $15, $0d, $24, $24, $28, $24
	.db $22, $0c, $47, $24                       ; possibly used to clear time up
	.db $ff

TwoPlayerTimeUp:
	.db $21, $cd, $05, $16, $0a, $1b, $12, $18   ; "MARIO"
OnePlayerTimeUp:
	.db $22, $0c, $07, $1d, $12, $16, $0e, $24, $1e, $19  ; "TIME UP"
	.db $ff

TwoPlayerGameOver:
	.db $21, $cd, $05, $16, $0a, $1b, $12, $18   ; "MARIO"
OnePlayerGameOver:
	.db $22, $0b, $09, $10, $0a, $16, $0e, $24   ; "GAME OVER"
	.db $18, $1f, $0e, $1b
	.db $ff

WarpZoneWelcome:
	.db $25, $84, $15, $20, $0e, $15, $0c, $18, $16  ; "WELCOME TO WARP ZONE!"
	.db $0e, $24, $1d, $18, $24, $20, $0a, $1b, $19
	.db $24, $23, $18, $17, $0e, $2b
	.db $26, $25, $01, $24                       ; placeholder for left pipe
	.db $26, $2d, $01, $24                       ; placeholder for middle pipe
	.db $26, $35, $01, $24                       ; placeholder for right pipe
	.db $27, $d9, $46, $aa                       ; attribute data
	.db $27, $e1, $45, $aa
	.db $ff

LuigiName:
	.db $15, $1e, $12, $10, $12                  ; "LUIGI", no address or length

WarpZoneNumbers:
	.db $04, $03, $02, $00                       ; warp zone numbers, note spaces on middle
	.db $24, $05, $24, $00                       ; zone, partly responsible for
	.db $08, $07, $06, $00                       ; the minus world

GameTextOffsets:
	.db TopStatusBarLine-GameText, TopStatusBarLine-GameText
	.db WorldLivesDisplay-GameText, WorldLivesDisplay-GameText
	.db TwoPlayerTimeUp-GameText, OnePlayerTimeUp-GameText
	.db TwoPlayerGameOver-GameText, OnePlayerGameOver-GameText
	.db WarpZoneWelcome-GameText, WarpZoneWelcome-GameText

WriteGameText:
	PHA                                          ; save text number to stack
	ASL
	TAY                                          ; multiply by 2 and use as offset
	CPY #$04                                     ; if set to do top status bar or world/lives display,
	BCC LdGameText                               ; branch to use current offset as-is
	CPY #$08                                     ; if set to do time-up or game over,
	BCC Chk2Players                              ; branch to check players
	LDY #$08                                     ; otherwise warp zone, therefore set offset
Chk2Players:
	LDA NumberOfPlayers                          ; check for number of players
	BNE LdGameText                               ; if there are two, use current offset to also print name
	INY                                          ; otherwise increment offset by one to not print name
LdGameText:
	LDX GameTextOffsets,y                        ; get offset to message we want to print
	LDY #$00
GameTextLoop:
	LDA GameText,x                               ; load message data
	CMP #$ff                                     ; check for terminator
	BEQ EndGameText                              ; branch to end text if found
	STA VRAM_Buffer1,y                           ; otherwise write data to buffer
	INX                                          ; and increment increment
	INY
	BNE GameTextLoop                             ; do this for 256 bytes if no terminator found
EndGameText:
	LDA #$00                                     ; put null terminator at end
	STA VRAM_Buffer1,y
	PLA                                          ; pull original text number from stack
	TAX
	CMP #$04                                     ; are we printing warp zone?
	BCS PrintWarpZoneNumbers
	DEX                                          ; are we printing the world/lives display?
	BNE CheckPlayerName                          ; if not, branch to check player's name
	LDA NumberofLives                            ; otherwise, check number of lives
	LDY #$00
-	CMP #10
	BCC +
	SBC #10
	INY
	BNE -
+	CPY #$00
	BEQ +
	STY VRAM_Buffer1+7
+	STA VRAM_Buffer1+8

	LDY WorldNumber                              ; write world and level numbers (incremented for display)
	INY                                          ; to the buffer in the spaces surrounding the dash
	STY VRAM_Buffer1+19
	LDY LevelNumber
	INY
	STY VRAM_Buffer1+21                          ; we're done here
	RTS

CheckPlayerName:
	LDA NumberOfPlayers                          ; check number of players
	BEQ ExitChkName                              ; if only 1 player, leave
	LDA CurrentPlayer                            ; load current player
	DEX                                          ; check to see if current message number is for time up
	BNE ChkLuigi
	LDY OperMode                                 ; check for game over mode
	CPY #GameOverModeValue
	BEQ ChkLuigi
	EOR #%00000001                               ; if not, must be time up, invert d0 to do other player
ChkLuigi:
	LSR
	BCC ExitChkName                              ; if mario is current player, do not change the name
	LDY #$04
NameLoop:
	LDA LuigiName,y                              ; otherwise, replace "MARIO" with "LUIGI"
	STA VRAM_Buffer1+3,y
	DEY
	BPL NameLoop                                 ; do this until each letter is replaced
ExitChkName:
	RTS

PrintWarpZoneNumbers:
	SBC #$04                                     ; subtract 4 and then shift to the left
	ASL                                          ; twice to get proper warp zone number
	ASL                                          ; offset
	TAX
	LDY #$00
WarpNumLoop:
	LDA WarpZoneNumbers,x                        ; print warp zone numbers into the
	STA VRAM_Buffer1+27,y                        ; placeholders from earlier
	INX
	INY                                          ; put a number in every fourth space
	INY
	INY
	INY
	CPY #$0c
	BCC WarpNumLoop
	LDA #$2c                                     ; load new buffer pointer at end of message
	JMP SetVRAMOffset

; -------------------------------------------------------------------------------------

ResetSpritesAndScreenTimer:
	LDA ScreenTimer                              ; check if screen timer has expired
	BNE NoReset                                  ; if not, branch to leave
	JSR MoveAllSpritesOffscreen                  ; otherwise reset sprites now

ResetScreenTimer:
	LDA #$07                                     ; reset timer again
	STA ScreenTimer
	INC ScreenRoutineTask                        ; move onto next task
NoReset:
	RTS

; -------------------------------------------------------------------------------------
; $00 - temp vram buffer offset
; $01 - temp metatile buffer offset
; $02 - temp metatile graphics table offset
; $03 - used to store attribute bits
; $04 - used to determine attribute table row
; $05 - used to determine attribute table column
; $06 - metatile graphics table address low
; $07 - metatile graphics table address high

RenderAreaGraphics:
	LDA CurrentColumnPos                         ; store LSB of where we're at
	AND #$01
	STA $05
	LDY VRAM_Buffer2_Offset                      ; store vram buffer offset
	STY $00
	LDA CurrentNTAddr_Low                        ; get current name table address we're supposed to render
	STA VRAM_Buffer2+1,y
	LDA CurrentNTAddr_High
	STA VRAM_Buffer2,y
	LDA #$9a                                     ; store length byte of 26 here with d7 set
	STA VRAM_Buffer2+2,y                         ; to increment by 32 (in columns)
	LDA #$00                                     ; init attribute row
	STA $04
	TAX
DrawMTLoop:
	STX $01                                      ; store init value of 0 or incremented offset for buffer
	LDA MetatileBuffer,x                         ; get first metatile number, and mask out all but 2 MSB
	AND #%11000000
	STA $03                                      ; store attribute table bits here
	ASL                                          ; note that metatile format is:
	ROL                                          ; %xx000000 - attribute table bits,
	ROL                                          ; %00xxxxxx - metatile number
	TAY                                          ; rotate bits to d1-d0 and use as offset here
	LDA MetatileGraphics_Low,y                   ; get address to graphics table from here
	STA $06
	LDA MetatileGraphics_High,y
	STA $07
	LDA MetatileBuffer,x                         ; get metatile number again
	ASL                                          ; multiply by 4 and use as tile offset
	ASL
	STA $02
	LDA AreaParserTaskNum                        ; get current task number for level processing and
	AND #%00000001                               ; mask out all but LSB, then invert LSB, multiply by 2
	EOR #%00000001                               ; to get the correct column position in the metatile,
	ASL                                          ; then add to the tile offset so we can draw either side
	ADC $02                                      ; of the metatiles
	TAY
	LDX $00                                      ; use vram buffer offset from before as X
	LDA ($06),y
	STA VRAM_Buffer2+3,x                         ; get first tile number (top left or top right) and store
	INY
	LDA ($06),y                                  ; now get the second (bottom left or bottom right) and store
	STA VRAM_Buffer2+4,x
	LDY $04                                      ; get current attribute row
	LDA $05                                      ; get LSB of current column where we're at, and
	BNE RightCheck                               ; branch if set (clear = left attrib, set = right)
	LDA $01                                      ; get current row we're rendering
	LSR                                          ; branch if LSB set (clear = top left, set = bottom left)
	BCS LLeft
	ROL $03                                      ; rotate attribute bits 3 to the left
	ROL $03                                      ; thus in d1-d0, for upper left square
	ROL $03
	JMP SetAttrib
RightCheck:
	LDA $01                                      ; get LSB of current row we're rendering
	LSR                                          ; branch if set (clear = top right, set = bottom right)
	BCS NextMTRow
	LSR $03                                      ; shift attribute bits 4 to the right
	LSR $03                                      ; thus in d3-d2, for upper right square
	LSR $03
	LSR $03
	JMP SetAttrib
LLeft:
	LSR $03                                      ; shift attribute bits 2 to the right
	LSR $03                                      ; thus in d5-d4 for lower left square
NextMTRow:
	INC $04                                      ; move onto next attribute row
SetAttrib:
	LDA AttributeBuffer,y                        ; get previously saved bits from before
	ORA $03                                      ; if any, and put new bits, if any, onto
	STA AttributeBuffer,y                        ; the old, and store
	INC $00                                      ; increment vram buffer offset by 2
	INC $00
	LDX $01                                      ; get current gfx buffer row, and check for
	INX                                          ; the bottom of the screen
	CPX #$0d
	BCC DrawMTLoop                               ; if not there yet, loop back
	LDY $00                                      ; get current vram buffer offset, increment by 3
	INY                                          ; (for name table address and length bytes)
	INY
	INY
	LDA #$00
	STA VRAM_Buffer2,y                           ; put null terminator at end of data for name table
	STY VRAM_Buffer2_Offset                      ; store new buffer offset
	INC CurrentNTAddr_Low                        ; increment name table address low
	LDA CurrentNTAddr_Low                        ; check current low byte
	AND #%00011111                               ; if no wraparound, just skip this part
	BNE ExitDrawM
	LDA #$80                                     ; if wraparound occurs, make sure low byte stays
	STA CurrentNTAddr_Low                        ; just under the status bar
	LDA CurrentNTAddr_High                       ; and then invert d2 of the name table address high
	EOR #%00000100                               ; to move onto the next appropriate name table
	STA CurrentNTAddr_High
ExitDrawM:
	JMP SetVRAMCtrl                              ; jump to set buffer to $0341 and leave

; -------------------------------------------------------------------------------------
; $00 - temp attribute table address high (big endian order this time!)
; $01 - temp attribute table address low

RenderAttributeTables:
	LDA CurrentNTAddr_Low                        ; get low byte of next name table address
	AND #%00011111                               ; to be written to, mask out all but 5 LSB,
	SEC                                          ; subtract four
	SBC #$04
	AND #%00011111                               ; mask out bits again and store
	STA $01
	LDA CurrentNTAddr_High                       ; get high byte and branch if borrow not set
	BCS SetATHigh
	EOR #%00000100                               ; otherwise invert d2
SetATHigh:
	AND #%00000100                               ; mask out all other bits
	ORA #$23                                     ; add $2300 to the high byte and store
	STA $00
	LDA $01                                      ; get low byte - 4, divide by 4, add offset for
	LSR                                          ; attribute table and store
	LSR
	ADC #$c0                                     ; we should now have the appropriate block of
	STA $01                                      ; attribute table in our temp address
	LDX #$00
	LDY VRAM_Buffer2_Offset                      ; get buffer offset
AttribLoop:
	LDA $00
	STA VRAM_Buffer2,y                           ; store high byte of attribute table address
	LDA $01
	CLC                                          ; get low byte, add 8 because we want to start
	ADC #$08                                     ; below the status bar, and store
	STA VRAM_Buffer2+1,y
	STA $01                                      ; also store in temp again
	LDA AttributeBuffer,x                        ; fetch current attribute table byte and store
	STA VRAM_Buffer2+3,y                         ; in the buffer
	LDA #$01
	STA VRAM_Buffer2+2,y                         ; store length of 1 in buffer
	LSR
	STA AttributeBuffer,x                        ; clear current byte in attribute buffer
	INY                                          ; increment buffer offset by 4 bytes
	INY
	INY
	INY
	INX                                          ; increment attribute offset and check to see
	CPX #$07                                     ; if we're at the end yet
	BCC AttribLoop
	STA VRAM_Buffer2,y                           ; put null terminator at the end
	STY VRAM_Buffer2_Offset                      ; store offset in case we want to do any more
SetVRAMCtrl:
	LDA #$06
	STA VRAM_Buffer_AddrCtrl                     ; set buffer to $0341 and leave
	RTS

; -------------------------------------------------------------------------------------

; $00 - used as temporary counter in ColorRotation

ColorRotatePalette:
	.db $27, $27, $27, $17, $07, $17

BlankPalette:
	.db $3f, $0c, $04, $ff, $ff, $ff, $ff, $00

; used based on area type
Palette3Data:
	.db $0f, $07, $12, $0f
	.db $0f, $07, $17, $0f
	.db $0f, $07, $17, $1c
	.db $0f, $07, $17, $00

ColorRotation:
	LDA FrameCounter                             ; get frame counter
	AND #$07                                     ; mask out all but three LSB
	BNE ExitColorRot                             ; branch if not set to zero to do this every eighth frame
	LDX VRAM_Buffer1_Offset                      ; check vram buffer offset
	CPX #$31
	BCS ExitColorRot                             ; if offset over 48 bytes, branch to leave
	TAY                                          ; otherwise use frame counter's 3 LSB as offset here
GetBlankPal:
	LDA BlankPalette,y                           ; get blank palette for palette 3
	STA VRAM_Buffer1,x                           ; store it in the vram buffer
	INX                                          ; increment offsets
	INY
	CPY #$08
	BCC GetBlankPal                              ; do this until all bytes are copied
	LDX VRAM_Buffer1_Offset                      ; get current vram buffer offset
	LDA #$03
	STA $00                                      ; set counter here
	LDA AreaType                                 ; get area type
	ASL                                          ; multiply by 4 to get proper offset
	ASL
	TAY                                          ; save as offset here
GetAreaPal:
	LDA Palette3Data,y                           ; fetch palette to be written based on area type
	STA VRAM_Buffer1+3,x                         ; store it to overwrite blank palette in vram buffer
	INY
	INX
	DEC $00                                      ; decrement counter
	BPL GetAreaPal                               ; do this until the palette is all copied
	LDX VRAM_Buffer1_Offset                      ; get current vram buffer offset
	LDY ColorRotateOffset                        ; get color cycling offset
	LDA ColorRotatePalette,y
	STA VRAM_Buffer1+4,x                         ; get and store current color in second slot of palette
	LDA VRAM_Buffer1_Offset
	CLC                                          ; add seven bytes to vram buffer offset
	ADC #$07
	STA VRAM_Buffer1_Offset
	INC ColorRotateOffset                        ; increment color cycling offset
	LDA ColorRotateOffset
	CMP #$06                                     ; check to see if it's still in range
	BCC ExitColorRot                             ; if so, branch to leave
	LDA #$00
	STA ColorRotateOffset                        ; otherwise, init to keep it in range
ExitColorRot:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------
; $00 - temp store for offset control bit
; $01 - temp vram buffer offset
; $02 - temp store for vertical high nybble in block buffer routine
; $03 - temp adder for high byte of name table address
; $04, $05 - name table address low/high
; $06, $07 - block buffer address low/high

BlockGfxData:
	.db $45, $45, $47, $47
	.db $47, $47, $47, $47
	.db $57, $58, $59, $5a
	.db $24, $24, $24, $24
	.db $26, $26, $26, $26

RemoveCoin_Axe:
	LDY #$41                                     ; set low byte so offset points to $0341
	LDA #$03                                     ; load offset for default blank metatile
	LDX AreaType                                 ; check area type
	BNE WriteBlankMT                             ; if not water type, use offset
	LDA #$04                                     ; otherwise load offset for blank metatile used in water
WriteBlankMT:
	JSR PutBlockMetatile                         ; do a sub to write blank metatile to vram buffer
	LDA #$06
	STA VRAM_Buffer_AddrCtrl                     ; set vram address controller to $0341 and leave
	RTS

ReplaceBlockMetatile:
	JSR WriteBlockMetatile                       ; write metatile to vram buffer to replace block object
	INC Block_ResidualCounter                    ; increment unused counter (residual code)
	DEC Block_RepFlag,x                          ; decrement flag (residual code)
	RTS                                          ; leave

DestroyBlockMetatile:
	LDA #$00                                     ; force blank metatile if branched/jumped to this point

WriteBlockMetatile:
	LDY #$03                                     ; load offset for blank metatile
	CMP #$00                                     ; check contents of A for blank metatile
	BEQ UseBOffset                               ; branch if found (unconditional if branched from 8a6b)
	LDY #$00                                     ; load offset for brick metatile w/ line
	CMP #$58
	BEQ UseBOffset                               ; use offset if metatile is brick with coins (w/ line)
	CMP #$51
	BEQ UseBOffset                               ; use offset if metatile is breakable brick w/ line
	INY                                          ; increment offset for brick metatile w/o line
	CMP #$5d
	BEQ UseBOffset                               ; use offset if metatile is brick with coins (w/o line)
	CMP #$52
	BEQ UseBOffset                               ; use offset if metatile is breakable brick w/o line
	INY                                          ; if any other metatile, increment offset for empty block
UseBOffset:
	TYA                                          ; put Y in A
	LDY VRAM_Buffer1_Offset                      ; get vram buffer offset
	INY                                          ; move onto next byte
	JSR PutBlockMetatile                         ; get appropriate block data and write to vram buffer
MoveVOffset:
	DEY                                          ; decrement vram buffer offset
	TYA                                          ; add 10 bytes to it
	CLC
	ADC #10
	JMP SetVRAMOffset                            ; branch to store as new vram buffer offset

PutBlockMetatile:
	STX $00                                      ; store control bit from SprDataOffset_Ctrl
	STY $01                                      ; store vram buffer offset for next byte
	ASL
	ASL                                          ; multiply A by four and use as X
	TAX
	LDY #$20                                     ; load high byte for name table 0
	LDA $06                                      ; get low byte of block buffer pointer
	CMP #$d0                                     ; check to see if we're on odd-page block buffer
	BCC SaveHAdder                               ; if not, use current high byte
	LDY #$24                                     ; otherwise load high byte for name table 1
SaveHAdder:
	STY $03                                      ; save high byte here
	AND #$0f                                     ; mask out high nybble of block buffer pointer
	ASL                                          ; multiply by 2 to get appropriate name table low byte
	STA $04                                      ; and then store it here
	LDA #$00
	STA $05                                      ; initialize temp high byte
	LDA $02                                      ; get vertical high nybble offset used in block buffer routine
	CLC
	ADC #$20                                     ; add 32 pixels for the status bar
	ASL
	ROL $05                                      ; shift and rotate d7 onto d0 and d6 into carry
	ASL
	ROL $05                                      ; shift and rotate d6 onto d0 and d5 into carry
	ADC $04                                      ; add low byte of name table and carry to vertical high nybble
	STA $04                                      ; and store here
	LDA $05                                      ; get whatever was in d7 and d6 of vertical high nybble
	ADC #$00                                     ; add carry
	CLC
	ADC $03                                      ; then add high byte of name table
	STA $05                                      ; store here
	LDY $01                                      ; get vram buffer offset to be used
RemBridge:
	LDA BlockGfxData,x                           ; write top left and top right
	STA VRAM_Buffer1+2,y                         ; tile numbers into first spot
	LDA BlockGfxData+1,x
	STA VRAM_Buffer1+3,y
	LDA BlockGfxData+2,x                         ; write bottom left and bottom
	STA VRAM_Buffer1+7,y                         ; right tiles numbers into
	LDA BlockGfxData+3,x                         ; second spot
	STA VRAM_Buffer1+8,y
	LDA $04
	STA VRAM_Buffer1,y                           ; write low byte of name table
	CLC                                          ; into first slot as read
	ADC #$20                                     ; add 32 bytes to value
	STA VRAM_Buffer1+5,y                         ; write low byte of name table
	LDA $05                                      ; plus 32 bytes into second slot
	STA VRAM_Buffer1-1,y                         ; write high byte of name
	STA VRAM_Buffer1+4,y                         ; table address to both slots
	LDA #$02
	STA VRAM_Buffer1+1,y                         ; put length of 2 in
	STA VRAM_Buffer1+6,y                         ; both slots
	LDA #$00
	STA VRAM_Buffer1+9,y                         ; put null terminator at end
	LDX $00                                      ; get offset control bit here
	RTS                                          ; and leave

; -------------------------------------------------------------------------------------
; METATILE GRAPHICS TABLE

MetatileGraphics_Low:
	.db <Palette0_MTiles, <Palette1_MTiles, <Palette2_MTiles, <Palette3_MTiles

MetatileGraphics_High:
	.db >Palette0_MTiles, >Palette1_MTiles, >Palette2_MTiles, >Palette3_MTiles

Palette0_MTiles:
	.db $24, $24, $24, $24                       ; blank
	.db $27, $27, $27, $27                       ; black metatile
	.db $24, $24, $24, $35                       ; bush left
	.db $36, $25, $37, $25                       ; bush middle
	.db $24, $38, $24, $24                       ; bush right
	.db $24, $30, $30, $26                       ; mountain left
	.db $26, $26, $34, $26                       ; mountain left bottom/middle center
	.db $24, $31, $24, $32                       ; mountain middle top
	.db $33, $26, $24, $33                       ; mountain right
	.db $34, $26, $26, $26                       ; mountain right bottom
	.db $26, $26, $26, $26                       ; mountain middle bottom
	.db $24, $c0, $24, $c0                       ; bridge guardrail
	.db $24, $7f, $7f, $24                       ; chain
	.db $b8, $ba, $b9, $bb                       ; tall tree top, top half
	.db $b8, $bc, $b9, $bd                       ; short tree top
	.db $ba, $bc, $bb, $bd                       ; tall tree top, bottom half
	.db $60, $64, $61, $65                       ; warp pipe end left, points up
	.db $62, $66, $63, $67                       ; warp pipe end right, points up
	.db $60, $64, $61, $65                       ; decoration pipe end left, points up
	.db $62, $66, $63, $67                       ; decoration pipe end right, points up
	.db $68, $68, $69, $69                       ; pipe shaft left
	.db $26, $26, $6a, $6a                       ; pipe shaft right
	.db $4b, $4c, $4d, $4e                       ; tree ledge left edge
	.db $4d, $4f, $4d, $4f                       ; tree ledge middle
	.db $4d, $4e, $50, $51                       ; tree ledge right edge
	.db $6b, $70, $2c, $2d                       ; mushroom left edge
	.db $6c, $71, $6d, $72                       ; mushroom middle
	.db $6e, $73, $6f, $74                       ; mushroom right edge
	.db $86, $8a, $87, $8b                       ; sideways pipe end top
	.db $88, $8c, $88, $8c                       ; sideways pipe shaft top
	.db $89, $8d, $69, $69                       ; sideways pipe joint top
	.db $8e, $91, $8f, $92                       ; sideways pipe end bottom
	.db $26, $93, $26, $93                       ; sideways pipe shaft bottom
	.db $90, $94, $69, $69                       ; sideways pipe joint bottom
	.db $a4, $e9, $ea, $eb                       ; seaplant
	.db $24, $24, $24, $24                       ; blank, used on bricks or blocks that are hit
	.db $24, $2f, $24, $3d                       ; flagpole ball
	.db $a2, $a2, $a3, $a3                       ; flagpole shaft
	.db $24, $24, $24, $24                       ; blank, used in conjunction with vines

Palette1_MTiles:
	.db $a2, $a2, $a3, $a3                       ; vertical rope
	.db $99, $24, $99, $24                       ; horizontal rope
	.db $24, $a2, $3e, $3f                       ; left pulley
	.db $5b, $5c, $24, $a3                       ; right pulley
	.db $24, $24, $24, $24                       ; blank used for balance rope
	.db $9d, $47, $9e, $47                       ; castle top
	.db $47, $47, $27, $27                       ; castle window left
	.db $47, $47, $47, $47                       ; castle brick wall
	.db $27, $27, $47, $47                       ; castle window right
	.db $a9, $47, $aa, $47                       ; castle top w/ brick
	.db $9b, $27, $9c, $27                       ; entrance top
	.db $27, $27, $27, $27                       ; entrance bottom
	.db $52, $52, $52, $52                       ; green ledge stump
	.db $80, $a0, $81, $a1                       ; fence
	.db $be, $be, $bf, $bf                       ; tree trunk
	.db $75, $ba, $76, $bb                       ; mushroom stump top
	.db $ba, $ba, $bb, $bb                       ; mushroom stump bottom
	.db $45, $47, $45, $47                       ; breakable brick w/ line
	.db $47, $47, $47, $47                       ; breakable brick
	.db $45, $47, $45, $47                       ; breakable brick (not used)
	.db $b4, $b6, $b5, $b7                       ; cracked rock terrain
	.db $45, $47, $45, $47                       ; brick with line (power-up)
	.db $45, $47, $45, $47                       ; brick with line (vine)
	.db $45, $47, $45, $47                       ; brick with line (star)
	.db $45, $47, $45, $47                       ; brick with line (coins)
	.db $45, $47, $45, $47                       ; brick with line (1-up)
	.db $47, $47, $47, $47                       ; brick (power-up)
	.db $47, $47, $47, $47                       ; brick (vine)
	.db $47, $47, $47, $47                       ; brick (star)
	.db $47, $47, $47, $47                       ; brick (coins)
	.db $47, $47, $47, $47                       ; brick (1-up)
	.db $24, $24, $24, $24                       ; hidden block (1 coin)
	.db $24, $24, $24, $24                       ; hidden block (1-up)
	.db $ab, $ac, $ad, $ae                       ; solid block (3-d block)
	.db $5d, $5e, $5d, $5e                       ; solid block (white wall)
	.db $c1, $24, $c1, $24                       ; bridge
	.db $c6, $c8, $c7, $c9                       ; bullet bill cannon barrel
	.db $ca, $cc, $cb, $cd                       ; bullet bill cannon top
	.db $2a, $2a, $40, $40                       ; bullet bill cannon bottom
	.db $24, $24, $24, $24                       ; blank used for jumpspring
	.db $24, $47, $24, $47                       ; half brick used for jumpspring
	.db $82, $83, $84, $85                       ; solid block (water level, green rock)
	.db $24, $47, $24, $47                       ; half brick (???)
	.db $86, $8a, $87, $8b                       ; water pipe top
	.db $8e, $91, $8f, $92                       ; water pipe bottom
	.db $24, $2f, $24, $3d                       ; flag ball (residual object)

Palette2_MTiles:
	.db $24, $24, $24, $35                       ; cloud left
	.db $36, $25, $37, $25                       ; cloud middle
	.db $24, $38, $24, $24                       ; cloud right
	.db $24, $24, $39, $24                       ; cloud bottom left
	.db $3a, $24, $3b, $24                       ; cloud bottom middle
	.db $3c, $24, $24, $24                       ; cloud bottom right
	.db $41, $26, $41, $26                       ; water/lava top
	.db $26, $26, $26, $26                       ; water/lava
	.db $b0, $b1, $b2, $b3                       ; cloud level terrain
	.db $77, $79, $77, $79                       ; bowser's bridge

Palette3_MTiles:
	.db $53, $55, $54, $56                       ; question block (coin)
	.db $53, $55, $54, $56                       ; question block (power-up)
	.db $a5, $a7, $a6, $a8                       ; coin
	.db $c2, $c4, $c3, $c5                       ; underwater coin
	.db $57, $59, $58, $5a                       ; empty block
	.db $7b, $7d, $7c, $7e                       ; axe

; -------------------------------------------------------------------------------------
; VRAM BUFFER DATA FOR LOCATIONS IN PRG-ROM

WaterPaletteData:
	.db $3f, $00, $20
	.db $0f, $15, $12, $25
	.db $0f, $3a, $1a, $0f
	.db $0f, $30, $12, $0f
	.db $0f, $27, $12, $0f
	.db $22, $16, $27, $18
	.db $0f, $10, $30, $27
	.db $0f, $16, $30, $27
	.db $0f, $0f, $30, $10
	.db $00

GroundPaletteData:
	.db $3f, $00, $20
	.db $0f, $29, $1a, $0f
	.db $0f, $36, $17, $0f
	.db $0f, $30, $21, $0f
	.db $0f, $27, $17, $0f
	.db $0f, $16, $27, $18
	.db $0f, $1a, $30, $27
	.db $0f, $16, $30, $27
	.db $0f, $0f, $36, $17
	.db $00

UndergroundPaletteData:
	.db $3f, $00, $20
	.db $0f, $29, $1a, $09
	.db $0f, $3c, $1c, $0f
	.db $0f, $30, $21, $1c
	.db $0f, $27, $17, $1c
	.db $0f, $16, $27, $18
	.db $0f, $1c, $36, $17
	.db $0f, $16, $30, $27
	.db $0f, $0c, $3c, $1c
	.db $00

CastlePaletteData:
	.db $3f, $00, $20
	.db $0f, $30, $10, $00
	.db $0f, $30, $10, $00
	.db $0f, $30, $16, $00
	.db $0f, $27, $17, $00
	.db $0f, $16, $27, $18
	.db $0f, $1c, $36, $17
	.db $0f, $16, $30, $27
	.db $0f, $00, $30, $10
	.db $00

DaySnowPaletteData:
	.db $3f, $00, $04
	.db $22, $30, $00, $10
	.db $00

NightSnowPaletteData:
	.db $3f, $00, $04
	.db $0f, $30, $00, $10
	.db $00

MushroomPaletteData:
	.db $3f, $00, $04
	.db $22, $27, $16, $0f
	.db $00

BowserPaletteData:
	.db $3f, $14, $04
	.db $0f, $1a, $30, $27
	.db $00

MarioThanksMessage:
; "THANK YOU MARIO!"
	.db $25, $48, $10
	.db $1d, $11, $0a, $17, $14, $24
	.db $22, $18, $1e, $24
	.db $16, $0a, $1b, $12, $18, $2b
	.db $00

LuigiThanksMessage:
; "THANK YOU LUIGI!"
	.db $25, $48, $10
	.db $1d, $11, $0a, $17, $14, $24
	.db $22, $18, $1e, $24
	.db $15, $1e, $12, $10, $12, $2b
	.db $00

MushroomRetainerSaved:
; "BUT OUR PRINCESS IS IN"
	.db $25, $c5, $16
	.db $0b, $1e, $1d, $24, $18, $1e, $1b, $24
	.db $19, $1b, $12, $17, $0c, $0e, $1c, $1c, $24
	.db $12, $1c, $24, $12, $17
; "ANOTHER CASTLE!"
	.db $26, $05, $0f
	.db $0a, $17, $18, $1d, $11, $0e, $1b, $24
	.db $0c, $0a, $1c, $1d, $15, $0e, $2b, $00

PrincessSaved1:
; "YOUR QUEST IS OVER."
	.db $25, $a7, $13
	.db $22, $18, $1e, $1b, $24
	.db $1a, $1e, $0e, $1c, $1d, $24
	.db $12, $1c, $24, $18, $1f, $0e, $1b, $af
	.db $00

PrincessSaved2:
; "WE PRESENT YOU A NEW QUEST."
	.db $25, $e3, $1b
	.db $20, $0e, $24
	.db $19, $1b, $0e, $1c, $0e, $17, $1d, $24
	.db $22, $18, $1e, $24, $0a, $24, $17, $0e, $20, $24
	.db $1a, $1e, $0e, $1c, $1d, $af
	.db $00

WorldSelectMessage1:
; "PUSH BUTTON B"
	.db $26, $4a, $0d
	.db $19, $1e, $1c, $11, $24
	.db $0b, $1e, $1d, $1d, $18, $17, $24, $0b
	.db $00

WorldSelectMessage2:
; "TO SELECT A WORLD"
	.db $26, $88, $11
	.db $1d, $18, $24, $1c, $0e, $15, $0e, $0c, $1d, $24
	.db $0a, $24, $20, $18, $1b, $15, $0d
	.db $00

; -------------------------------------------------------------------------------------
; $04 - address low to jump address
; $05 - address high to jump address
; $06 - jump address low
; $07 - jump address high

JumpEngine:
	ASL                                          ; shift bit from contents of A
	TAY
	PLA                                          ; pull saved return address from stack
	STA $04                                      ; save to indirect
	PLA
	STA $05
	INY
	LDA ($04),y                                  ; load pointer from indirect
	STA $06                                      ; note that if an RTS is performed in next routine
	INY                                          ; it will return to the execution before the sub
	LDA ($04),y                                  ; that called this routine
	STA $07
	JMP ($06)                                    ; jump to the address we loaded

; -------------------------------------------------------------------------------------

InitializeNameTables:
	LDA PPU_STATUS                               ; reset flip-flop
	LDA Mirror_PPU_CTRL_REG1                     ; load mirror of ppu reg $2000
	ORA #%00010000                               ; set sprites for first 4k and background for second 4k
	AND #%11110000                               ; clear rest of lower nybble, leave higher alone
	JSR WritePPUReg1
	LDA #$24                                     ; set vram address to start of name table 1
	JSR WriteNTAddr
	LDA #$20                                     ; and then set it to name table 0
WriteNTAddr:
	STA PPU_ADDRESS
	LDA #$00
	STA PPU_ADDRESS
	LDX #$04                                     ; clear name table with blank tile #24
	LDY #$c0
	LDA #$24
InitNTLoop:
	STA PPU_DATA                                 ; count out exactly 768 tiles
	DEY
	BNE InitNTLoop
	DEX
	BNE InitNTLoop
	LDY #64                                      ; now to clear the attribute table (with zero this time)
	TXA
	STA VRAM_Buffer1_Offset                      ; init vram buffer 1 offset
	STA VRAM_Buffer1                             ; init vram buffer 1
InitATLoop:
	STA PPU_DATA
	DEY
	BNE InitATLoop
	STA HorizontalScroll                         ; reset scroll variables
	STA VerticalScroll
	JMP InitScroll                               ; initialize scroll registers to zero

; -------------------------------------------------------------------------------------
; $00 - temp joypad bit

ReadJoypads:
IFDEF STUPID_PHYSICS_CRAP
	LDA SwimmingFlag
	BNE +
	LDA Player_State
	CMP #$01
	BEQ ++
ENDIF

+	LDA #$01                                     ; reset and clear strobe of joypad ports
	STA JOYPAD_PORT
	LSR
	TAX                                          ; start with joypad 1's port
	STA JOYPAD_PORT
	JSR ReadPortBits
	INX                                          ; increment for joypad 2's port
ReadPortBits:
	LDY #$08
PortLoop:
	PHA                                          ; push previous bit onto stack
	LDA JOYPAD_PORT,x                            ; read current bit on joypad port
	STA $00                                      ; check d1 and d0 of port output
	LSR                                          ; this is necessary on the old
	ORA $00                                      ; famicom systems in japan
	LSR
	PLA                                          ; read bits from stack
	ROL                                          ; rotate bit from carry flag
	DEY
	BNE PortLoop                                 ; count down bits left
	STA SavedJoypadBits,x                        ; save controller status here always
	PHA
Save8Bits:
	LDA JoypadBitMask,x
	EOR #$FF
	AND SavedJoypadBits,x
	STA JoypadPressed,x                          ; save with all bits in another place and leave

	PLA
	STA JoypadBitMask,x                          ; save with all bits in another place and leave
++	RTS

; -------------------------------------------------------------------------------------
; $00 - vram buffer address table low
; $01 - vram buffer address table high

WriteBufferToScreen:
	STA PPU_ADDRESS                              ; store high byte of vram address
	INY
	LDA ($00),y                                  ; load next byte (second)
	STA PPU_ADDRESS                              ; store low byte of vram address
	INY
	LDA ($00),y                                  ; load next byte (third)
	ASL                                          ; shift to left and save in stack
	PHA
	LDA Mirror_PPU_CTRL_REG1                     ; load mirror of $2000,
	ORA #%00000100                               ; set ppu to increment by 32 by default
	BCS SetupWrites                              ; if d7 of third byte was clear, ppu will
	AND #%11111011                               ; only increment by 1
SetupWrites:
	JSR WritePPUReg1                             ; write to register
	PLA                                          ; pull from stack and shift to left again
	ASL
	BCC GetLength                                ; if d6 of third byte was clear, do not repeat byte
	ORA #%00000010                               ; otherwise set d1 and increment Y
	INY
GetLength:
	LSR                                          ; shift back to the right to get proper length
	LSR                                          ; note that d1 will now be in carry
	TAX
OutputToVRAM:
	BCS RepeatByte                               ; if carry set, repeat loading the same byte
	INY                                          ; otherwise increment Y to load next byte
RepeatByte:
	LDA ($00),y                                  ; load more data from buffer and write to vram
	STA PPU_DATA
	DEX                                          ; done writing?
	BNE OutputToVRAM
	SEC
	TYA
	ADC $00                                      ; add end length plus one to the indirect at $00
	STA $00                                      ; to allow this routine to read another set of updates
	LDA #$00
	ADC $01
	STA $01
	LDA #$3f                                     ; sets vram address to $3f00
	STA PPU_ADDRESS
	LDA #$00
	STA PPU_ADDRESS
	STA PPU_ADDRESS                              ; then reinitializes it for some reason
	STA PPU_ADDRESS
UpdateScreen:
	LDX PPU_STATUS                               ; reset flip-flop
	LDY #$00                                     ; load first byte from indirect as a pointer
	LDA ($00),y
	BNE WriteBufferToScreen                      ; if byte is zero we have no further updates to make here
InitScroll:
	STA PPU_SCROLL_REG                           ; store contents of A into scroll registers
	STA PPU_SCROLL_REG                           ; and end whatever subroutine led us here
	RTS

; -------------------------------------------------------------------------------------

WritePPUReg1:
	STA PPU_CTRL_REG1                            ; write contents of A to PPU register 1
	STA Mirror_PPU_CTRL_REG1                     ; and its mirror
	RTS

; -------------------------------------------------------------------------------------
; $00 - used to store status bar nybbles
; $02 - used as temp vram offset
; $03 - used to store length of status bar number

; status bar name table offset and length data
StatusBarData:
	.db $f0, $06                                 ; top score display on title screen
	.db $62, $06                                 ; player score
	.db $62, $06
	.db $6d, $02                                 ; coin tally
	.db $6d, $02
	.db $7a, $03                                 ; game timer

StatusBarOffset:
	.db $06, $0c, $12, $18, $1e, $24

PrintStatusBarNumbers:
	STA $00                                      ; store player-specific offset
	JSR OutputNumbers                            ; use first nybble to print the coin display
	LDA $00                                      ; move high nybble to low
	LSR                                          ; and print to score display
	LSR
	LSR
	LSR

OutputNumbers:
	CLC                                          ; add 1 to low nybble
	ADC #$01
	AND #%00001111                               ; mask out high nybble
	CMP #$06
	BCS ExitOutputN
	PHA                                          ; save incremented value to stack for now and
	ASL                                          ; shift to left and use as offset
	TAY
	LDX VRAM_Buffer1_Offset                      ; get current buffer pointer
	LDA #$20                                     ; put at top of screen by default
	CPY #$00                                     ; are we writing top score on title screen?
	BNE SetupNums
	LDA #$22                                     ; if so, put further down on the screen
SetupNums:
	STA VRAM_Buffer1,x
	LDA StatusBarData,y                          ; write low vram address and length of thing
	STA VRAM_Buffer1+1,x                         ; we're printing to the buffer
	LDA StatusBarData+1,y
	STA VRAM_Buffer1+2,x
	STA $03                                      ; save length byte in counter
	STX $02                                      ; and buffer pointer elsewhere for now
	PLA                                          ; pull original incremented value from stack
	TAX
	LDA StatusBarOffset,x                        ; load offset to value we want to write
	SEC
	SBC StatusBarData+1,y                        ; subtract from length byte we read before
	TAY                                          ; use value as offset to display digits
	LDX $02
DigitPLoop:
	LDA DisplayDigits,y                          ; write digits to the buffer
	STA VRAM_Buffer1+3,x
	INX
	INY
	DEC $03                                      ; do this until all the digits are written
	BNE DigitPLoop
	LDA #$00                                     ; put null terminator at end
	STA VRAM_Buffer1+3,x
	INX                                          ; increment buffer pointer by 3
	INX
	INX
	STX VRAM_Buffer1_Offset                      ; store it in case we want to use it again
ExitOutputN:
	RTS

; -------------------------------------------------------------------------------------

DigitsMathRoutine:
	LDA OperMode                                 ; check mode of operation
	CMP #TitleScreenModeValue
	BEQ EraseDMods                               ; if in title screen mode, branch to lock score
	LDX #$05
AddModLoop:
	LDA DigitModifier,x                          ; load digit amount to increment
	CLC
	ADC DisplayDigits,y                          ; add to current digit
	BMI BorrowOne                                ; if result is a negative number, branch to subtract
	CMP #10
	BCS CarryOne                                 ; if digit greater than $09, branch to add
StoreNewD:
	STA DisplayDigits,y                          ; store as new score or game timer digit
	DEY                                          ; move onto next digits in score or game timer
	DEX                                          ; and digit amounts to increment
	BPL AddModLoop                               ; loop back if we're not done yet
EraseDMods:
	LDA #$00                                     ; store zero here
	LDX #$06                                     ; start with the last digit
EraseMLoop:
	STA DigitModifier-1,x                        ; initialize the digit amounts to increment
	DEX
	BPL EraseMLoop                               ; do this until they're all reset, then leave
	RTS
BorrowOne:
	DEC DigitModifier-1,x                        ; decrement the previous digit, then put $09 in
	LDA #$09                                     ; the game timer digit we're currently on to "borrow
	BNE StoreNewD                                ; the one", then do an unconditional branch back
CarryOne:
	SEC                                          ; subtract ten from our digit to make it a
	SBC #10                                      ; proper BCD number, then increment the digit
	INC DigitModifier-1,x                        ; preceding current digit to "carry the one" properly
	JMP StoreNewD                                ; go back to just after we branched here

; -------------------------------------------------------------------------------------

UpdateTopScore:
	LDX #$05                                     ; start with mario's score
	JSR TopScoreCheck
	LDX #$0b                                     ; now do luigi's score

TopScoreCheck:
	LDY #$05                                     ; start with the lowest digit
	SEC
GetScoreDiff:
	LDA PlayerScoreDisplay,x                     ; subtract each player digit from each high score digit
	SBC TopScoreDisplay,y                        ; from lowest to highest, if any top score digit exceeds
	DEX                                          ; any player digit, borrow will be set until a subsequent
	DEY                                          ; subtraction clears it (player digit is higher than top)
	BPL GetScoreDiff
	BCC NoTopSc                                  ; check to see if borrow is still set, if so, no new high score
	INX                                          ; increment X and Y once to the start of the score
	INY
CopyScore:
	LDA PlayerScoreDisplay,x                     ; store player's score digits into high score memory area
	STA TopScoreDisplay,y
	INX
	INY
	CPY #$06                                     ; do this until we have stored them all
	BCC CopyScore
NoTopSc:
	RTS

; -------------------------------------------------------------------------------------

DefaultSprOffsets:
	.db $04, $30, $48, $60, $78, $90, $a8, $c0
	.db $d8, $e8, $24, $f8, $fc, $28, $2c

Sprite0Data:
	.db $18, $ff, $23, $58

; -------------------------------------------------------------------------------------

InitializeGame:
	LDY #$6f                                     ; clear all memory as in initialization procedure,
	JSR InitializeMemory                         ; but this time, clear only as far as $076f
	LDY #$1f
ClrSndLoop:
	STA SoundMemory,y                            ; clear out memory used
	DEY                                          ; by the sound engines
	BPL ClrSndLoop
	LDA #$18                                     ; set demo timer
	STA DemoTimer
	JSR LoadAreaPointer

InitializeArea:
	LDY #$4b                                     ; clear all memory again, only as far as $074b
	JSR InitializeMemory                         ; this is only necessary if branching from
	LDX #$21
	LDA #$00
ClrTimersLoop:
	STA Timers,x                                 ; clear out memory between
	DEX                                          ; $0780 and $07a1
	BPL ClrTimersLoop
	LDA HalfwayPage
	LDY AltEntranceControl                       ; if AltEntranceControl not set, use halfway page, if any found
	BEQ StartPage
	LDA EntrancePage                             ; otherwise use saved entry page number here
StartPage:
	STA ScreenLeft_PageLoc                       ; set as value here
	STA CurrentPageLoc                           ; also set as current page
	STA BackloadingFlag                          ; set flag here if halfway page or saved entry page number found
	JSR GetScreenPosition                        ; get pixel coordinates for screen borders
	LDY #$20                                     ; if on odd numbered page, use $2480 as start of rendering
	AND #%00000001                               ; otherwise use $2080, this address used later as name table
	BEQ SetInitNTHigh                            ; address for rendering of game area
	LDY #$24
SetInitNTHigh:
	STY CurrentNTAddr_High                       ; store name table address
	LDY #$80
	STY CurrentNTAddr_Low
	ASL                                          ; store LSB of page number in high nybble
	ASL                                          ; of block buffer column position
	ASL
	ASL
	STA BlockBufferColumnPos
	DEC AreaObjectLength                         ; set area object lengths for all empty
	DEC AreaObjectLength+1
	DEC AreaObjectLength+2
	LDA #$0b                                     ; set value for renderer to update 12 column sets
	STA ColumnSets                               ; 12 column sets = 24 metatile columns = 1 1/2 screens
	JSR GetAreaDataAddrs                         ; get enemy and level addresses and load header
	LDA PrimaryHardMode                          ; check to see if primary hard mode has been activated
	BNE SetSecHard                               ; if so, activate the secondary no matter where we're at
	LDA WorldNumber                              ; otherwise check world number
	CMP #World5                                  ; if less than 5, do not activate secondary
	BCC CheckHalfway
	BNE SetSecHard                               ; if not equal to, then world > 5, thus activate
	LDA LevelNumber                              ; otherwise, world 5, so check level number
	CMP #Level3                                  ; if 1 or 2, do not set secondary hard mode flag
	BCC CheckHalfway
SetSecHard:
	INC SecondaryHardMode                        ; set secondary hard mode flag for areas 5-3 and beyond
CheckHalfway:
	LDA HalfwayPage
	BEQ DoneInitArea
	LDA #$02                                     ; if halfway page set, overwrite start position from header
	STA PlayerEntranceCtrl
DoneInitArea:
	LDA #Silence                                 ; silence music
	STA AreaMusicQueue
	LDA #$01                                     ; disable screen output
	STA DisableScreenFlag
	INC OperMode_Task                            ; increment one of the modes
	RTS

; -------------------------------------------------------------------------------------

PrimaryGameSetup:
	LDA #$01
	STA FetchNewGameTimerFlag                    ; set flag to load game timer from header
	STA PlayerSize                               ; set player's size to small
	LDA #$00
	STA NumberofLives                            ; set 0 lives for both players
	STA OffScr_NumberofLives

SecondaryGameSetup:
	LDA #$00
	STA DisableScreenFlag                        ; enable screen output
	TAY
ClearVRLoop:
	STA VRAM_Buffer1-1,y                         ; clear buffer at $0300-$03ff
	INY
	BNE ClearVRLoop
	STA GameTimerExpiredFlag                     ; clear game timer exp flag
	STA DisableIntermediate                      ; clear skip lives display flag
	STA BackloadingFlag                          ; clear value here
	LDA #$ff
	STA BalPlatformAlignment                     ; initialize balance platform assignment flag
	LDA ScreenLeft_PageLoc                       ; get left side page location
	LSR Mirror_PPU_CTRL_REG1                     ; shift LSB of ppu register #1 mirror out
	AND #$01                                     ; mask out all but LSB of page location
	ROR                                          ; rotate LSB of page location into carry then onto mirror
	ROL Mirror_PPU_CTRL_REG1                     ; this is to set the proper PPU name table
	JSR GetAreaMusic                             ; load proper music into queue
	LDA #$38                                     ; load sprite shuffle amounts to be used later
	STA SprShuffleAmt+2
	LDA #$48
	STA SprShuffleAmt+1
	LDA #$58
	STA SprShuffleAmt
	LDX #$0e                                     ; load default OAM offsets into $06e4-$06f2
ShufAmtLoop:
	LDA DefaultSprOffsets,x
	STA SprDataOffset,x
	DEX                                          ; do this until they're all set
	BPL ShufAmtLoop
	LDY #$03                                     ; set up sprite #0
ISpr0Loop:
	LDA Sprite0Data,y
	STA Sprite_Data,y
	DEY
	BPL ISpr0Loop
	JSR DoNothing2                               ; these jsrs doesn't do anything useful
	JSR DoNothing1
	INC Sprite0HitDetectFlag                     ; set sprite #0 check flag
	INC OperMode_Task                            ; increment to next task
	RTS

; -------------------------------------------------------------------------------------

; $06 - RAM address low
; $07 - RAM address high

InitializeMemory:
	LDX #$07                                     ; set initial high byte to $0700-$07ff
	LDA #$00                                     ; set initial low byte to start of page (at $00 of page)
	STA $06
InitPageLoop:
	STX $07
InitByteLoop:
	CPX #$01                                     ; check to see if we're on the stack ($0100-$01ff)
	BNE InitByte                                 ; if not, go ahead anyway
	CPY #$60                                     ; otherwise, check to see if we're at $0160-$01ff
	BCS SkipByte                                 ; if so, skip write
InitByte:
	STA ($06),y                                  ; otherwise, initialize byte with current low byte in Y
SkipByte:
	DEY
	CPY #$ff                                     ; do this until all bytes in page have been erased
	BNE InitByteLoop
	DEX                                          ; go onto the next page
	BPL InitPageLoop                             ; do this until all pages of memory have been erased
	RTS

; -------------------------------------------------------------------------------------

MusicSelectData:
	.db WaterMusic, GroundMusic, UndergroundMusic, CastleMusic
	.db CloudMusic, PipeIntroMusic

GetAreaMusic:
	LDA OperMode                                 ; if in title screen mode, leave
	BEQ ExitGetM
	LDA AltEntranceControl                       ; check for specific alternate mode of entry
	CMP #$02                                     ; if found, branch without checking starting position
	BEQ ChkAreaType                              ; from area object data header
	LDY #$05                                     ; select music for pipe intro scene by default
	LDA PlayerEntranceCtrl                       ; check value from level header for certain values
	CMP #$06
	BEQ StoreMusic                               ; load music for pipe intro scene if header
	CMP #$07                                     ; start position either value $06 or $07
	BEQ StoreMusic
ChkAreaType:
	LDY AreaType                                 ; load area type as offset for music bit
	LDA CloudTypeOverride
	BEQ StoreMusic                               ; check for cloud type override
	LDY #$04                                     ; select music for cloud type level if found
StoreMusic:
	LDA MusicSelectData,y                        ; otherwise select appropriate music for level type
	STA AreaMusicQueue                           ; store in queue and leave
ExitGetM:
	RTS

; -------------------------------------------------------------------------------------

PlayerStarting_X_Pos:
	.db $28, $18
	.db $38, $28

AltYPosOffset:
	.db $08, $00

PlayerStarting_Y_Pos:
	.db $00, $20, $b0, $50, $00, $00, $b0, $b0
	.db $f0

PlayerBGPriorityData:
	.db $00, $20, $00, $00, $00, $00, $00, $00

GameTimerData:
	.db $20                                      ; dummy byte, used as part of bg priority data
	.db $04, $03, $02

Entrance_GameTimerSetup:
	LDA ScreenLeft_PageLoc                       ; set current page for area objects
	STA Player_PageLoc                           ; as page location for player
	LDA #$28                                     ; store value here
	STA VerticalForceDown                        ; for fractional movement downwards if necessary
	LDA #$01                                     ; set high byte of player position and
	STA PlayerFacingDir                          ; set facing direction so that player faces right
	STA Player_Y_HighPos
	LDA #$00                                     ; set player state to on the ground by default
	STA Player_State
	DEC Player_CollisionBits                     ; initialize player's collision bits
	LDY #$00                                     ; initialize halfway page
	STY HalfwayPage
	LDA AreaType                                 ; check area type
	BNE ChkStPos                                 ; if water type, set swimming flag, otherwise do not set
	INY
ChkStPos:
	STY SwimmingFlag
	LDX PlayerEntranceCtrl                       ; get starting position loaded from header
	LDY AltEntranceControl                       ; check alternate mode of entry flag for 0 or 1
	BEQ SetStPos
	CPY #$01
	BEQ SetStPos
	LDX AltYPosOffset-2,y                        ; if not 0 or 1, override $0710 with new offset in X
SetStPos:
	LDA PlayerStarting_X_Pos,y                   ; load appropriate horizontal position
	STA Player_X_Position                        ; and vertical positions for the player, using
	LDA PlayerStarting_Y_Pos,x                   ; AltEntranceControl as offset for horizontal and either $0710
	STA Player_Y_Position                        ; or value that overwrote $0710 as offset for vertical
	LDA PlayerBGPriorityData,x
	STA Player_SprAttrib                         ; set player sprite attributes using offset in X
	JSR GetPlayerColors                          ; get appropriate player palette
	LDY GameTimerSetting                         ; get timer control value from header
	BEQ ChkOverR                                 ; if set to zero, branch (do not use dummy byte for this)
	LDA FetchNewGameTimerFlag                    ; do we need to set the game timer? if not, use
	BEQ ChkOverR                                 ; old game timer setting
	LDA GameTimerData,y                          ; if game timer is set and game timer flag is also set,
	STA GameTimerDisplay                         ; use value of game timer control for first digit of game timer
	LDA #$01
	STA GameTimerDisplay+2                       ; set last digit of game timer to 1
	LSR
	STA GameTimerDisplay+1                       ; set second digit of game timer
	STA FetchNewGameTimerFlag                    ; clear flag for game timer reset
	STA StarInvincibleTimer                      ; clear star mario timer
ChkOverR:
	LDY JoypadOverride                           ; if controller bits not set, branch to skip this part
	BEQ ChkSwimE
	LDA #$03                                     ; set player state to climbing
	STA Player_State
	LDX #$00                                     ; set offset for first slot, for block object
	JSR InitBlock_XY_Pos
	LDA #$f0                                     ; set vertical coordinate for block object
	STA Block_Y_Position
	LDX #$05                                     ; set offset in X for last enemy object buffer slot
	LDY #$00                                     ; set offset in Y for object coordinates used earlier
	JSR Setup_Vine                               ; do a sub to grow vine
ChkSwimE:
	LDY AreaType                                 ; if level not water-type,
	BNE SetPESub                                 ; skip this subroutine
	JSR SetupBubble                              ; otherwise, execute sub to set up air bubbles
SetPESub:
	LDA #$07                                     ; set to run player entrance subroutine
	STA GameEngineSubroutine                     ; on the next frame of game engine
	RTS

; -------------------------------------------------------------------------------------

; page numbers are in order from -1 to -4
HalfwayPageNybbles:
	.db $56, $40
	.db $65, $70
	.db $66, $40
	.db $66, $40
	.db $66, $40
	.db $66, $60
	.db $65, $70
	.db $00, $00

PlayerLoseLife:
	INC DisableScreenFlag                        ; disable screen and sprite 0 check
	LDA #$00
	STA Sprite0HitDetectFlag
	LDA #Silence                                 ; silence music
	STA EventMusicQueue
	INC NumberofLives                            ; add one death to player
	BNE StillInGame                              ; if couunter not maxed out
	LDA #$FF
	STA NumberofLives                            ; reset to 255
StillInGame:
	LDA WorldNumber                              ; multiply world number by 2 and use
	ASL                                          ; as offset
	TAX
	LDA LevelNumber                              ; if in area -3 or -4, increment
	AND #$02                                     ; offset by one byte, otherwise
	BEQ GetHalfway                               ; leave offset alone
	INX
GetHalfway:
	LDY HalfwayPageNybbles,x                     ; get halfway page number with offset
	LDA LevelNumber                              ; check area number's LSB
	LSR
	TYA                                          ; if in area -2 or -4, use lower nybble
	BCS MaskHPNyb
	LSR                                          ; move higher nybble to lower if area
	LSR                                          ; number is -1 or -3
	LSR
	LSR
MaskHPNyb:
	AND #%00001111                               ; mask out all but lower nybble
	CMP ScreenLeft_PageLoc
	BEQ SetHalfway                               ; left side of screen must be at the halfway page,
	BCC SetHalfway                               ; otherwise player must start at the
	LDA #$00                                     ; beginning of the level
SetHalfway:
	STA HalfwayPage                              ; store as halfway page for player
	JSR TransposePlayers                         ; switch players around if 2-player game
	JMP ContinueGame                             ; continue the game

; -------------------------------------------------------------------------------------

GameOverMode:
	; nobody here but us chickens

TerminateGame:
	LDA #Silence                                 ; silence music
	STA EventMusicQueue
	JSR TransposePlayers                         ; check if other player can keep
	BCC ContinueGame                             ; going, and do so if possible
	LDA WorldNumber                              ; otherwise put world number of current
	STA ContinueWorld                            ; player into secret continue function variable
	LDA #$00
	ASL                                          ; residual ASL instruction
	STA OperMode_Task                            ; reset all modes to title screen and
	STA ScreenTimer                              ; leave
	STA OperMode
	RTS

ContinueGame:
	JSR LoadAreaPointer                          ; update level pointer with
	LDA #$01                                     ; actual world and area numbers, then
	STA PlayerSize                               ; reset player's size, status, and
	INC FetchNewGameTimerFlag                    ; set game timer flag to reload
	LDA #$00                                     ; game timer from header
	STA TimerControl                             ; also set flag for timers to count again
	STA PlayerStatus
	STA GameEngineSubroutine                     ; reset task for game core
	STA OperMode_Task                            ; set modes and leave
	LDA #$01                                     ; if in game over mode, switch back to
	STA OperMode                                 ; game mode, because game is still on
GameIsOn:
	RTS

TransposePlayers:
	SEC                                          ; set carry flag by default to end game
	LDA NumberOfPlayers                          ; if only a 1 player game, leave
	BEQ ExTrans
	LDA OffScr_NumberofLives                     ; does offscreen player have any lives left?
	BMI ExTrans                                  ; branch if not
	LDA CurrentPlayer                            ; invert bit to update
	EOR #%00000001                               ; which player is on the screen
	STA CurrentPlayer
	LDX #$06
TransLoop:
	LDA OnscreenPlayerInfo,x                     ; transpose the information
	PHA                                          ; of the onscreen player
	LDA OffscreenPlayerInfo,x                    ; with that of the offscreen player
	STA OnscreenPlayerInfo,x
	PLA
	STA OffscreenPlayerInfo,x
	DEX
	BPL TransLoop
	CLC                                          ; clear carry flag to get game going
ExTrans:
	RTS

; -------------------------------------------------------------------------------------

DoNothing1:
	LDA #$ff                                     ; this is residual code, this value is
	STA $06c9                                    ; not used anywhere in the program
DoNothing2:
	RTS

; -------------------------------------------------------------------------------------

AreaParserTaskHandler:
	LDY AreaParserTaskNum                        ; check number of tasks here
	BNE DoAPTasks                                ; if already set, go ahead
	LDY #$08
	STY AreaParserTaskNum                        ; otherwise, set eight by default
DoAPTasks:
	DEY
	TYA
	JSR AreaParserTasks
	DEC AreaParserTaskNum                        ; if all tasks not complete do not
	BNE SkipATRender                             ; render attribute table yet
	JSR RenderAttributeTables
SkipATRender:
	RTS

AreaParserTasks:
	JSR JumpEngine

	.dw IncrementColumnPos
	.dw RenderAreaGraphics
	.dw RenderAreaGraphics
	.dw AreaParserCore
	.dw IncrementColumnPos
	.dw RenderAreaGraphics
	.dw RenderAreaGraphics
	.dw AreaParserCore

; -------------------------------------------------------------------------------------

IncrementColumnPos:
	INC CurrentColumnPos                         ; increment column where we're at
	LDA CurrentColumnPos
	AND #%00001111                               ; mask out higher nybble
	BNE NoColWrap
	STA CurrentColumnPos                         ; if no bits left set, wrap back to zero (0-f)
	INC CurrentPageLoc                           ; and increment page number where we're at
NoColWrap:
	INC BlockBufferColumnPos                     ; increment column offset where we're at
	LDA BlockBufferColumnPos
	AND #%00011111                               ; mask out all but 5 LSB (0-1f)
	STA BlockBufferColumnPos                     ; and save
	RTS

; -------------------------------------------------------------------------------------
; $00 - used as counter, store for low nybble for background, ceiling byte for terrain
; $01 - used to store floor byte for terrain
; $07 - used to store terrain metatile
; $06-$07 - used to store block buffer address

BSceneDataOffsets:
	.db $00, $30, $60

BackSceneryData:
	.db $93, $00, $00, $11, $12, $12, $13, $00   ; clouds
	.db $00, $51, $52, $53, $00, $00, $00, $00
	.db $00, $00, $01, $02, $02, $03, $00, $00
	.db $00, $00, $00, $00, $91, $92, $93, $00
	.db $00, $00, $00, $51, $52, $53, $41, $42
	.db $43, $00, $00, $00, $00, $00, $91, $92

	.db $97, $87, $88, $89, $99, $00, $00, $00   ; mountains and bushes
	.db $11, $12, $13, $a4, $a5, $a5, $a5, $a6
	.db $97, $98, $99, $01, $02, $03, $00, $a4
	.db $a5, $a6, $00, $11, $12, $12, $12, $13
	.db $00, $00, $00, $00, $01, $02, $02, $03
	.db $00, $a4, $a5, $a5, $a6, $00, $00, $00

	.db $11, $12, $12, $13, $00, $00, $00, $00   ; trees and fences
	.db $00, $00, $00, $9c, $00, $8b, $aa, $aa
	.db $aa, $aa, $11, $12, $13, $8b, $00, $9c
	.db $9c, $00, $00, $01, $02, $03, $11, $12
	.db $12, $13, $00, $00, $00, $00, $aa, $aa
	.db $9c, $aa, $00, $8b, $00, $01, $02, $03

BackSceneryMetatiles:
	.db $80, $83, $00                            ; cloud left
	.db $81, $84, $00                            ; cloud middle
	.db $82, $85, $00                            ; cloud right
	.db $02, $00, $00                            ; bush left
	.db $03, $00, $00                            ; bush middle
	.db $04, $00, $00                            ; bush right
	.db $00, $05, $06                            ; mountain left
	.db $07, $06, $0a                            ; mountain middle
	.db $00, $08, $09                            ; mountain right
	.db $4d, $00, $00                            ; fence
	.db $0d, $0f, $4e                            ; tall tree
	.db $0e, $4e, $4e                            ; short tree

FSceneDataOffsets:
	.db $00, $0d, $1a

ForeSceneryData:
	.db $86, $87, $87, $87, $87, $87, $87        ; in water
	.db $87, $87, $87, $87, $69, $69

	.db $00, $00, $00, $00, $00, $45, $47        ; wall
	.db $47, $47, $47, $47, $00, $00

	.db $00, $00, $00, $00, $00, $00, $00        ; over water
	.db $00, $00, $00, $00, $86, $87

TerrainMetatiles:
	.db $69, $54, $52, $62

TerrainRenderBits:
	.db %00000000, %00000000                     ; no ceiling or floor
	.db %00000000, %00011000                     ; no ceiling, floor 2
	.db %00000001, %00011000                     ; ceiling 1, floor 2
	.db %00000111, %00011000                     ; ceiling 3, floor 2
	.db %00001111, %00011000                     ; ceiling 4, floor 2
	.db %11111111, %00011000                     ; ceiling 8, floor 2
	.db %00000001, %00011111                     ; ceiling 1, floor 5
	.db %00000111, %00011111                     ; ceiling 3, floor 5
	.db %00001111, %00011111                     ; ceiling 4, floor 5
	.db %10000001, %00011111                     ; ceiling 1, floor 6
	.db %00000001, %00000000                     ; ceiling 1, no floor
	.db %10001111, %00011111                     ; ceiling 4, floor 6
	.db %11110001, %00011111                     ; ceiling 1, floor 9
	.db %11111001, %00011000                     ; ceiling 1, middle 5, floor 2
	.db %11110001, %00011000                     ; ceiling 1, middle 4, floor 2
	.db %11111111, %00011111                     ; completely solid top to bottom

AreaParserCore:
	LDA BackloadingFlag                          ; check to see if we are starting right of start
	BEQ RenderSceneryTerrain                     ; if not, go ahead and render background, foreground and terrain
	JSR ProcessAreaData                          ; otherwise skip ahead and load level data

RenderSceneryTerrain:
	LDX #$0c
	LDA #$00
ClrMTBuf:
	STA MetatileBuffer,x                         ; clear out metatile buffer
	DEX
	BPL ClrMTBuf
	LDY BackgroundScenery                        ; do we need to render the background scenery?
	BEQ RendFore                                 ; if not, skip to check the foreground
	LDA CurrentPageLoc                           ; otherwise check for every third page
ThirdP:
	CMP #$03
	BMI RendBack                                 ; if less than three we're there
	SEC
	SBC #$03                                     ; if 3 or more, subtract 3 and
	BPL ThirdP                                   ; do an unconditional branch
RendBack:
	ASL                                          ; move results to higher nybble
	ASL
	ASL
	ASL
	ADC BSceneDataOffsets-1,y                    ; add to it offset loaded from here
	ADC CurrentColumnPos                         ; add to the result our current column position
	TAX
	LDA BackSceneryData,x                        ; load data from sum of offsets
	BEQ RendFore                                 ; if zero, no scenery for that part
	PHA
	AND #$0f                                     ; save to stack and clear high nybble
	SEC
	SBC #$01                                     ; subtract one (because low nybble is $01-$0c)
	STA $00                                      ; save low nybble
	ASL                                          ; multiply by three (shift to left and add result to old one)
	ADC $00                                      ; note that since d7 was nulled, the carry flag is always clear
	TAX                                          ; save as offset for background scenery metatile data
	PLA                                          ; get high nybble from stack, move low
	LSR
	LSR
	LSR
	LSR
	TAY                                          ; use as second offset (used to determine height)
	LDA #$03                                     ; use previously saved memory location for counter
	STA $00
SceLoop1:
	LDA BackSceneryMetatiles,x                   ; load metatile data from offset of (lsb - 1) * 3
	STA MetatileBuffer,y                         ; store into buffer from offset of (msb / 16)
	INX
	INY
	CPY #$0b                                     ; if at this location, leave loop
	BEQ RendFore
	DEC $00                                      ; decrement until counter expires, barring exception
	BNE SceLoop1
RendFore:
	LDX ForegroundScenery                        ; check for foreground data needed or not
	BEQ RendTerr                                 ; if not, skip this part
	LDY FSceneDataOffsets-1,x                    ; load offset from location offset by header value, then
	LDX #$00                                     ; reinit X
SceLoop2:
	LDA ForeSceneryData,y                        ; load data until counter expires
	BEQ NoFore                                   ; do not store if zero found
	STA MetatileBuffer,x
NoFore:
	INY
	INX
	CPX #$0d                                     ; store up to end of metatile buffer
	BNE SceLoop2
RendTerr:
	LDY AreaType                                 ; check world type for water level
	BNE TerMTile                                 ; if not water level, skip this part
	LDA WorldNumber                              ; check world number, if not world number eight
	CMP #World8                                  ; then skip this part
	BNE TerMTile
	LDA #$62                                     ; if set as water level and world number eight,
	JMP StoreMT                                  ; use castle wall metatile as terrain type
TerMTile:
	LDA TerrainMetatiles,y                       ; otherwise get appropriate metatile for area type
	LDY CloudTypeOverride                        ; check for cloud type override
	BEQ StoreMT                                  ; if not set, keep value otherwise
	LDA #$88                                     ; use cloud block terrain
StoreMT:
	STA $07                                      ; store value here
	LDX #$00                                     ; initialize X, use as metatile buffer offset
	LDA TerrainControl                           ; use yet another value from the header
	ASL                                          ; multiply by 2 and use as yet another offset
	TAY
TerrLoop:
	LDA TerrainRenderBits,y                      ; get one of the terrain rendering bit data
	STA $00
	INY                                          ; increment Y and use as offset next time around
	STY $01
	LDA CloudTypeOverride                        ; skip if value here is zero
	BEQ NoCloud2
	CPX #$00                                     ; otherwise, check if we're doing the ceiling byte
	BEQ NoCloud2
	LDA $00                                      ; if not, mask out all but d3
	AND #%00001000
	STA $00
NoCloud2:
	LDY #$00                                     ; start at beginning of bitmasks
TerrBChk:
	LDA Bitmasks,y                               ; load bitmask, then perform AND on contents of first byte
	BIT $00
	BEQ NextTBit                                 ; if not set, skip this part (do not write terrain to buffer)
	LDA $07
	STA MetatileBuffer,x                         ; load terrain type metatile number and store into buffer here
NextTBit:
	INX                                          ; continue until end of buffer
	CPX #$0d
	BEQ RendBBuf                                 ; if we're at the end, break out of this loop
	LDA AreaType                                 ; check world type for underground area
	CMP #$02
	BNE EndUChk                                  ; if not underground, skip this part
	CPX #$0b
	BNE EndUChk                                  ; if we're at the bottom of the screen, override
	LDA #$54                                     ; old terrain type with ground level terrain type
	STA $07
EndUChk:
	INY                                          ; increment bitmasks offset in Y
	CPY #$08
	BNE TerrBChk                                 ; if not all bits checked, loop back
	LDY $01
	BNE TerrLoop                                 ; unconditional branch, use Y to load next byte
RendBBuf:
	JSR ProcessAreaData                          ; do the area data loading routine now
	LDA BlockBufferColumnPos
	JSR GetBlockBufferAddr                       ; get block buffer address from where we're at
	LDX #$00
	LDY #$00                                     ; init index regs and start at beginning of smaller buffer
ChkMTLow:
	STY $00
	LDA MetatileBuffer,x                         ; load stored metatile number
	AND #%11000000                               ; mask out all but 2 MSB
	ASL
	ROL                                          ; make %xx000000 into %000000xx
	ROL
	TAY                                          ; use as offset in Y
	LDA MetatileBuffer,x                         ; reload original unmasked value here
	CMP BlockBuffLowBounds,y                     ; check for certain values depending on bits set
	BCS StrBlock                                 ; if equal or greater, branch
	LDA #$00                                     ; if less, init value before storing
StrBlock:
	LDY $00                                      ; get offset for block buffer
	STA ($06),y                                  ; store value into block buffer
	TYA
	CLC                                          ; add 16 (move down one row) to offset
	ADC #$10
	TAY
	INX                                          ; increment column value
	CPX #$0d
	BCC ChkMTLow                                 ; continue until we pass last row, then leave
	RTS

; numbers lower than these with the same attribute bits
; will not be stored in the block buffer
BlockBuffLowBounds:
	.db $10, $51, $88, $c0

; -------------------------------------------------------------------------------------
; $00 - used to store area object identifier
; $07 - used as adder to find proper area object code

ProcessAreaData:
	LDX #$02                                     ; start at the end of area object buffer
ProcADLoop:
	STX ObjectOffset
	LDA #$00                                     ; reset flag
	STA BehindAreaParserFlag
	LDY AreaDataOffset                           ; get offset of area data pointer
	LDA (AreaData),y                             ; get first byte of area object
	CMP #$fd                                     ; if end-of-area, skip all this crap
	BEQ RdyDecode
	LDA AreaObjectLength,x                       ; check area object buffer flag
	BPL RdyDecode                                ; if buffer not negative, branch, otherwise
	INY
	LDA (AreaData),y                             ; get second byte of area object
	ASL                                          ; check for page select bit (d7), branch if not set
	BCC Chk1Row13
	LDA AreaObjectPageSel                        ; check page select
	BNE Chk1Row13
	INC AreaObjectPageSel                        ; if not already set, set it now
	INC AreaObjectPageLoc                        ; and increment page location
Chk1Row13:
	DEY
	LDA (AreaData),y                             ; reread first byte of level object
	AND #$0f                                     ; mask out high nybble
	CMP #$0d                                     ; row 13?
	BNE Chk1Row14
	INY                                          ; if so, reread second byte of level object
	LDA (AreaData),y
	DEY                                          ; decrement to get ready to read first byte
	AND #%01000000                               ; check for d6 set (if not, object is page control)
	BNE CheckRear
	LDA AreaObjectPageSel                        ; if page select is set, do not reread
	BNE CheckRear
	INY                                          ; if d6 not set, reread second byte
	LDA (AreaData),y
	AND #%00011111                               ; mask out all but 5 LSB and store in page control
	STA AreaObjectPageLoc
	INC AreaObjectPageSel                        ; increment page select
	JMP NextAObj
Chk1Row14:
	CMP #$0e                                     ; row 14?
	BNE CheckRear
	LDA BackloadingFlag                          ; check flag for saved page number and branch if set
	BNE RdyDecode                                ; to render the object (otherwise bg might not look right)
CheckRear:
	LDA AreaObjectPageLoc                        ; check to see if current page of level object is
	CMP CurrentPageLoc                           ; behind current page of renderer
	BCC SetBehind                                ; if so branch
RdyDecode:
	JSR DecodeAreaData                           ; do sub and do not turn on flag
	JMP ChkLength
SetBehind:
	INC BehindAreaParserFlag                     ; turn on flag if object is behind renderer
NextAObj:
	JSR IncAreaObjOffset                         ; increment buffer offset and move on
ChkLength:
	LDX ObjectOffset                             ; get buffer offset
	LDA AreaObjectLength,x                       ; check object length for anything stored here
	BMI ProcLoopb                                ; if not, branch to handle loopback
	DEC AreaObjectLength,x                       ; otherwise decrement length or get rid of it
ProcLoopb:
	DEX                                          ; decrement buffer offset
	BPL ProcADLoop                               ; and loopback unless exceeded buffer
	LDA BehindAreaParserFlag                     ; check for flag set if objects were behind renderer
	BNE ProcessAreaData                          ; branch if true to load more level data, otherwise
	LDA BackloadingFlag                          ; check for flag set if starting right of page $00
	BNE ProcessAreaData                          ; branch if true to load more level data, otherwise leave
EndAParse:
	RTS

IncAreaObjOffset:
	INC AreaDataOffset                           ; increment offset of level pointer
	INC AreaDataOffset
	LDA #$00                                     ; reset page select
	STA AreaObjectPageSel
	RTS

DecodeAreaData:
	LDA AreaObjectLength,x                       ; check current buffer flag
	BMI Chk1stB
	LDY AreaObjOffsetBuffer,x                    ; if not, get offset from buffer
Chk1stB:
	LDX #$10                                     ; load offset of 16 for special row 15
	LDA (AreaData),y                             ; get first byte of level object again
	CMP #$fd
	BEQ EndAParse                                ; if end of level, leave this routine
	AND #$0f                                     ; otherwise, mask out low nybble
	CMP #$0f                                     ; row 15?
	BEQ ChkRow14                                 ; if so, keep the offset of 16
	LDX #$08                                     ; otherwise load offset of 8 for special row 12
	CMP #$0c                                     ; row 12?
	BEQ ChkRow14                                 ; if so, keep the offset value of 8
	LDX #$00                                     ; otherwise nullify value by default
ChkRow14:
	STX $07                                      ; store whatever value we just loaded here
	LDX ObjectOffset                             ; get object offset again
	CMP #$0e                                     ; row 14?
	BNE ChkRow13
	LDA #$00                                     ; if so, load offset with $00
	STA $07
	LDA #$2e                                     ; and load A with another value
	BNE NormObj                                  ; unconditional branch
ChkRow13:
	CMP #$0d                                     ; row 13?
	BNE ChkSRows
	LDA #$22                                     ; if so, load offset with 34
	STA $07
	INY                                          ; get next byte
	LDA (AreaData),y
	AND #%01000000                               ; mask out all but d6 (page control obj bit)
	BEQ LeavePar                                 ; if d6 clear, branch to leave (we handled this earlier)
	LDA (AreaData),y                             ; otherwise, get byte again
	AND #%01111111                               ; mask out d7
	CMP #$4b                                     ; check for loop command in low nybble
	BNE Mask2MSB                                 ; (plus d6 set for object other than page control)
	INC LoopCommand                              ; if loop command, set loop command flag
Mask2MSB:
	AND #%00111111                               ; mask out d7 and d6
	JMP NormObj                                  ; and jump
ChkSRows:
	CMP #$0c                                     ; row 12-15?
	BCS SpecObj
	INY                                          ; if not, get second byte of level object
	LDA (AreaData),y
	AND #%01110000                               ; mask out all but d6-d4
	BNE LrgObj                                   ; if any bits set, branch to handle large object
	LDA #$16
	STA $07                                      ; otherwise set offset of 24 for small object
	LDA (AreaData),y                             ; reload second byte of level object
	AND #%00001111                               ; mask out higher nybble and jump
	JMP NormObj
LrgObj:
	STA $00                                      ; store value here (branch for large objects)
	CMP #$70                                     ; check for vertical pipe object
	BNE NotWPipe
	LDA (AreaData),y                             ; if not, reload second byte
	AND #%00001000                               ; mask out all but d3 (usage control bit)
	BEQ NotWPipe                                 ; if d3 clear, branch to get original value
	LDA #$00                                     ; otherwise, nullify value for warp pipe
	STA $00
NotWPipe:
	LDA $00                                      ; get value and jump ahead
	JMP MoveAOId
SpecObj:
	INY                                          ; branch here for rows 12-15
	LDA (AreaData),y
	AND #%01110000                               ; get next byte and mask out all but d6-d4
MoveAOId:
	LSR                                          ; move d6-d4 to lower nybble
	LSR
	LSR
	LSR
NormObj:
	STA $00                                      ; store value here (branch for small objects and rows 13 and 14)
	LDA AreaObjectLength,x                       ; is there something stored here already?
	BPL RunAObj                                  ; if so, branch to do its particular sub
	LDA AreaObjectPageLoc                        ; otherwise check to see if the object we've loaded is on the
	CMP CurrentPageLoc                           ; same page as the renderer, and if so, branch
	BEQ InitRear
	LDY AreaDataOffset                           ; if not, get old offset of level pointer
	LDA (AreaData),y                             ; and reload first byte
	AND #%00001111
	CMP #$0e                                     ; row 14?
	BNE LeavePar
	LDA BackloadingFlag                          ; if so, check backloading flag
	BNE StrAObj                                  ; if set, branch to render object, else leave
LeavePar:
	RTS
InitRear:
	LDA BackloadingFlag                          ; check backloading flag to see if it's been initialized
	BEQ BackColC                                 ; branch to column-wise check
	LDA #$00                                     ; if not, initialize both backloading and
	STA BackloadingFlag                          ; behind-renderer flags and leave
	STA BehindAreaParserFlag
	STA ObjectOffset
LoopCmdE:
	RTS
BackColC:
	LDY AreaDataOffset                           ; get first byte again
	LDA (AreaData),y
	AND #%11110000                               ; mask out low nybble and move high to low
	LSR
	LSR
	LSR
	LSR
	CMP CurrentColumnPos                         ; is this where we're at?
	BNE LeavePar                                 ; if not, branch to leave
StrAObj:
	LDA AreaDataOffset                           ; if so, load area obj offset and store in buffer
	STA AreaObjOffsetBuffer,x
	JSR IncAreaObjOffset                         ; do sub to increment to next object data
RunAObj:
	LDA $00                                      ; get stored value and add offset to it
	CLC                                          ; then use the jump engine with current contents of A
	ADC $07
	JSR JumpEngine

; large objects (rows $00-$0b or 00-11, d6-d4 set)
	.dw VerticalPipe                             ; used by warp pipes
	.dw AreaStyleObject
	.dw RowOfBricks
	.dw RowOfSolidBlocks
	.dw RowOfCoins
	.dw ColumnOfBricks
	.dw ColumnOfSolidBlocks
	.dw VerticalPipe                             ; used by decoration pipes

; objects for special row $0c or 12
	.dw Hole_Empty
	.dw PulleyRopeObject
	.dw Bridge_High
	.dw Bridge_Middle
	.dw Bridge_Low
	.dw Hole_Water
	.dw QuestionBlockRow_High
	.dw QuestionBlockRow_Low

; objects for special row $0f or 15
	.dw EndlessRope
	.dw BalancePlatRope
	.dw CastleObject
	.dw StaircaseObject
	.dw ExitPipe
	.dw FlagBalls_Residual

; small objects (rows $00-$0b or 00-11, d6-d4 all clear)
	.dw QuestionBlock                            ; power-up
	.dw QuestionBlock                            ; coin
	.dw QuestionBlock                            ; hidden, coin
	.dw Hidden1UpBlock                           ; hidden, 1-up
	.dw BrickWithItem                            ; brick, power-up
	.dw BrickWithItem                            ; brick, vine
	.dw BrickWithItem                            ; brick, star
	.dw BrickWithCoins                           ; brick, coins
	.dw BrickWithItem                            ; brick, 1-up
	.dw WaterPipe
	.dw EmptyBlock
	.dw Jumpspring

; objects for special row $0d or 13 (d6 set)
	.dw IntroPipe
	.dw FlagpoleObject
	.dw AxeObj
	.dw ChainObj
	.dw CastleBridgeObj
	.dw ScrollLockObject_Warp
	.dw ScrollLockObject
	.dw ScrollLockObject
	.dw AreaFrenzy                               ; flying cheep-cheeps
	.dw AreaFrenzy                               ; bullet bills or swimming cheep-cheeps
	.dw AreaFrenzy                               ; stop frenzy
	.dw LoopCmdE

; object for special row $0e or 14
	.dw AlterAreaAttributes

; -------------------------------------------------------------------------------------
; (these apply to all area object subroutines in this section unless otherwise stated)
; $00 - used to store offset used to find object code
; $07 - starts with adder from area parser, used to store row offset

AlterAreaAttributes:
	LDY AreaObjOffsetBuffer,x                    ; load offset for level object data saved in buffer
	INY                                          ; load second byte
	LDA (AreaData),y
	PHA                                          ; save in stack for now
	AND #%01000000
	BNE Alter2                                   ; branch if d6 is set
	PLA
	PHA                                          ; pull and push offset to copy to A
	AND #%00001111                               ; mask out high nybble and store as
	STA TerrainControl                           ; new terrain height type bits
	PLA
	AND #%00110000                               ; pull and mask out all but d5 and d4
	LSR                                          ; move bits to lower nybble and store
	LSR                                          ; as new background scenery bits
	LSR
	LSR
	STA BackgroundScenery                        ; then leave
	RTS
Alter2:
	PLA
	AND #%00000111                               ; mask out all but 3 LSB
	CMP #$04                                     ; if four or greater, set color control bits
	BCC SetFore                                  ; and nullify foreground scenery bits
	STA BackgroundColorCtrl
	LDA #$00
SetFore:
	STA ForegroundScenery                        ; otherwise set new foreground scenery bits
	RTS

; --------------------------------

ScrollLockObject_Warp:
	LDX #$04                                     ; load value of 4 for game text routine as default
	LDA WorldNumber                              ; warp zone (4-3-2), then check world number
	BEQ WarpNum
	INX                                          ; if world number > 1, increment for next warp zone (5)
	LDY AreaType                                 ; check area type
	DEY
	BNE WarpNum                                  ; if ground area type, increment for last warp zone
	INX                                          ; (8-7-6) and move on
WarpNum:
	TXA
	STA WarpZoneControl                          ; store number here to be used by warp zone routine
	JSR WriteGameText                            ; print text and warp zone numbers
	LDA #PiranhaPlant
	JSR KillEnemies                              ; load identifier for piranha plants and do sub

ScrollLockObject:
	LDA ScrollLock                               ; invert scroll lock to turn it on
	EOR #%00000001
	STA ScrollLock
	RTS

; --------------------------------
; $00 - used to store enemy identifier in KillEnemies

KillEnemies:
	STA $00                                      ; store identifier here
	LDA #$00
	LDX #$04                                     ; check for identifier in enemy object buffer
KillELoop:
	LDY Enemy_ID,x
	CPY $00                                      ; if not found, branch
	BNE NoKillE
	STA Enemy_Flag,x                             ; if found, deactivate enemy object flag
NoKillE:
	DEX                                          ; do this until all slots are checked
	BPL KillELoop
	RTS

; --------------------------------

FrenzyIDData:
	.db FlyCheepCheepFrenzy, BBill_CCheep_Frenzy, Stop_Frenzy

AreaFrenzy:
	LDX $00                                      ; use area object identifier bit as offset
	LDA FrenzyIDData-8,x                         ; note that it starts at 8, thus weird address here
	LDY #$05
FreCompLoop:
	DEY                                          ; check regular slots of enemy object buffer
	BMI ExitAFrenzy                              ; if all slots checked and enemy object not found, branch to store
	CMP Enemy_ID,y                               ; check for enemy object in buffer versus frenzy object
	BNE FreCompLoop
	LDA #$00                                     ; if enemy object already present, nullify queue and leave
ExitAFrenzy:
	STA EnemyFrenzyQueue                         ; store enemy into frenzy queue
	RTS

; --------------------------------
; $06 - used by MushroomLedge to store length

AreaStyleObject:
	LDA AreaStyle                                ; load level object style and jump to the right sub
	JSR JumpEngine
	.dw TreeLedge                                ; also used for cloud type levels
	.dw MushroomLedge
	.dw BulletBillCannon

TreeLedge:
	JSR GetLrgObjAttrib                          ; get row and length of green ledge
	LDA AreaObjectLength,x                       ; check length counter for expiration
	BEQ EndTreeL
	BPL MidTreeL
	TYA
	STA AreaObjectLength,x                       ; store lower nybble into buffer flag as length of ledge
	LDA CurrentPageLoc
	ORA CurrentColumnPos                         ; are we at the start of the level?
	BEQ MidTreeL
	LDA #$16                                     ; render start of tree ledge
	JMP NoUnder
MidTreeL:
	LDX $07
	LDA #$17                                     ; render middle of tree ledge
	STA MetatileBuffer,x                         ; note that this is also used if ledge position is
	LDA #$4c                                     ; at the start of level for continuous effect
	JMP AllUnder                                 ; now render the part underneath
EndTreeL:
	LDA #$18                                     ; render end of tree ledge
	JMP NoUnder

MushroomLedge:
	JSR ChkLrgObjLength                          ; get shroom dimensions
	STY $06                                      ; store length here for now
	BCC EndMushL
	LDA AreaObjectLength,x                       ; divide length by 2 and store elsewhere
	LSR
	STA MushroomLedgeHalfLen,x
	LDA #$19                                     ; render start of mushroom
	JMP NoUnder
EndMushL:
	LDA #$1b                                     ; if at the end, render end of mushroom
	LDY AreaObjectLength,x
	BEQ NoUnder
	LDA MushroomLedgeHalfLen,x                   ; get divided length and store where length
	STA $06                                      ; was stored originally
	LDX $07
	LDA #$1a
	STA MetatileBuffer,x                         ; render middle of mushroom
	CPY $06                                      ; are we smack dab in the center?
	BNE MushLExit                                ; if not, branch to leave
	INX
	LDA #$4f
	STA MetatileBuffer,x                         ; render stem top of mushroom underneath the middle
	LDA #$50
AllUnder:
	INX
	LDY #$0f                                     ; set $0f to render all way down
	JMP RenderUnderPart                          ; now render the stem of mushroom
NoUnder:
	LDX $07                                      ; load row of ledge
	LDY #$00                                     ; set 0 for no bottom on this part
	JMP RenderUnderPart

; --------------------------------

; tiles used by pulleys and rope object
PulleyRopeMetatiles:
	.db $42, $41, $43

PulleyRopeObject:
	JSR ChkLrgObjLength                          ; get length of pulley/rope object
	LDY #$00                                     ; initialize metatile offset
	BCS RenderPul                                ; if starting, render left pulley
	INY
	LDA AreaObjectLength,x                       ; if not at the end, render rope
	BNE RenderPul
	INY                                          ; otherwise render right pulley
RenderPul:
	LDA PulleyRopeMetatiles,y
	STA MetatileBuffer                           ; render at the top of the screen
MushLExit:
	RTS                                          ; and leave

; --------------------------------
; $06 - used to store upper limit of rows for CastleObject

CastleMetatiles:
	.db $00, $45, $45, $45, $00
	.db $00, $48, $47, $46, $00
	.db $45, $49, $49, $49, $45
	.db $47, $47, $4a, $47, $47
	.db $47, $47, $4b, $47, $47
	.db $49, $49, $49, $49, $49
	.db $47, $4a, $47, $4a, $47
	.db $47, $4b, $47, $4b, $47
	.db $47, $47, $47, $47, $47
	.db $4a, $47, $4a, $47, $4a
	.db $4b, $47, $4b, $47, $4b

CastleObject:
	JSR GetLrgObjAttrib                          ; save lower nybble as starting row
	STY $07                                      ; if starting row is above $0a, game will crash!!!
	LDY #$04
	JSR ChkLrgObjFixedLength                     ; load length of castle if not already loaded
	TXA
	PHA                                          ; save obj buffer offset to stack
	LDY AreaObjectLength,x                       ; use current length as offset for castle data
	LDX $07                                      ; begin at starting row
	LDA #$0b
	STA $06                                      ; load upper limit of number of rows to print
CRendLoop:
	LDA CastleMetatiles,y                        ; load current byte using offset
	STA MetatileBuffer,x
	INX                                          ; store in buffer and increment buffer offset
	LDA $06
	BEQ ChkCFloor                                ; have we reached upper limit yet?
	INY                                          ; if not, increment column-wise
	INY                                          ; to byte in next row
	INY
	INY
	INY
	DEC $06                                      ; move closer to upper limit
ChkCFloor:
	CPX #$0b                                     ; have we reached the row just before floor?
	BNE CRendLoop                                ; if not, go back and do another row
	PLA
	TAX                                          ; get obj buffer offset from before
	LDA CurrentPageLoc
	BEQ ExitCastle                               ; if we're at page 0, we do not need to do anything else
	LDA AreaObjectLength,x                       ; check length
	CMP #$01                                     ; if length almost about to expire, put brick at floor
	BEQ PlayerStop
	LDY $07                                      ; check starting row for tall castle ($00)
	BNE NotTall
	CMP #$03                                     ; if found, then check to see if we're at the second column
	BEQ PlayerStop
NotTall:
	CMP #$02                                     ; if not tall castle, check to see if we're at the third column
	BNE ExitCastle                               ; if we aren't and the castle is tall, don't create flag yet
	JSR GetAreaObjXPosition                      ; otherwise, obtain and save horizontal pixel coordinate
	PHA
	JSR FindEmptyEnemySlot                       ; find an empty place on the enemy object buffer
	PLA
	STA Enemy_X_Position,x                       ; then write horizontal coordinate for star flag
	LDA CurrentPageLoc
	STA Enemy_PageLoc,x                          ; set page location for star flag
	LDA #$01
	STA Enemy_Y_HighPos,x                        ; set vertical high byte
	STA Enemy_Flag,x                             ; set flag for buffer
	LDA #$90
	STA Enemy_Y_Position,x                       ; set vertical coordinate
	LDA #StarFlagObject                          ; set star flag value in buffer itself
	STA Enemy_ID,x
	RTS
PlayerStop:
	LDY #$52                                     ; put brick at floor to stop player at end of level
	STY MetatileBuffer+10                        ; this is only done if we're on the second column
ExitCastle:
	RTS

; --------------------------------

WaterPipe:
	JSR GetLrgObjAttrib                          ; get row and lower nybble
	LDY AreaObjectLength,x                       ; get length (residual code, water pipe is 1 col thick)
	LDX $07                                      ; get row
	LDA #$6b
	STA MetatileBuffer,x                         ; draw something here and below it
	LDA #$6c
	STA MetatileBuffer+1,x
	RTS

; --------------------------------
; $05 - used to store length of vertical shaft in RenderSidewaysPipe
; $06 - used to store leftover horizontal length in RenderSidewaysPipe
; and vertical length in VerticalPipe and GetPipeHeight

IntroPipe:
	LDY #$03                                     ; check if length set, if not set, set it
	JSR ChkLrgObjFixedLength
	LDY #$0a                                     ; set fixed value and render the sideways part
	JSR RenderSidewaysPipe
	BCS NoBlankP                                 ; if carry flag set, not time to draw vertical pipe part
	LDX #$06                                     ; blank everything above the vertical pipe part
VPipeSectLoop:
	LDA #$00                                     ; all the way to the top of the screen
	STA MetatileBuffer,x                         ; because otherwise it will look like exit pipe
	DEX
	BPL VPipeSectLoop
	LDA VerticalPipeData,y                       ; draw the end of the vertical pipe part
	STA MetatileBuffer+7
NoBlankP:
	RTS

SidePipeShaftData:
	.db $15, $14                                 ; used to control whether or not vertical pipe shaft
	.db $00, $00                                 ; is drawn, and if so, controls the metatile number
SidePipeTopPart:
	.db $15, $1e                                 ; top part of sideways part of pipe
	.db $1d, $1c
SidePipeBottomPart:

	.db $15, $21                                 ; bottom part of sideways part of pipe
	.db $20, $1f

ExitPipe:
	LDY #$03                                     ; check if length set, if not set, set it
	JSR ChkLrgObjFixedLength
	JSR GetLrgObjAttrib                          ; get vertical length, then plow on through RenderSidewaysPipe

RenderSidewaysPipe:
	DEY                                          ; decrement twice to make room for shaft at bottom
	DEY                                          ; and store here for now as vertical length
	STY $05
	LDY AreaObjectLength,x                       ; get length left over and store here
	STY $06
	LDX $05                                      ; get vertical length plus one, use as buffer offset
	INX
	LDA SidePipeShaftData,y                      ; check for value $00 based on horizontal offset
	CMP #$00
	BEQ DrawSidePart                             ; if found, do not draw the vertical pipe shaft
	LDX #$00
	LDY $05                                      ; init buffer offset and get vertical length
	JSR RenderUnderPart                          ; and render vertical shaft using tile number in A
	CLC                                          ; clear carry flag to be used by IntroPipe
DrawSidePart:
	LDY $06                                      ; render side pipe part at the bottom
	LDA SidePipeTopPart,y
	STA MetatileBuffer,x                         ; note that the pipe parts are stored
	LDA SidePipeBottomPart,y                     ; backwards horizontally
	STA MetatileBuffer+1,x
	RTS

VerticalPipeData:
	.db $11, $10                                 ; used by pipes that lead somewhere
	.db $15, $14
	.db $13, $12                                 ; used by decoration pipes
	.db $15, $14

VerticalPipe:
	JSR GetPipeHeight
	LDA $00                                      ; check to see if value was nullified earlier
	BEQ WarpPipe                                 ; (if d3, the usage control bit of second byte, was set)
	INY
	INY
	INY
	INY                                          ; add four if usage control bit was not set
WarpPipe:
	TYA                                          ; save value in stack
	PHA
	LDA AreaNumber
	ORA WorldNumber                              ; if at world 1-1, do not add piranha plant ever
	BEQ DrawPipe
	LDY AreaObjectLength,x                       ; if on second column of pipe, branch
	BEQ DrawPipe                                 ; (because we only need to do this once)
	JSR FindEmptyEnemySlot                       ; check for an empty moving data buffer space
	BCS DrawPipe                                 ; if not found, too many enemies, thus skip
	JSR GetAreaObjXPosition                      ; get horizontal pixel coordinate
	CLC
	ADC #$08                                     ; add eight to put the piranha plant in the center
	STA Enemy_X_Position,x                       ; store as enemy's horizontal coordinate
	LDA CurrentPageLoc                           ; add carry to current page number
	ADC #$00
	STA Enemy_PageLoc,x                          ; store as enemy's page coordinate
	LDA #$01
	STA Enemy_Y_HighPos,x
	STA Enemy_Flag,x                             ; activate enemy flag
	JSR GetAreaObjYPosition                      ; get piranha plant's vertical coordinate and store here
	STA Enemy_Y_Position,x
	LDA #PiranhaPlant                            ; write piranha plant's value into buffer
	STA Enemy_ID,x
	JSR InitPiranhaPlant
DrawPipe:
	PLA                                          ; get value saved earlier and use as Y
	TAY
	LDX $07                                      ; get buffer offset
	LDA VerticalPipeData,y                       ; draw the appropriate pipe with the Y we loaded earlier
	STA MetatileBuffer,x                         ; render the top of the pipe
	INX
	LDA VerticalPipeData+2,y                     ; render the rest of the pipe
	LDY $06                                      ; subtract one from length and render the part underneath
	DEY
	JMP RenderUnderPart

GetPipeHeight:
	LDY #$01                                     ; check for length loaded, if not, load
	JSR ChkLrgObjFixedLength                     ; pipe length of 2 (horizontal)
	JSR GetLrgObjAttrib
	TYA                                          ; get saved lower nybble as height
	AND #$07                                     ; save only the three lower bits as
	STA $06                                      ; vertical length, then load Y with
	LDY AreaObjectLength,x                       ; length left over
	RTS

FindEmptyEnemySlot:
	LDX #$00                                     ; start at first enemy slot
EmptyChkLoop:
	CLC                                          ; clear carry flag by default
	LDA Enemy_Flag,x                             ; check enemy buffer for nonzero
	BEQ ExitEmptyChk                             ; if zero, leave
	INX
	CPX #$05                                     ; if nonzero, check next value
	BNE EmptyChkLoop
ExitEmptyChk:
	RTS                                          ; if all values nonzero, carry flag is set

; --------------------------------

Hole_Water:
	JSR ChkLrgObjLength                          ; get low nybble and save as length
	LDA #$86                                     ; render waves
	STA MetatileBuffer+10
	LDX #$0b
	LDY #$01                                     ; now render the water underneath
	LDA #$87
	JMP RenderUnderPart

; --------------------------------

QuestionBlockRow_High:
	LDA #$03                                     ; start on the fourth row
	.db $2c                                      ; BIT instruction opcode

QuestionBlockRow_Low:
	LDA #$07                                     ; start on the eighth row
	PHA                                          ; save whatever row to the stack for now
	JSR ChkLrgObjLength                          ; get low nybble and save as length
	PLA
	TAX                                          ; render question boxes with coins
	LDA #$c0
	STA MetatileBuffer,x
	RTS

; --------------------------------

Bridge_High:
	LDA #$06                                     ; start on the seventh row from top of screen
	.db $2c                                      ; BIT instruction opcode

Bridge_Middle:
	LDA #$07                                     ; start on the eighth row
	.db $2c                                      ; BIT instruction opcode

Bridge_Low:
	LDA #$09                                     ; start on the tenth row
	PHA                                          ; save whatever row to the stack for now
	JSR ChkLrgObjLength                          ; get low nybble and save as length
	PLA
	TAX                                          ; render bridge railing
	LDA #$0b
	STA MetatileBuffer,x
	INX
	LDY #$00                                     ; now render the bridge itself
	LDA #$63
	JMP RenderUnderPart

; --------------------------------

FlagBalls_Residual:
	JSR GetLrgObjAttrib                          ; get low nybble from object byte
	LDX #$02                                     ; render flag balls on third row from top
	LDA #$6d                                     ; of screen downwards based on low nybble
	JMP RenderUnderPart

; --------------------------------

FlagpoleObject:
	LDA #$24                                     ; render flagpole ball on top
	STA MetatileBuffer
	LDX #$01                                     ; now render the flagpole shaft
	LDY #$08
	LDA #$25
	JSR RenderUnderPart
	LDA #$61                                     ; render solid block at the bottom
	STA MetatileBuffer+10
	JSR GetAreaObjXPosition
	SEC                                          ; get pixel coordinate of where the flagpole is,
	SBC #$08                                     ; subtract eight pixels and use as horizontal
	STA Enemy_X_Position+5                       ; coordinate for the flag
	LDA CurrentPageLoc
	SBC #$00                                     ; subtract borrow from page location and use as
	STA Enemy_PageLoc+5                          ; page location for the flag
	LDA #$30
	STA Enemy_Y_Position+5                       ; set vertical coordinate for flag
	LDA #$b0
	STA FlagpoleFNum_Y_Pos                       ; set initial vertical coordinate for flagpole's floatey number
	LDA #FlagpoleFlagObject
	STA Enemy_ID+5                               ; set flag identifier, note that identifier and coordinates
	INC Enemy_Flag+5                             ; use last space in enemy object buffer
	RTS

; --------------------------------

EndlessRope:
	LDX #$00                                     ; render rope from the top to the bottom of screen
	LDY #$0f
	JMP DrawRope

BalancePlatRope:
	TXA                                          ; save object buffer offset for now
	PHA
	LDX #$01                                     ; blank out all from second row to the bottom
	LDY #$0f                                     ; with blank used for balance platform rope
	LDA #$44
	JSR RenderUnderPart
	PLA                                          ; get back object buffer offset
	TAX
	JSR GetLrgObjAttrib                          ; get vertical length from lower nybble
	LDX #$01
DrawRope:
	LDA #$40                                     ; render the actual rope
	JMP RenderUnderPart

; --------------------------------

CoinMetatileData:
	.db $c3, $c2, $c2, $c2

RowOfCoins:
	LDY AreaType                                 ; get area type
	LDA CoinMetatileData,y                       ; load appropriate coin metatile
	JMP GetRow

; --------------------------------

C_ObjectRow:
	.db $06, $07, $08

C_ObjectMetatile:
	.db $c5, $0c, $89

CastleBridgeObj:
	LDY #$0c                                     ; load length of 13 columns
	JSR ChkLrgObjFixedLength
	JMP ChainObj

AxeObj:
	LDA #$08                                     ; load bowser's palette into sprite portion of palette
	STA VRAM_Buffer_AddrCtrl

ChainObj:
	LDY $00                                      ; get value loaded earlier from decoder
	LDX C_ObjectRow-2,y                          ; get appropriate row and metatile for object
	LDA C_ObjectMetatile-2,y
	JMP ColObj

EmptyBlock:
	JSR GetLrgObjAttrib                          ; get row location
	LDX $07
	LDA #$c4
ColObj:
	LDY #$00                                     ; column length of 1
	JMP RenderUnderPart

; --------------------------------

SolidBlockMetatiles:
	.db $69, $61, $61, $62

BrickMetatiles:
	.db $22, $51, $52, $52
	.db $88                                      ; used only by row of bricks object

RowOfBricks:
	LDY AreaType                                 ; load area type obtained from area offset pointer
	LDA CloudTypeOverride                        ; check for cloud type override
	BEQ DrawBricks
	LDY #$04                                     ; if cloud type, override area type
DrawBricks:
	LDA BrickMetatiles,y                         ; get appropriate metatile
	JMP GetRow                                   ; and go render it

RowOfSolidBlocks:
	LDY AreaType                                 ; load area type obtained from area offset pointer
	LDA SolidBlockMetatiles,y                    ; get metatile
GetRow:
	PHA                                          ; store metatile here
	JSR ChkLrgObjLength                          ; get row number, load length
DrawRow:
	LDX $07
	LDY #$00                                     ; set vertical height of 1
	PLA
	JMP RenderUnderPart                          ; render object

ColumnOfBricks:
	LDY AreaType                                 ; load area type obtained from area offset
	LDA BrickMetatiles,y                         ; get metatile (no cloud override as for row)
	JMP GetRow2

ColumnOfSolidBlocks:
	LDY AreaType                                 ; load area type obtained from area offset
	LDA SolidBlockMetatiles,y                    ; get metatile
GetRow2:
	PHA                                          ; save metatile to stack for now
	JSR GetLrgObjAttrib                          ; get length and row
	PLA                                          ; restore metatile
	LDX $07                                      ; get starting row
	JMP RenderUnderPart                          ; now render the column

; --------------------------------

BulletBillCannon:
	JSR GetLrgObjAttrib                          ; get row and length of bullet bill cannon
	LDX $07                                      ; start at first row
	LDA #$64                                     ; render bullet bill cannon
	STA MetatileBuffer,x
	INX
	DEY                                          ; done yet?
	BMI SetupCannon
	LDA #$65                                     ; if not, render middle part
	STA MetatileBuffer,x
	INX
	DEY                                          ; done yet?
	BMI SetupCannon
	LDA #$66                                     ; if not, render bottom until length expires
	JSR RenderUnderPart
SetupCannon:
	LDX Cannon_Offset                            ; get offset for data used by cannons and whirlpools
	JSR GetAreaObjYPosition                      ; get proper vertical coordinate for cannon
	STA Cannon_Y_Position,x                      ; and store it here
	LDA CurrentPageLoc
	STA Cannon_PageLoc,x                         ; store page number for cannon here
	JSR GetAreaObjXPosition                      ; get proper horizontal coordinate for cannon
	STA Cannon_X_Position,x                      ; and store it here
	INX
	CPX #$06                                     ; increment and check offset
	BCC StrCOffset                               ; if not yet reached sixth cannon, branch to save offset
	LDX #$00                                     ; otherwise initialize it
StrCOffset:
	STX Cannon_Offset                            ; save new offset and leave
	RTS

; --------------------------------

StaircaseHeightData:
	.db $07, $07, $06, $05, $04, $03, $02, $01, $00

StaircaseRowData:
	.db $03, $03, $04, $05, $06, $07, $08, $09, $0a

StaircaseObject:
	JSR ChkLrgObjLength                          ; check and load length
	BCC NextStair                                ; if length already loaded, skip init part
	LDA #$09                                     ; start past the end for the bottom
	STA StaircaseControl                         ; of the staircase
NextStair:
	DEC StaircaseControl                         ; move onto next step (or first if starting)
	LDY StaircaseControl
	LDX StaircaseRowData,y                       ; get starting row and height to render
	LDA StaircaseHeightData,y
	TAY
	LDA #$61                                     ; now render solid block staircase
	JMP RenderUnderPart

; --------------------------------

Jumpspring:
	JSR GetLrgObjAttrib
	JSR FindEmptyEnemySlot                       ; find empty space in enemy object buffer
	JSR GetAreaObjXPosition                      ; get horizontal coordinate for jumpspring
	STA Enemy_X_Position,x                       ; and store
	LDA CurrentPageLoc                           ; store page location of jumpspring
	STA Enemy_PageLoc,x
	JSR GetAreaObjYPosition                      ; get vertical coordinate for jumpspring
	STA Enemy_Y_Position,x                       ; and store
	STA Jumpspring_FixedYPos,x                   ; store as permanent coordinate here
	LDA #JumpspringObject
	STA Enemy_ID,x                               ; write jumpspring object to enemy object buffer
	LDY #$01
	STY Enemy_Y_HighPos,x                        ; store vertical high byte
	INC Enemy_Flag,x                             ; set flag for enemy object buffer
	LDX $07
	LDA #$67                                     ; draw metatiles in two rows where jumpspring is
	STA MetatileBuffer,x
	LDA #$68
	STA MetatileBuffer+1,x
	RTS

; --------------------------------
; $07 - used to save ID of brick object

Hidden1UpBlock:
	LDA Hidden1UpFlag                            ; if flag not set, do not render object
	BEQ ExitDecBlock
	LDA #$00                                     ; if set, init for the next one
	STA Hidden1UpFlag
	JMP BrickWithItem                            ; jump to code shared with unbreakable bricks

QuestionBlock:
	JSR GetAreaObjectID                          ; get value from level decoder routine
	JMP DrawQBlk                                 ; go to render it

BrickWithCoins:
	LDA #$00                                     ; initialize multi-coin timer flag
	STA BrickCoinTimerFlag

BrickWithItem:
	JSR GetAreaObjectID                          ; save area object ID
	STY $07
	LDA #$00                                     ; load default adder for bricks with lines
	LDY AreaType                                 ; check level type for ground level
	DEY
	BEQ BWithL                                   ; if ground type, do not start with 5
	LDA #$05                                     ; otherwise use adder for bricks without lines
BWithL:
	CLC                                          ; add object ID to adder
	ADC $07
	TAY                                          ; use as offset for metatile
DrawQBlk:
	LDA BrickQBlockMetatiles,y                   ; get appropriate metatile for brick (question block
	PHA                                          ; if branched to here from question block routine)
	JSR GetLrgObjAttrib                          ; get row from location byte
	JMP DrawRow                                  ; now render the object

GetAreaObjectID:
	LDA $00                                      ; get value saved from area parser routine
	SEC
	SBC #$00                                     ; possibly residual code
	TAY                                          ; save to Y
ExitDecBlock:
	RTS

; --------------------------------

HoleMetatiles:
	.db $87, $00, $00, $00

Hole_Empty:
	JSR ChkLrgObjLength                          ; get lower nybble and save as length
	BCC NoWhirlP                                 ; skip this part if length already loaded
	LDA AreaType                                 ; check for water type level
	BNE NoWhirlP                                 ; if not water type, skip this part
	LDX Whirlpool_Offset                         ; get offset for data used by cannons and whirlpools
	JSR GetAreaObjXPosition                      ; get proper vertical coordinate of where we're at
	SEC
	SBC #$10                                     ; subtract 16 pixels
	STA Whirlpool_LeftExtent,x                   ; store as left extent of whirlpool
	LDA CurrentPageLoc                           ; get page location of where we're at
	SBC #$00                                     ; subtract borrow
	STA Whirlpool_PageLoc,x                      ; save as page location of whirlpool
	INY
	INY                                          ; increment length by 2
	TYA
	ASL                                          ; multiply by 16 to get size of whirlpool
	ASL                                          ; note that whirlpool will always be
	ASL                                          ; two blocks bigger than actual size of hole
	ASL                                          ; and extend one block beyond each edge
	STA Whirlpool_Length,x                       ; save size of whirlpool here
	INX
	CPX #$05                                     ; increment and check offset
	BCC StrWOffset                               ; if not yet reached fifth whirlpool, branch to save offset
	LDX #$00                                     ; otherwise initialize it
StrWOffset:
	STX Whirlpool_Offset                         ; save new offset here
NoWhirlP:
	LDX AreaType                                 ; get appropriate metatile, then
	LDA HoleMetatiles,x                          ; render the hole proper
	LDX #$08
	LDY #$0f                                     ; start at ninth row and go to bottom, run RenderUnderPart

; --------------------------------

RenderUnderPart:
	STY AreaObjectHeight                         ; store vertical length to render
	LDY MetatileBuffer,x                         ; check current spot to see if there's something
	BEQ DrawThisRow                              ; we need to keep, if nothing, go ahead
	CPY #$17
	BEQ WaitOneRow                               ; if middle part (tree ledge), wait until next row
	CPY #$1a
	BEQ WaitOneRow                               ; if middle part (mushroom ledge), wait until next row
	CPY #$c0
	BEQ DrawThisRow                              ; if question block w/ coin, overwrite
	CPY #$c0
	BCS WaitOneRow                               ; if any other metatile with palette 3, wait until next row
	CPY #$54
	BNE DrawThisRow                              ; if cracked rock terrain, overwrite
	CMP #$50
	BEQ WaitOneRow                               ; if stem top of mushroom, wait until next row
DrawThisRow:
	STA MetatileBuffer,x                         ; render contents of A from routine that called this
WaitOneRow:
	INX
	CPX #$0d                                     ; stop rendering if we're at the bottom of the screen
	BCS ExitUPartR
	LDY AreaObjectHeight                         ; decrement, and stop rendering if there is no more length
	DEY
	BPL RenderUnderPart
ExitUPartR:
	RTS

; --------------------------------

ChkLrgObjLength:
	JSR GetLrgObjAttrib                          ; get row location and size (length if branched to from here)

ChkLrgObjFixedLength:
	LDA AreaObjectLength,x                       ; check for set length counter
	CLC                                          ; clear carry flag for not just starting
	BPL LenSet                                   ; if counter not set, load it, otherwise leave alone
	TYA                                          ; save length into length counter
	STA AreaObjectLength,x
	SEC                                          ; set carry flag if just starting
LenSet:
	RTS


GetLrgObjAttrib:
	LDY AreaObjOffsetBuffer,x                    ; get offset saved from area obj decoding routine
	LDA (AreaData),y                             ; get first byte of level object
	AND #%00001111
	STA $07                                      ; save row location
	INY
	LDA (AreaData),y                             ; get next byte, save lower nybble (length or height)
	AND #%00001111                               ; as Y, then leave
	TAY
	RTS

; --------------------------------

GetAreaObjXPosition:
	LDA CurrentColumnPos                         ; multiply current offset where we're at by 16
	ASL                                          ; to obtain horizontal pixel coordinate
	ASL
	ASL
	ASL
	RTS

; --------------------------------

GetAreaObjYPosition:
	LDA $07                                      ; multiply value by 16
	ASL
	ASL                                          ; this will give us the proper vertical pixel coordinate
	ASL
	ASL
	CLC
	ADC #32                                      ; add 32 pixels for the status bar
	RTS

; -------------------------------------------------------------------------------------
; $06-$07 - used to store block buffer address used as indirect

BlockBufferAddr:
	.db <Block_Buffer_1, <Block_Buffer_2
	.db >Block_Buffer_1, >Block_Buffer_2

GetBlockBufferAddr:
	PHA                                          ; take value of A, save
	LSR                                          ; move high nybble to low
	LSR
	LSR
	LSR
	TAY                                          ; use nybble as pointer to high byte
	LDA BlockBufferAddr+2,y                      ; of indirect here
	STA $07
	PLA
	AND #%00001111                               ; pull from stack, mask out high nybble
	CLC
	ADC BlockBufferAddr,y                        ; add to low byte
	STA $06                                      ; store here and leave
	RTS

; -------------------------------------------------------------------------------------

; -------------------------------------------------------------------------------------

AreaDataOfsLoopback:
	.db $12, $36, $0e, $0e, $0e, $32, $32, $32, $0a, $26, $40

; -------------------------------------------------------------------------------------

LoadAreaPointer:
	JSR FindAreaPointer                          ; find it and store it here
	STA AreaPointer
GetAreaType:
	AND #%01100000                               ; mask out all but d6 and d5
	ASL
	ROL
	ROL
	ROL                                          ; make %0xx00000 into %000000xx
	STA AreaType                                 ; save 2 MSB as area type
	RTS

FindAreaPointer:
	LDY WorldNumber                              ; load offset from world variable
	LDA WorldAddrOffsets,y
	CLC                                          ; add area number used to find data
	ADC AreaNumber
	TAY
	LDA AreaAddrOffsets,y                        ; from there we have our area pointer
	RTS


GetAreaDataAddrs:
	LDA AreaPointer                              ; use 2 MSB for Y
	JSR GetAreaType
	TAY
	LDA AreaPointer                              ; mask out all but 5 LSB
	AND #%00011111
	STA AreaAddrsLOffset                         ; save as low offset
	LDA EnemyAddrHOffsets,y                      ; load base value with 2 altered MSB,
	CLC                                          ; then add base value to 5 LSB, result
	ADC AreaAddrsLOffset                         ; becomes offset for level data
	TAY
	LDA EnemyDataAddrLow,y                       ; use offset to load pointer
	STA EnemyDataLow
	LDA EnemyDataAddrHigh,y
	STA EnemyDataHigh
	LDY AreaType                                 ; use area type as offset
	LDA AreaDataHOffsets,y                       ; do the same thing but with different base value
	CLC
	ADC AreaAddrsLOffset
	TAY
	LDA AreaDataAddrLow,y                        ; use this offset to load another pointer
	STA AreaDataLow
	LDA AreaDataAddrHigh,y
	STA AreaDataHigh
	LDY #$00                                     ; load first byte of header
	LDA (AreaData),y
	PHA                                          ; save it to the stack for now
	AND #%00000111                               ; save 3 LSB for foreground scenery or bg color control
	CMP #$04
	BCC StoreFore
	STA BackgroundColorCtrl                      ; if 4 or greater, save value here as bg color control
	LDA #$00
StoreFore:
	STA ForegroundScenery                        ; if less, save value here as foreground scenery
	PLA                                          ; pull byte from stack and push it back
	PHA
	AND #%00111000                               ; save player entrance control bits
	LSR                                          ; shift bits over to LSBs
	LSR
	LSR
	STA PlayerEntranceCtrl                       ; save value here as player entrance control
	PLA                                          ; pull byte again but do not push it back
	AND #%11000000                               ; save 2 MSB for game timer setting
	CLC
	ROL                                          ; rotate bits over to LSBs
	ROL
	ROL
	STA GameTimerSetting                         ; save value here as game timer setting
	INY
	LDA (AreaData),y                             ; load second byte of header
	PHA                                          ; save to stack
	AND #%00001111                               ; mask out all but lower nybble
	STA TerrainControl
	PLA                                          ; pull and push byte to copy it to A
	PHA
	AND #%00110000                               ; save 2 MSB for background scenery type
	LSR
	LSR                                          ; shift bits to LSBs
	LSR
	LSR
	STA BackgroundScenery                        ; save as background scenery
	PLA
	AND #%11000000
	CLC
	ROL                                          ; rotate bits over to LSBs
	ROL
	ROL
	CMP #%00000011                               ; if set to 3, store here
	BNE StoreStyle                               ; and nullify other value
	STA CloudTypeOverride                        ; otherwise store value in other place
	LDA #$00
StoreStyle:
	STA AreaStyle
	LDA AreaDataLow                              ; increment area data address by 2 bytes
	CLC
	ADC #$02
	STA AreaDataLow
	LDA AreaDataHigh
	ADC #$00
	STA AreaDataHigh
	RTS

; -------------------------------------------------------------------------------------

	.include "src/levels/levels.asm"

; -------------------------------------------------------------------------------------

; -------------------------------------------------------------------------------------

; indirect jump routine called when
; $0770 is set to 1
GameMode:
	LDA OperMode_Task
	JSR JumpEngine

	.dw InitializeArea
	.dw ScreenRoutines
	.dw SecondaryGameSetup
	.dw GameCoreRoutine

; -------------------------------------------------------------------------------------

GameCoreRoutine:
	LDX CurrentPlayer                            ; get which player is on the screen
	LDA SavedJoypadBits,x                        ; use appropriate player's controller bits
	STA SavedJoypadBits                          ; as the master controller bits
	JSR GameRoutines                             ; execute one of many possible subs
	LDA OperMode_Task                            ; check major task of operating mode
	CMP #$03                                     ; if we are supposed to be here,
	BCS GameEngine                               ; branch to the game engine itself
	RTS

GameEngine:
	JSR ProcFireball_Bubble                      ; process fireballs and air bubbles
	LDX #$00
ProcELoop:
	STX ObjectOffset                             ; put incremented offset in X as enemy object offset
	JSR EnemiesAndLoopsCore                      ; process enemy objects
	JSR FloateyNumbersRoutine                    ; process floatey numbers
	INX
	CPX #$06                                     ; do these two subroutines until the whole buffer is done
	BNE ProcELoop
	JSR GetPlayerOffscreenBits                   ; get offscreen bits for player object
	JSR RelativePlayerPosition                   ; get relative coordinates for player object
	JSR PlayerGfxHandler                         ; draw the player
	JSR BlockObjMT_Updater                       ; replace block objects with metatiles if necessary
	LDX #$01
	STX ObjectOffset                             ; set offset for second
	JSR BlockObjectsCore                         ; process second block object
	DEX
	STX ObjectOffset                             ; set offset for first
	JSR BlockObjectsCore                         ; process first block object
	JSR MiscObjectsCore                          ; process misc objects (hammer, jumping coins)
	JSR ProcessCannons                           ; process bullet bill cannons
	JSR ProcessWhirlpools                        ; process whirlpools
	JSR FlagpoleRoutine                          ; process the flagpole
	JSR RunGameTimer                             ; count down the game timer
	JSR ColorRotation                            ; cycle one of the background colors
	LDA Player_Y_HighPos
	CMP #$02                                     ; if player is below the screen, don't bother with the music
	BPL NoChgMus
	LDA StarInvincibleTimer                      ; if star mario invincibility timer at zero,
	BEQ ClrPlrPal                                ; skip this part
	CMP #$04
	BNE NoChgMus                                 ; if not yet at a certain point, continue
	LDA IntervalTimerControl                     ; if interval timer not yet expired,
	BNE NoChgMus                                 ; branch ahead, don't bother with the music
	JSR GetAreaMusic                             ; to re-attain appropriate level music
NoChgMus:
	LDY StarInvincibleTimer                      ; get invincibility timer
	LDA FrameCounter                             ; get frame counter
	CPY #$08                                     ; if timer still above certain point,
	BCS CycleTwo                                 ; branch to cycle player's palette quickly
	LSR                                          ; otherwise, divide by 8 to cycle every eighth frame
	LSR
CycleTwo:
	LSR                                          ; if branched here, divide by 2 to cycle every other frame
	JSR CyclePlayerPalette                       ; do sub to cycle the palette (note: shares fire flower code)
	JMP SaveAB                                   ; then skip this sub to finish up the game engine
ClrPlrPal:
	JSR ResetPalStar                             ; do sub to clear player's palette bits in attributes
SaveAB:
	LDA A_B_Buttons                              ; save current A and B button
	STA PreviousA_B_Buttons                      ; into temp variable to be used on next frame
	LDA #$00
	STA Left_Right_Buttons                       ; nullify left and right buttons temp variable
UpdScrollVar:
	LDA VRAM_Buffer_AddrCtrl
	CMP #$06                                     ; if vram address controller set to 6 (one of two $0341s)
	BEQ ExitEng                                  ; then branch to leave
	LDA AreaParserTaskNum                        ; otherwise check number of tasks
	BNE RunParser
	LDA ScrollThirtyTwo                          ; get horizontal scroll in 0-31 or $00-$20 range
	CMP #$20                                     ; check to see if exceeded $21
	BMI ExitEng                                  ; branch to leave if not
	LDA ScrollThirtyTwo
	SBC #$20                                     ; otherwise subtract $20 to set appropriately
	STA ScrollThirtyTwo                          ; and store
	LDA #$00                                     ; reset vram buffer offset used in conjunction with
	STA VRAM_Buffer2_Offset                      ; level graphics buffer at $0341-$035f
RunParser:
	JSR AreaParserTaskHandler                    ; update the name table with more level graphics
ExitEng:
	RTS                                          ; and after all that, we're finally done!

; -------------------------------------------------------------------------------------

ScrollHandler:
	LDA Player_X_Scroll                          ; load value saved here
	CLC
	ADC Platform_X_Scroll                        ; add value used by left/right platforms
	STA Player_X_Scroll                          ; save as new value here to impose force on scroll
	LDA ScrollLock                               ; check scroll lock flag
	BNE InitScrlAmt                              ; skip a bunch of code here if set
	LDA Player_Pos_ForScroll
	CMP #$50                                     ; check player's horizontal screen position
	BCC InitScrlAmt                              ; if less than 80 pixels to the right, branch
	LDA SideCollisionTimer                       ; if timer related to player's side collision
	BNE InitScrlAmt                              ; not expired, branch
	LDY Player_X_Scroll                          ; get value and decrement by one
	DEY                                          ; if value originally set to zero or otherwise
	BMI InitScrlAmt                              ; negative for left movement, branch
	INY
	CPY #$02                                     ; if value $01, branch and do not decrement
	BCC ChkNearMid
	DEY                                          ; otherwise decrement by one
ChkNearMid:
	LDA Player_Pos_ForScroll
	CMP #$70                                     ; check player's horizontal screen position
	BCC ScrollScreen                             ; if less than 112 pixels to the right, branch
	LDY Player_X_Scroll                          ; otherwise get original value undecremented

ScrollScreen:
	TYA
	STA ScrollAmount                             ; save value here
	CLC
	ADC ScrollThirtyTwo                          ; add to value already set here
	STA ScrollThirtyTwo                          ; save as new value here
	TYA
	CLC
	ADC ScreenLeft_X_Pos                         ; add to left side coordinate
	STA ScreenLeft_X_Pos                         ; save as new left side coordinate
	STA HorizontalScroll                         ; save here also
	LDA ScreenLeft_PageLoc
	ADC #$00                                     ; add carry to page location for left
	STA ScreenLeft_PageLoc                       ; side of the screen
	AND #$01                                     ; get LSB of page location
	STA $00                                      ; save as temp variable for PPU register 1 mirror
	LDA Mirror_PPU_CTRL_REG1                     ; get PPU register 1 mirror
	AND #%11111110                               ; save all bits except d0
	ORA $00                                      ; get saved bit here and save in PPU register 1
	STA Mirror_PPU_CTRL_REG1                     ; mirror to be used to set name table later
	JSR GetScreenPosition                        ; figure out where the right side is
	LDA #$08
	STA ScrollIntervalTimer                      ; set scroll timer (residual, not used elsewhere)
	JMP ChkPOffscr                               ; skip this part
InitScrlAmt:
	LDA #$00
	STA ScrollAmount                             ; initialize value here
ChkPOffscr:
	LDX #$00                                     ; set X for player offset
	JSR GetXOffscreenBits                        ; get horizontal offscreen bits for player
	STA $00                                      ; save them here
	LDY #$00                                     ; load default offset (left side)
	ASL                                          ; if d7 of offscreen bits are set,
	BCS KeepOnscr                                ; branch with default offset
	INY                                          ; otherwise use different offset (right side)
	LDA $00
	AND #%00100000                               ; check offscreen bits for d5 set
	BEQ InitPlatScrl                             ; if not set, branch ahead of this part
KeepOnscr:
	LDA ScreenEdge_X_Pos,y                       ; get left or right side coordinate based on offset
	SEC
	SBC X_SubtracterData,y                       ; subtract amount based on offset
	STA Player_X_Position                        ; store as player position to prevent movement further
	LDA ScreenEdge_PageLoc,y                     ; get left or right page location based on offset
	SBC #$00                                     ; subtract borrow
	STA Player_PageLoc                           ; save as player's page location
	LDA Left_Right_Buttons                       ; check saved controller bits
	CMP OffscrJoypadBitsData,y                   ; against bits based on offset
	BEQ InitPlatScrl                             ; if not equal, branch
	LDA #$00
	STA Player_X_Speed                           ; otherwise nullify horizontal speed of player
InitPlatScrl:
	LDA #$00                                     ; nullify platform force imposed on scroll
	STA Platform_X_Scroll
	RTS

X_SubtracterData:
	.db $00, $10

OffscrJoypadBitsData:
	.db $01, $02

; -------------------------------------------------------------------------------------

GetScreenPosition:
	LDA ScreenLeft_X_Pos                         ; get coordinate of screen's left boundary
	CLC
	ADC #$ff                                     ; add 255 pixels
	STA ScreenRight_X_Pos                        ; store as coordinate of screen's right boundary
	LDA ScreenLeft_PageLoc                       ; get page number where left boundary is
	ADC #$00                                     ; add carry from before
	STA ScreenRight_PageLoc                      ; store as page number where right boundary is
	RTS

; -------------------------------------------------------------------------------------

GameRoutines:
	LDA GameEngineSubroutine                     ; run routine based on number (a few of these routines are
	JSR JumpEngine                               ; merely placeholders as conditions for other routines)

	.dw Entrance_GameTimerSetup
	.dw Vine_AutoClimb
	.dw SideExitPipeEntry
	.dw VerticalPipeEntry
	.dw FlagpoleSlide
	.dw PlayerEndLevel
	.dw PlayerLoseLife
	.dw PlayerEntrance
	.dw PlayerCtrlRoutine
	.dw PlayerChangeSize
	.dw PlayerInjuryBlink
	.dw PlayerDeath
	.dw PlayerFireFlower

; -------------------------------------------------------------------------------------

PlayerEntrance:
	LDA AltEntranceControl                       ; check for mode of alternate entry
	CMP #$02
	BEQ EntrMode2                                ; if found, branch to enter from pipe or with vine
	LDA #$00
	LDY Player_Y_Position                        ; if vertical position above a certain
	CPY #$30                                     ; point, nullify controller bits and continue
	BCC AutoControlPlayer                        ; with player movement code, do not return
	LDA PlayerEntranceCtrl                       ; check player entry bits from header
	CMP #$06
	BEQ ChkBehPipe                               ; if set to 6 or 7, execute pipe intro code
	CMP #$07                                     ; otherwise branch to normal entry
	BNE PlayerRdy
ChkBehPipe:
	LDA Player_SprAttrib                         ; check for sprite attributes
	BNE IntroEntr                                ; branch if found
	LDA #$01
	JMP AutoControlPlayer                        ; force player to walk to the right
IntroEntr:
	JSR EnterSidePipe                            ; execute sub to move player to the right
	DEC ChangeAreaTimer                          ; decrement timer for change of area
	BNE ExitEntr                                 ; branch to exit if not yet expired
	INC DisableIntermediate                      ; set flag to skip world and lives display
	JMP NextArea                                 ; jump to increment to next area and set modes
EntrMode2:
	LDA JoypadOverride                           ; if controller override bits set here,
	BNE VineEntr                                 ; branch to enter with vine
	LDA #$ff                                     ; otherwise, set value here then execute sub
	JSR MovePlayerYAxis                          ; to move player upwards (note $ff = -1)
	LDA Player_Y_Position                        ; check to see if player is at a specific coordinate
	CMP #$91                                     ; if player risen to a certain point (this requires pipes
	BCC PlayerRdy                                ; to be at specific height to look/function right) branch
	RTS                                          ; to the last part, otherwise leave
VineEntr:
	LDA VineHeight
	CMP #$60                                     ; check vine height
	BNE ExitEntr                                 ; if vine not yet reached maximum height, branch to leave
	LDA Player_Y_Position                        ; get player's vertical coordinate
	CMP #$99                                     ; check player's vertical coordinate against preset value
	LDY #$00                                     ; load default values to be written to
	LDA #$01                                     ; this value moves player to the right off the vine
	BCC OffVine                                  ; if vertical coordinate < preset value, use defaults
	LDA #$03
	STA Player_State                             ; otherwise set player state to climbing
	INY                                          ; increment value in Y
	LDA #$08                                     ; set block in block buffer to cover hole, then
	STA Block_Buffer_1+$b4                       ; use same value to force player to climb
OffVine:
	STY DisableCollisionDet                      ; set collision detection disable flag
	JSR AutoControlPlayer                        ; use contents of A to move player up or right, execute sub
	LDA Player_X_Position
	CMP #$48                                     ; check player's horizontal position
	BCC ExitEntr                                 ; if not far enough to the right, branch to leave
PlayerRdy:
	LDA #$08                                     ; set routine to be executed by game engine next frame
	STA GameEngineSubroutine
	LDA #$01                                     ; set to face player to the right
	STA PlayerFacingDir
	LSR                                          ; init A
	STA AltEntranceControl                       ; init mode of entry
	STA DisableCollisionDet                      ; init collision detection disable flag
	STA JoypadOverride                           ; nullify controller override bits
ExitEntr:
	RTS                                          ; leave!

; -------------------------------------------------------------------------------------
; $07 - used to hold upper limit of high byte when player falls down hole

AutoControlPlayer:
	STA SavedJoypadBits                          ; override controller bits with contents of A if executing here

PlayerCtrlRoutine:
	LDA GameEngineSubroutine                     ; check task here
	CMP #$0b                                     ; if certain value is set, branch to skip controller bit loading
	BEQ SizeChk
	LDA AreaType                                 ; are we in a water type area?
	BNE SaveJoyp                                 ; if not, branch
	LDY Player_Y_HighPos
	DEY                                          ; if not in vertical area between
	BNE DisJoyp                                  ; status bar and bottom, branch
	LDA Player_Y_Position
	CMP #$d0                                     ; if nearing the bottom of the screen or
	BCC SaveJoyp                                 ; not in the vertical area between status bar or bottom,
DisJoyp:
	LDA #$00                                     ; disable controller bits
	STA SavedJoypadBits
SaveJoyp:
	LDA SavedJoypadBits                          ; otherwise store A and B buttons in $0a
	AND #%11000000
	STA A_B_Buttons
	LDA SavedJoypadBits                          ; store left and right buttons in $0c
	AND #%00000011
	STA Left_Right_Buttons
	LDA SavedJoypadBits                          ; store up and down buttons in $0b
	AND #%00001100
	STA Up_Down_Buttons
	AND #%00000100                               ; check for pressing down
	BEQ SizeChk                                  ; if not, branch
	LDA Player_State                             ; check player's state
	BNE SizeChk                                  ; if not on the ground, branch
	LDY Left_Right_Buttons                       ; check left and right
	BEQ SizeChk                                  ; if neither pressed, branch
	LDA #$00
	STA Left_Right_Buttons                       ; if pressing down while on the ground,
	STA Up_Down_Buttons                          ; nullify directional bits
SizeChk:
	JSR PlayerMovementSubs                       ; run movement subroutines
	LDY #$01                                     ; is player small?
	LDA PlayerSize
	BNE ChkMoveDir
	LDY #$00                                     ; check for if crouching
	LDA CrouchingFlag
	BEQ ChkMoveDir                               ; if not, branch ahead
	LDY #$02                                     ; if big and crouching, load y with 2
ChkMoveDir:
	STY Player_BoundBoxCtrl                      ; set contents of Y as player's bounding box size control
	LDA #$01                                     ; set moving direction to right by default
	LDY Player_X_Speed                           ; check player's horizontal speed
	BEQ PlayerSubs                               ; if not moving at all horizontally, skip this part
	BPL SetMoveDir                               ; if moving to the right, use default moving direction
	ASL                                          ; otherwise change to move to the left
SetMoveDir:
	STA Player_MovingDir                         ; set moving direction
PlayerSubs:
	JSR ScrollHandler                            ; move the screen if necessary
	JSR GetPlayerOffscreenBits                   ; get player's offscreen bits
	JSR RelativePlayerPosition                   ; get coordinates relative to the screen
	LDX #$00                                     ; set offset for player object
	JSR BoundingBoxCore                          ; get player's bounding box coordinates
	JSR PlayerBGCollision                        ; do collision detection and process
	LDA Player_Y_Position
	CMP #$40                                     ; check to see if player is higher than 64th pixel
	BCC PlayerHole                               ; if so, branch ahead
	LDA GameEngineSubroutine
	CMP #$05                                     ; if running end-of-level routine, branch ahead
	BEQ PlayerHole
	CMP #$07                                     ; if running player entrance routine, branch ahead
	BEQ PlayerHole
	CMP #$04                                     ; if running routines $00-$03, branch ahead
	BCC PlayerHole
	LDA Player_SprAttrib
	AND #%11011111                               ; otherwise nullify player's
	STA Player_SprAttrib                         ; background priority flag
PlayerHole:
	LDA Player_Y_HighPos                         ; check player's vertical high byte
	CMP #$02                                     ; for below the screen
	BMI ExitCtrl                                 ; branch to leave if not that far down
	LDX #$01
	STX ScrollLock                               ; set scroll lock
	LDY #$04
	STY $07                                      ; set value here
	LDX #$00                                     ; use X as flag, and clear for cloud level
	LDY GameTimerExpiredFlag                     ; check game timer expiration flag
	BNE HoleDie                                  ; if set, branch
	LDY CloudTypeOverride                        ; check for cloud type override
	BNE ChkHoleX                                 ; skip to last part if found
HoleDie:
	INX                                          ; set flag in X for player death
	LDY GameEngineSubroutine
	CPY #$0b                                     ; check for some other routine running
	BEQ ChkHoleX                                 ; if so, branch ahead
	LDY DeathMusicLoaded                         ; check value here
	BNE HoleBottom                               ; if already set, branch to next part
	INY
	STY EventMusicQueue                          ; otherwise play death music
	STY DeathMusicLoaded                         ; and set value here
HoleBottom:
	LDY #$06
	STY $07                                      ; change value here
ChkHoleX:
	CMP $07                                      ; compare vertical high byte with value set here
	BMI ExitCtrl                                 ; if less, branch to leave
	DEX                                          ; otherwise decrement flag in X
	BMI CloudExit                                ; if flag was clear, branch to set modes and other values
	LDY EventMusicBuffer                         ; check to see if music is still playing
	BNE ExitCtrl                                 ; branch to leave if so
	LDA #$06                                     ; otherwise set to run lose life routine
	STA GameEngineSubroutine                     ; on next frame
ExitCtrl:
	RTS                                          ; leave

CloudExit:
	LDA #$00
	STA JoypadOverride                           ; clear controller override bits if any are set
	JSR SetEntr                                  ; do sub to set secondary mode
	INC AltEntranceControl                       ; set mode of entry to 3
	RTS

; -------------------------------------------------------------------------------------

Vine_AutoClimb:
	LDA Player_Y_HighPos                         ; check to see whether player reached position
	BNE AutoClimb                                ; above the status bar yet and if so, set modes
	LDA Player_Y_Position
	CMP #$e4
	BCC SetEntr
AutoClimb:
	LDA #%00001000                               ; set controller bits override to up
	STA JoypadOverride
	LDY #$03                                     ; set player state to climbing
	STY Player_State
	JMP AutoControlPlayer
SetEntr:
	LDA #$02                                     ; set starting position to override
	STA AltEntranceControl
	JMP ChgAreaMode                              ; set modes

; -------------------------------------------------------------------------------------

VerticalPipeEntry:
	LDA #$01                                     ; set 1 as movement amount
	JSR MovePlayerYAxis                          ; do sub to move player downwards
	JSR ScrollHandler                            ; do sub to scroll screen with saved force if necessary
	LDY #$00                                     ; load default mode of entry
	LDA WarpZoneControl                          ; check warp zone control variable/flag
	BNE ChgAreaPipe                              ; if set, branch to use mode 0
	INY
	LDA AreaType                                 ; check for castle level type
	CMP #$03
	BNE ChgAreaPipe                              ; if not castle type level, use mode 1
	INY
	JMP ChgAreaPipe                              ; otherwise use mode 2

MovePlayerYAxis:
	CLC
	ADC Player_Y_Position                        ; add contents of A to player position
	STA Player_Y_Position
	RTS

; -------------------------------------------------------------------------------------

SideExitPipeEntry:
	JSR EnterSidePipe                            ; execute sub to move player to the right
	LDY #$02
ChgAreaPipe:
	DEC ChangeAreaTimer                          ; decrement timer for change of area
	BNE ExitCAPipe
	STY AltEntranceControl                       ; when timer expires set mode of alternate entry
ChgAreaMode:
	INC DisableScreenFlag                        ; set flag to disable screen output
	LDA #$00
	STA OperMode_Task                            ; set secondary mode of operation
	STA Sprite0HitDetectFlag                     ; disable sprite 0 check
ExitCAPipe:
	RTS                                          ; leave

EnterSidePipe:
	LDA #$08                                     ; set player's horizontal speed
	STA Player_X_Speed
	LDY #$01                                     ; set controller right button by default
	LDA Player_X_Position                        ; mask out higher nybble of player's
	AND #%00001111                               ; horizontal position
	BNE RightPipe
	STA Player_X_Speed                           ; if lower nybble = 0, set as horizontal speed
	TAY                                          ; and nullify controller bit override here
RightPipe:
	TYA                                          ; use contents of Y to
	JSR AutoControlPlayer                        ; execute player control routine with ctrl bits nulled
	RTS

; -------------------------------------------------------------------------------------

PlayerChangeSize:
	LDA TimerControl                             ; check master timer control
	CMP #$f8                                     ; for specific moment in time
	BNE EndChgSize                               ; branch if before or after that point
	JMP InitChangeSize                           ; otherwise run code to get growing/shrinking going
EndChgSize:
	CMP #$c4                                     ; check again for another specific moment
	BNE ExitChgSize                              ; and branch to leave if before or after that point
	JSR DonePlayerTask                           ; otherwise do sub to init timer control and set routine
ExitChgSize:
	RTS                                          ; and then leave

; -------------------------------------------------------------------------------------

PlayerInjuryBlink:
	LDA TimerControl                             ; check master timer control
	CMP #$f0                                     ; for specific moment in time
	BCS ExitBlink                                ; branch if before that point
	CMP #$c8                                     ; check again for another specific point
	BEQ DonePlayerTask                           ; branch if at that point, and not before or after
	JMP PlayerCtrlRoutine                        ; otherwise run player control routine
ExitBlink:
	BNE ExitBoth                                 ; do unconditional branch to leave

InitChangeSize:
	LDY PlayerChangeSizeFlag                     ; if growing/shrinking flag already set
	BNE ExitBoth                                 ; then branch to leave
	STY PlayerAnimCtrl                           ; otherwise initialize player's animation frame control
	INC PlayerChangeSizeFlag                     ; set growing/shrinking flag
	LDA PlayerSize
	EOR #$01                                     ; invert player's size
	STA PlayerSize
ExitBoth:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------
; $00 - used in CyclePlayerPalette to store current palette to cycle

PlayerDeath:
	LDA TimerControl                             ; check master timer control
	CMP #$f0                                     ; for specific moment in time
	BCS ExitDeath                                ; branch to leave if before that point
	JMP PlayerCtrlRoutine                        ; otherwise run player control routine

DonePlayerTask:
	LDA #$00
	STA TimerControl                             ; initialize master timer control to continue timers
	LDA #$08
	STA GameEngineSubroutine                     ; set player control routine to run next frame
	RTS                                          ; leave

PlayerFireFlower:

	LDA TimerControl                             ; check master timer control
	CMP #$c0                                     ; for specific moment in time
	BEQ ResetPalFireFlower                       ; branch if at moment, not before or after
	LDA FrameCounter                             ; get frame counter
	LSR
	LSR                                          ; divide by four to change every four frames

CyclePlayerPalette:
	AND #$03                                     ; mask out all but d1-d0 (previously d3-d2)
	STA $00                                      ; store result here to use as palette bits
	LDA Player_SprAttrib                         ; get player attributes
	AND #%11111100                               ; save any other bits but palette bits
	ORA $00                                      ; add palette bits
	STA Player_SprAttrib                         ; store as new player attributes
	RTS                                          ; and leave

ResetPalFireFlower:
	JSR DonePlayerTask                           ; do sub to init timer control and run player control routine

ResetPalStar:
	LDA Player_SprAttrib                         ; get player attributes
	AND #%11111100                               ; mask out palette bits to force palette 0
	STA Player_SprAttrib                         ; store as new player attributes
	RTS                                          ; and leave

ExitDeath:
	RTS                                          ; leave from death routine

; -------------------------------------------------------------------------------------

FlagpoleSlide:
	LDA Enemy_ID+5                               ; check special use enemy slot
	CMP #FlagpoleFlagObject                      ; for flagpole flag object
	BNE NoFPObj                                  ; if not found, branch to something residual
	LDA FlagpoleSoundQueue                       ; load flagpole sound
	STA Square1SoundQueue                        ; into square 1's sfx queue
	LDA #$00
	STA FlagpoleSoundQueue                       ; init flagpole sound queue
	LDY Player_Y_Position
	CPY #$9e                                     ; check to see if player has slid down
	BCS SlidePlayer                              ; far enough, and if so, branch with no controller bits set
	LDA #$04                                     ; otherwise force player to climb down (to slide)
SlidePlayer:
	JMP AutoControlPlayer                        ; jump to player control routine
NoFPObj:
	INC GameEngineSubroutine                     ; increment to next routine (this may
	RTS                                          ; be residual code)

; -------------------------------------------------------------------------------------

Hidden1UpCoinAmts:
	.db $15, $23, $16, $1b, $17, $18, $23, $63

PlayerEndLevel:
	LDA #$01                                     ; force player to walk to the right
	JSR AutoControlPlayer
	LDA Player_Y_Position                        ; check player's vertical position
	CMP #$ae
	BCC ChkStop                                  ; if player is not yet off the flagpole, skip this part
	LDA ScrollLock                               ; if scroll lock not set, branch ahead to next part
	BEQ ChkStop                                  ; because we only need to do this part once
	LDA #EndOfLevelMusic
	STA EventMusicQueue                          ; load win level music in event music queue
	LDA #$00
	STA ScrollLock                               ; turn off scroll lock to skip this part later
ChkStop:
	LDA Player_CollisionBits                     ; get player collision bits
	LSR                                          ; check for d0 set
	BCS RdyNextA                                 ; if d0 set, skip to next part
	LDA StarFlagTaskControl                      ; if star flag task control already set,
	BNE InCastle                                 ; go ahead with the rest of the code
	INC StarFlagTaskControl                      ; otherwise set task control now (this gets ball rolling!)
InCastle:
	LDA #%00100000                               ; set player's background priority bit to
	STA Player_SprAttrib                         ; give illusion of being inside the castle
RdyNextA:
	LDA StarFlagTaskControl
	CMP #$05                                     ; if star flag task control not yet set
	BNE ExitNA                                   ; beyond last valid task number, branch to leave
	INC LevelNumber                              ; increment level number used for game logic
	LDA LevelNumber
	CMP #$03                                     ; check to see if we have yet reached level -4
	BNE NextArea                                 ; and skip this last part here if not
	LDY WorldNumber                              ; get world number as offset
	LDA CoinTallyFor1Ups                         ; check third area coin tally for bonus 1-ups
	CMP Hidden1UpCoinAmts,y                      ; against minimum value, if player has not collected
	BCC NextArea                                 ; at least this number of coins, leave flag clear
	INC Hidden1UpFlag                            ; otherwise set hidden 1-up box control flag
NextArea:
	INC AreaNumber                               ; increment area number used for address loader
	JSR LoadAreaPointer                          ; get new level pointer
	INC FetchNewGameTimerFlag                    ; set flag to load new game timer
	JSR ChgAreaMode                              ; do sub to set secondary mode, disable screen and sprite 0
	STA HalfwayPage                              ; reset halfway page to 0 (beginning)
	LDA #Silence
	STA EventMusicQueue                          ; silence music and leave
ExitNA:
	RTS

; -------------------------------------------------------------------------------------

PlayerMovementSubs:
	LDA #$00                                     ; set A to init crouch flag by default
	LDY PlayerSize                               ; is player small?
	BNE SetCrouch                                ; if so, branch
	LDA Player_State                             ; check state of player
	BNE ProcMove                                 ; if not on the ground, branch
	LDA Up_Down_Buttons                          ; load controller bits for up and down
	AND #%00000100                               ; single out bit for down button
SetCrouch:
	STA CrouchingFlag                            ; store value in crouch flag
ProcMove:
	JSR PlayerPhysicsSub                         ; run sub related to jumping and swimming
	LDA PlayerChangeSizeFlag                     ; if growing/shrinking flag set,
	BNE NoMoveSub                                ; branch to leave
	LDA Player_State
	CMP #$03                                     ; get player state
	BEQ MoveSubs                                 ; if climbing, branch ahead, leave timer unset
	LDY #$18
	STY ClimbSideTimer                           ; otherwise reset timer now
MoveSubs:
	JSR JumpEngine

	.dw OnGroundStateSub
	.dw JumpSwimSub
	.dw FallingSub
	.dw ClimbingSub

NoMoveSub:
	RTS

; -------------------------------------------------------------------------------------
; $00 - used by ClimbingSub to store high vertical adder

OnGroundStateSub:
	JSR GetPlayerAnimSpeed                       ; do a sub to set animation frame timing
	LDA Left_Right_Buttons
	BEQ GndMove                                  ; if left/right controller bits not set, skip instruction
	STA PlayerFacingDir                          ; otherwise set new facing direction
GndMove:
	JSR ImposeFriction                           ; do a sub to impose friction on player's walk/run
	JSR MovePlayerHorizontally                   ; do another sub to move player horizontally
	STA Player_X_Scroll                          ; set returned value as player's movement speed for scroll
	RTS

; --------------------------------

FallingSub:
	LDA VerticalForceDown
	STA VerticalForce                            ; dump vertical movement force for falling into main one
	JMP LRAir                                    ; movement force, then skip ahead to process left/right movement

; --------------------------------

JumpSwimSub:
	LDY Player_Y_Speed                           ; if player's vertical speed zero
	BPL DumpFall                                 ; or moving downwards, branch to falling
	LDA A_B_Buttons
	AND #A_Button                                ; check to see if A button is being pressed
	AND PreviousA_B_Buttons                      ; and was pressed in previous frame
	BNE ProcSwim                                 ; if so, branch elsewhere
	LDA JumpOrigin_Y_Position                    ; get vertical position player jumped from
	SEC
	SBC Player_Y_Position                        ; subtract current from original vertical coordinate
	CMP DiffToHaltJump                           ; compare to value set here to see if player is in mid-jump
	BCC ProcSwim                                 ; or just starting to jump, if just starting, skip ahead
DumpFall:
	LDA VerticalForceDown                        ; otherwise dump falling into main fractional
	STA VerticalForce
ProcSwim:
	LDA SwimmingFlag                             ; if swimming flag not set,
	BEQ LRAir                                    ; branch ahead to last part
	JSR GetPlayerAnimSpeed                       ; do a sub to get animation frame timing
	LDA Player_Y_Position
	CMP #$14                                     ; check vertical position against preset value
	BCS LRWater                                  ; if not yet reached a certain position, branch ahead
	LDA #$18
	STA VerticalForce                            ; otherwise set fractional
LRWater:
	LDA Left_Right_Buttons                       ; check left/right controller bits (check for swimming)
	BEQ LRAir                                    ; if not pressing any, skip
	STA PlayerFacingDir                          ; otherwise set facing direction accordingly
LRAir:
	LDA Left_Right_Buttons                       ; check left/right controller bits (check for jumping/falling)
	BEQ JSMove                                   ; if not pressing any, skip
	JSR ImposeFriction                           ; otherwise process horizontal movement
JSMove:
	JSR MovePlayerHorizontally                   ; do a sub to move player horizontally
	STA Player_X_Scroll                          ; set player's speed here, to be used for scroll later
	LDA GameEngineSubroutine
	CMP #$0b                                     ; check for specific routine selected
	BNE ExitMov1                                 ; branch if not set to run
	LDA #$28
	STA VerticalForce                            ; otherwise set fractional
ExitMov1:
	JMP MovePlayerVertically                     ; jump to move player vertically, then leave

; --------------------------------

ClimbAdderLow:
	.db $0e, $04, $fc, $f2
ClimbAdderHigh:
	.db $00, $00, $ff, $ff

ClimbingSub:
	LDA Player_YMF_Dummy
	CLC                                          ; add movement force to dummy variable
	ADC Player_Y_MoveForce                       ; save with carry
	STA Player_YMF_Dummy
	LDY #$00                                     ; set default adder here
	LDA Player_Y_Speed                           ; get player's vertical speed
	BPL MoveOnVine                               ; if not moving upwards, branch
	DEY                                          ; otherwise set adder to $ff
MoveOnVine:
	STY $00                                      ; store adder here
	ADC Player_Y_Position                        ; add carry to player's vertical position
	STA Player_Y_Position                        ; and store to move player up or down
	LDA Player_Y_HighPos
	ADC $00                                      ; add carry to player's page location
	STA Player_Y_HighPos                         ; and store
	LDA Left_Right_Buttons                       ; compare left/right controller bits
	AND Player_CollisionBits                     ; to collision flag
	BEQ InitCSTimer                              ; if not set, skip to end
	LDY ClimbSideTimer                           ; otherwise check timer
	BNE ExitCSub                                 ; if timer not expired, branch to leave
	LDY #$18
	STY ClimbSideTimer                           ; otherwise set timer now
	LDX #$00                                     ; set default offset here
	LDY PlayerFacingDir                          ; get facing direction
	LSR                                          ; move right button controller bit to carry
	BCS ClimbFD                                  ; if controller right pressed, branch ahead
	INX
	INX                                          ; otherwise increment offset by 2 bytes
ClimbFD:
	DEY                                          ; check to see if facing right
	BEQ CSetFDir                                 ; if so, branch, do not increment
	INX                                          ; otherwise increment by 1 byte
CSetFDir:
	LDA Player_X_Position
	CLC                                          ; add or subtract from player's horizontal position
	ADC ClimbAdderLow,x                          ; using value here as adder and X as offset
	STA Player_X_Position
	LDA Player_PageLoc                           ; add or subtract carry or borrow using value here
	ADC ClimbAdderHigh,x                         ; from the player's page location
	STA Player_PageLoc
	LDA Left_Right_Buttons                       ; get left/right controller bits again
	EOR #%00000011                               ; invert them and store them while player
	STA PlayerFacingDir                          ; is on vine to face player in opposite direction
ExitCSub:
	RTS                                          ; then leave
InitCSTimer:
	STA ClimbSideTimer                           ; initialize timer here
	RTS

; -------------------------------------------------------------------------------------
; $00 - used to store offset to friction data

JumpMForceData:
	.db $20, $20, $1e, $28, $28, $0d, $04

FallMForceData:
	.db $70, $70, $60, $90, $90, $0a, $09

PlayerYSpdData:
	.db $fc, $fc, $fc, $fb, $fb, $fe, $ff

InitMForceData:
	.db $00, $00, $00, $00, $00, $80, $00

MaxLeftXSpdData:
	.db $d8, $e8, $f0

MaxRightXSpdData:
	.db $28, $18, $10
	.db $0c                                      ; used for pipe intros

FrictionData:
	.db $e4, $98, $d0

Climb_Y_SpeedData:
	.db $00, $ff, $01

Climb_Y_MForceData:
	.db $00, $20, $ff

PlayerPhysicsSub:
	LDA Player_State                             ; check player state
	CMP #$03
	BNE CheckForJumping                          ; if not climbing, branch
	LDY #$00
	LDA Up_Down_Buttons                          ; get controller bits for up/down
	AND Player_CollisionBits                     ; check against player's collision detection bits
	BEQ ProcClimb                                ; if not pressing up or down, branch
	INY
	AND #%00001000                               ; check for pressing up
	BNE ProcClimb
	INY
ProcClimb:
	LDX Climb_Y_MForceData,y                     ; load value here
	STX Player_Y_MoveForce                       ; store as vertical movement force
	LDA #$08                                     ; load default animation timing
	LDX Climb_Y_SpeedData,y                      ; load some other value here
	STX Player_Y_Speed                           ; store as vertical speed
	BMI SetCAnim                                 ; if climbing down, use default animation timing value
	LSR                                          ; otherwise divide timer setting by 2
SetCAnim:
	STA PlayerAnimTimerSet                       ; store animation timer setting and leave
	RTS

CheckForJumping:
	LDA JumpspringAnimCtrl                       ; if jumpspring animating,
	BNE NoJump                                   ; skip ahead to something else
	LDA A_B_Buttons                              ; check for A button press
	AND #A_Button
	BEQ NoJump                                   ; if not, branch to something else
	AND PreviousA_B_Buttons                      ; if button not pressed in previous frame, branch
	BEQ ProcJumping
NoJump:
	JMP X_Physics                                ; otherwise, jump to something else

ProcJumping:
	LDA Player_State                             ; check player state
	BEQ InitJS                                   ; if on the ground, branch
	LDA SwimmingFlag                             ; if swimming flag not set, jump to do something else
	BEQ NoJump                                   ; to prevent midair jumping, otherwise continue
	LDA JumpSwimTimer                            ; if jump/swim timer nonzero, branch
	BNE InitJS
	LDA Player_Y_Speed                           ; check player's vertical speed
	BPL InitJS                                   ; if player's vertical speed motionless or down, branch
	JMP X_Physics                                ; if timer at zero and player still rising, do not swim
InitJS:
	LDA #$20                                     ; set jump/swim timer
	STA JumpSwimTimer
	LDY #$00                                     ; initialize vertical force and dummy variable
	STY Player_YMF_Dummy
	STY Player_Y_MoveForce
	LDA Player_Y_HighPos                         ; get vertical high and low bytes of jump origin
	STA JumpOrigin_Y_HighPos                     ; and store them next to each other here
	LDA Player_Y_Position
	STA JumpOrigin_Y_Position
	LDA #$01                                     ; set player state to jumping/swimming
	STA Player_State
	LDA Player_XSpeedAbsolute                    ; check value related to walking/running speed
	CMP #$09
	BCC ChkWtr                                   ; branch if below certain values, increment Y
	INY                                          ; for each amount equal or exceeded
	CMP #$10
	BCC ChkWtr
	INY
	CMP #$19
	BCC ChkWtr
	INY
	CMP #$1c
	BCC ChkWtr                                   ; note that for jumping, range is 0-4 for Y
	INY
ChkWtr:
	LDA #$01                                     ; set value here (apparently always set to 1)
	STA DiffToHaltJump
	LDA SwimmingFlag                             ; if swimming flag disabled, branch
	BEQ GetYPhy
	LDY #$05                                     ; otherwise set Y to 5, range is 5-6
	LDA Whirlpool_Flag                           ; if whirlpool flag not set, branch
	BEQ GetYPhy
	INY                                          ; otherwise increment to 6
GetYPhy:
	LDA JumpMForceData,y                         ; store appropriate jump/swim
	STA VerticalForce                            ; data here
	LDA FallMForceData,y
	STA VerticalForceDown
	LDA InitMForceData,y
	STA Player_Y_MoveForce
	LDA PlayerYSpdData,y
	STA Player_Y_Speed
	LDA SwimmingFlag                             ; if swimming flag disabled, branch
	BEQ PJumpSnd
	LDA #Sfx_EnemyStomp                          ; load swim/goomba stomp sound into
	STA Square1SoundQueue                        ; square 1's sfx queue
	LDA Player_Y_Position
	CMP #$14                                     ; check vertical low byte of player position
	BCS X_Physics                                ; if below a certain point, branch
	LDA #$00                                     ; otherwise reset player's vertical speed
	STA Player_Y_Speed                           ; and jump to something else to keep player
	JMP X_Physics                                ; from swimming above water level
PJumpSnd:
	LDA #Sfx_BigJump                             ; load big mario's jump sound by default
	LDY PlayerSize                               ; is mario big?
	BEQ SJumpSnd
	LDA #Sfx_SmallJump                           ; if not, load small mario's jump sound
SJumpSnd:
	STA Square1SoundQueue                        ; store appropriate jump sound in square 1 sfx queue
X_Physics:
	LDY #$00
	STY $00                                      ; init value here
	LDA Player_State                             ; if mario is on the ground, branch
	BEQ ProcPRun
	LDA Player_XSpeedAbsolute                    ; check something that seems to be related
	CMP #$19                                     ; to mario's speed
	BCS GetXPhy                                  ; if =>$19 branch here
	BCC ChkRFast                                 ; if not branch elsewhere
ProcPRun:
	INY                                          ; if mario on the ground, increment Y
	LDA AreaType                                 ; check area type
	BEQ ChkRFast                                 ; if water type, branch
	DEY                                          ; decrement Y by default for non-water type area
	LDA Left_Right_Buttons                       ; get left/right controller bits
	CMP Player_MovingDir                         ; check against moving direction
	BNE ChkRFast                                 ; if controller bits <> moving direction, skip this part
	LDA A_B_Buttons                              ; check for b button pressed
	AND #B_Button
	BNE SetRTmr                                  ; if pressed, skip ahead to set timer
	LDA RunningTimer                             ; check for running timer set
	BNE GetXPhy                                  ; if set, branch
ChkRFast:
	INY                                          ; if running timer not set or level type is water,
	INC $00                                      ; increment Y again and temp variable in memory
	LDA RunningSpeed
	BNE FastXSp                                  ; if running speed set here, branch
	LDA Player_XSpeedAbsolute
	CMP #$21                                     ; otherwise check player's walking/running speed
	BCC GetXPhy                                  ; if less than a certain amount, branch ahead
FastXSp:
	INC $00                                      ; if running speed set or speed => $21 increment $00
	JMP GetXPhy                                  ; and jump ahead
SetRTmr:
	LDA #$0a                                     ; if b button pressed, set running timer
	STA RunningTimer
GetXPhy:
	LDA MaxLeftXSpdData,y                        ; get maximum speed to the left
	STA MaximumLeftSpeed
	LDA GameEngineSubroutine                     ; check for specific routine running
	CMP #$07                                     ; (player entrance)
	BNE GetXPhy2                                 ; if not running, skip and use old value of Y
	LDY #$03                                     ; otherwise set Y to 3
GetXPhy2:
	LDA MaxRightXSpdData,y                       ; get maximum speed to the right
	STA MaximumRightSpeed
	LDY $00                                      ; get other value in memory
	LDA FrictionData,y                           ; get value using value in memory as offset
	STA FrictionAdderLow
	LDA #$00
	STA FrictionAdderHigh                        ; init something here
	LDA PlayerFacingDir
	CMP Player_MovingDir                         ; check facing direction against moving direction
	BEQ ExitPhy                                  ; if the same, branch to leave
	ASL FrictionAdderLow                         ; otherwise shift d7 of friction adder low into carry
	ROL FrictionAdderHigh                        ; then rotate carry onto d0 of friction adder high
ExitPhy:
	RTS                                          ; and then leave

; -------------------------------------------------------------------------------------

PlayerAnimTmrData:
	.db $02, $04, $07

GetPlayerAnimSpeed:
	LDY #$00                                     ; initialize offset in Y
	LDA Player_XSpeedAbsolute                    ; check player's walking/running speed
	CMP #$1c                                     ; against preset amount
	BCS SetRunSpd                                ; if greater than a certain amount, branch ahead
	INY                                          ; otherwise increment Y
	CMP #$0e                                     ; compare against lower amount
	BCS ChkSkid                                  ; if greater than this but not greater than first, skip increment
	INY                                          ; otherwise increment Y again
ChkSkid:
	LDA SavedJoypadBits                          ; get controller bits
	AND #%01111111                               ; mask out A button
	BEQ SetAnimSpd                               ; if no other buttons pressed, branch ahead of all this
	AND #$03                                     ; mask out all others except left and right
	CMP Player_MovingDir                         ; check against moving direction
	BNE ProcSkid                                 ; if left/right controller bits <> moving direction, branch
	LDA #$00                                     ; otherwise set zero value here
SetRunSpd:
	STA RunningSpeed                             ; store zero or running speed here
	JMP SetAnimSpd
ProcSkid:
	LDA Player_XSpeedAbsolute                    ; check player's walking/running speed
	CMP #$0b                                     ; against one last amount
	BCS SetAnimSpd                               ; if greater than this amount, branch
	LDA PlayerFacingDir
	STA Player_MovingDir                         ; otherwise use facing direction to set moving direction
	LDA #$00
	STA Player_X_Speed                           ; nullify player's horizontal speed
	STA Player_X_MoveForce                       ; and dummy variable for player
SetAnimSpd:
	LDA PlayerAnimTmrData,y                      ; get animation timer setting using Y as offset
	STA PlayerAnimTimerSet
	RTS

; -------------------------------------------------------------------------------------

ImposeFriction:
	AND Player_CollisionBits                     ; perform AND between left/right controller bits and collision flag
	CMP #$00                                     ; then compare to zero (this instruction is redundant)
	BNE JoypFrict                                ; if any bits set, branch to next part
	LDA Player_X_Speed
	BEQ SetAbsSpd                                ; if player has no horizontal speed, branch ahead to last part
	BPL RghtFrict                                ; if player moving to the right, branch to slow
	BMI LeftFrict                                ; otherwise logic dictates player moving left, branch to slow
JoypFrict:
	LSR                                          ; put right controller bit into carry
	BCC RghtFrict                                ; if left button pressed, carry = 0, thus branch
LeftFrict:
	LDA Player_X_MoveForce                       ; load value set here
	CLC
	ADC FrictionAdderLow                         ; add to it another value set here
	STA Player_X_MoveForce                       ; store here
	LDA Player_X_Speed
	ADC FrictionAdderHigh                        ; add value plus carry to horizontal speed
	STA Player_X_Speed                           ; set as new horizontal speed
	CMP MaximumRightSpeed                        ; compare against maximum value for right movement
	BMI XSpdSign                                 ; if horizontal speed greater negatively, branch
	LDA MaximumRightSpeed                        ; otherwise set preset value as horizontal speed
	STA Player_X_Speed                           ; thus slowing the player's left movement down
	JMP SetAbsSpd                                ; skip to the end
RghtFrict:
	LDA Player_X_MoveForce                       ; load value set here
	SEC
	SBC FrictionAdderLow                         ; subtract from it another value set here
	STA Player_X_MoveForce                       ; store here
	LDA Player_X_Speed
	SBC FrictionAdderHigh                        ; subtract value plus borrow from horizontal speed
	STA Player_X_Speed                           ; set as new horizontal speed
	CMP MaximumLeftSpeed                         ; compare against maximum value for left movement
	BPL XSpdSign                                 ; if horizontal speed greater positively, branch
	LDA MaximumLeftSpeed                         ; otherwise set preset value as horizontal speed
	STA Player_X_Speed                           ; thus slowing the player's right movement down
XSpdSign:
	CMP #$00                                     ; if player not moving or moving to the right,
	BPL SetAbsSpd                                ; branch and leave horizontal speed value unmodified
	EOR #$ff
	CLC                                          ; otherwise get two's compliment to get absolute
	ADC #$01                                     ; unsigned walking/running speed
SetAbsSpd:
	STA Player_XSpeedAbsolute                    ; store walking/running speed here and leave
	RTS

; -------------------------------------------------------------------------------------
; $00 - used to store downward movement force in FireballObjCore
; $02 - used to store maximum vertical speed in FireballObjCore
; $07 - used to store pseudorandom bit in BubbleCheck

ProcFireball_Bubble:
	LDA PlayerStatus                             ; check player's status
	CMP #$02
	BCC ProcAirBubbles                           ; if not fiery, branch
	LDA A_B_Buttons
	AND #B_Button                                ; check for b button pressed
	BEQ ProcFireballs                            ; branch if not pressed
	AND PreviousA_B_Buttons
	BNE ProcFireballs                            ; if button pressed in previous frame, branch
	LDA FireballCounter                          ; load fireball counter
	AND #%00000001                               ; get LSB and use as offset for buffer
	TAX
	LDA Fireball_State,x                         ; load fireball state
	BNE ProcFireballs                            ; if not inactive, branch
	LDY Player_Y_HighPos                         ; if player too high or too low, branch
	DEY
	BNE ProcFireballs
	LDA CrouchingFlag                            ; if player crouching, branch
	BNE ProcFireballs
	LDA Player_State                             ; if player's state = climbing, branch
	CMP #$03
	BEQ ProcFireballs
	LDA #Sfx_Fireball                            ; play fireball sound effect
	STA Square1SoundQueue
	LDA #$02                                     ; load state
	STA Fireball_State,x
	LDY PlayerAnimTimerSet                       ; copy animation frame timer setting
	STY FireballThrowingTimer                    ; into fireball throwing timer
	DEY
	STY PlayerAnimTimer                          ; decrement and store in player's animation timer
	INC FireballCounter                          ; increment fireball counter

ProcFireballs:
	LDX #$00
	JSR FireballObjCore                          ; process first fireball object
	LDX #$01
	JSR FireballObjCore                          ; process second fireball object, then do air bubbles

ProcAirBubbles:
	LDA AreaType                                 ; if not water type level, skip the rest of this
	BNE BublExit
	LDX #$02                                     ; otherwise load counter and use as offset
BublLoop:
	STX ObjectOffset                             ; store offset
	JSR BubbleCheck                              ; check timers and coordinates, create air bubble
	JSR RelativeBubblePosition                   ; get relative coordinates
	JSR GetBubbleOffscreenBits                   ; get offscreen information
	JSR DrawBubble                               ; draw the air bubble
	DEX
	BPL BublLoop                                 ; do this until all three are handled
BublExit:
	RTS                                          ; then leave

FireballXSpdData:
	.db $40, $c0

FireballObjCore:
	STX ObjectOffset                             ; store offset as current object
	LDA Fireball_State,x                         ; check for d7 = 1
	ASL
	BCS FireballExplosion                        ; if so, branch to get relative coordinates and draw explosion
	LDY Fireball_State,x                         ; if fireball inactive, branch to leave
	BEQ NoFBall
	DEY                                          ; if fireball state set to 1, skip this part and just run it
	BEQ RunFB
	LDA Player_X_Position                        ; get player's horizontal position
	ADC #$04                                     ; add four pixels and store as fireball's horizontal position
	STA Fireball_X_Position,x
	LDA Player_PageLoc                           ; get player's page location
	ADC #$00                                     ; add carry and store as fireball's page location
	STA Fireball_PageLoc,x
	LDA Player_Y_Position                        ; get player's vertical position and store
	STA Fireball_Y_Position,x
	LDA #$01                                     ; set high byte of vertical position
	STA Fireball_Y_HighPos,x
	LDY PlayerFacingDir                          ; get player's facing direction
	DEY                                          ; decrement to use as offset here
	LDA FireballXSpdData,y                       ; set horizontal speed of fireball accordingly
	STA Fireball_X_Speed,x
	LDA #$04                                     ; set vertical speed of fireball
	STA Fireball_Y_Speed,x
	LDA #$07
	STA Fireball_BoundBoxCtrl,x                  ; set bounding box size control for fireball
	DEC Fireball_State,x                         ; decrement state to 1 to skip this part from now on
RunFB:
	TXA                                          ; add 7 to offset to use
	CLC                                          ; as fireball offset for next routines
	ADC #$07
	TAX
	LDA #$50                                     ; set downward movement force here
	STA $00
	LDA #$03                                     ; set maximum speed here
	STA $02
	LDA #$00
	JSR ImposeGravity                            ; do sub here to impose gravity on fireball and move vertically
	JSR MoveObjectHorizontally                   ; do another sub to move it horizontally
	LDX ObjectOffset                             ; return fireball offset to X
	JSR RelativeFireballPosition                 ; get relative coordinates
	JSR GetFireballOffscreenBits                 ; get offscreen information
	JSR GetFireballBoundBox                      ; get bounding box coordinates
	JSR FireballBGCollision                      ; do fireball to background collision detection
	LDA FBall_OffscreenBits                      ; get fireball offscreen bits
	AND #%11001100                               ; mask out certain bits
	BNE EraseFB                                  ; if any bits still set, branch to kill fireball
	JSR FireballEnemyCollision                   ; do fireball to enemy collision detection and deal with collisions
	JMP DrawFireball                             ; draw fireball appropriately and leave
EraseFB:
	LDA #$00                                     ; erase fireball state
	STA Fireball_State,x
NoFBall:
	RTS                                          ; leave

FireballExplosion:
	JSR RelativeFireballPosition
	JMP DrawExplosion_Fireball

BubbleCheck:
	LDA PseudoRandomBitReg+1,x                   ; get part of LSFR
	AND #$01
	STA $07                                      ; store pseudorandom bit here
	LDA Bubble_Y_Position,x                      ; get vertical coordinate for air bubble
	CMP #$f8                                     ; if offscreen coordinate not set,
	BNE MoveBubl                                 ; branch to move air bubble
	LDA AirBubbleTimer                           ; if air bubble timer not expired,
	BNE ExitBubl                                 ; branch to leave, otherwise create new air bubble

SetupBubble:
	LDY #$00                                     ; load default value here
	LDA PlayerFacingDir                          ; get player's facing direction
	LSR                                          ; move d0 to carry
	BCC PosBubl                                  ; branch to use default value if facing left
	LDY #$08                                     ; otherwise load alternate value here
PosBubl:
	TYA                                          ; use value loaded as adder
	ADC Player_X_Position                        ; add to player's horizontal position
	STA Bubble_X_Position,x                      ; save as horizontal position for airbubble
	LDA Player_PageLoc
	ADC #$00                                     ; add carry to player's page location
	STA Bubble_PageLoc,x                         ; save as page location for airbubble
	LDA Player_Y_Position
	CLC                                          ; add eight pixels to player's vertical position
	ADC #$08
	STA Bubble_Y_Position,x                      ; save as vertical position for air bubble
	LDA #$01
	STA Bubble_Y_HighPos,x                       ; set vertical high byte for air bubble
	LDY $07                                      ; get pseudorandom bit, use as offset
	LDA BubbleTimerData,y                        ; get data for air bubble timer
	STA AirBubbleTimer                           ; set air bubble timer
MoveBubl:
	LDY $07                                      ; get pseudorandom bit again, use as offset
	LDA Bubble_YMF_Dummy,x
	SEC                                          ; subtract pseudorandom amount from dummy variable
	SBC Bubble_MForceData,y
	STA Bubble_YMF_Dummy,x                       ; save dummy variable
	LDA Bubble_Y_Position,x
	SBC #$00                                     ; subtract borrow from airbubble's vertical coordinate
	CMP #$20                                     ; if below the status bar,
	BCS Y_Bubl                                   ; branch to go ahead and use to move air bubble upwards
	LDA #$f8                                     ; otherwise set offscreen coordinate
Y_Bubl:
	STA Bubble_Y_Position,x                      ; store as new vertical coordinate for air bubble
ExitBubl:
	RTS                                          ; leave

Bubble_MForceData:
	.db $ff, $50

BubbleTimerData:
	.db $40, $20

; -------------------------------------------------------------------------------------

RunGameTimer:
	LDA OperMode                                 ; get primary mode of operation
	BEQ ExGTimer                                 ; branch to leave if in title screen mode
	LDA GameEngineSubroutine
	CMP #$08                                     ; if routine number less than eight running,
	BCC ExGTimer                                 ; branch to leave
	CMP #$0b                                     ; if running death routine,
	BEQ ExGTimer                                 ; branch to leave
	LDA Player_Y_HighPos
	CMP #$02                                     ; if player below the screen,
	BCS ExGTimer                                 ; branch to leave regardless of level type
	LDA GameTimerCtrlTimer                       ; if game timer control not yet expired,
	BNE ExGTimer                                 ; branch to leave
	LDA GameTimerDisplay
	ORA GameTimerDisplay+1                       ; otherwise check game timer digits
	ORA GameTimerDisplay+2
	BEQ TimeUpOn                                 ; if game timer digits at 000, branch to time-up code
	LDY GameTimerDisplay                         ; otherwise check first digit
	DEY                                          ; if first digit not on 1,
	BNE ResGTCtrl                                ; branch to reset game timer control
	LDA GameTimerDisplay+1                       ; otherwise check second and third digits
	ORA GameTimerDisplay+2
	BNE ResGTCtrl                                ; if timer not at 100, branch to reset game timer control
	LDA #TimeRunningOutMusic
	STA EventMusicQueue                          ; otherwise load time running out music
ResGTCtrl:
	LDA #$18                                     ; reset game timer control
	STA GameTimerCtrlTimer
	LDY #$23                                     ; set offset for last digit
	LDA #$ff                                     ; set value to decrement game timer digit
	STA DigitModifier+5
	JSR DigitsMathRoutine                        ; do sub to decrement game timer slowly
	LDA #$a4                                     ; set status nybbles to update game timer display
	JMP PrintStatusBarNumbers                    ; do sub to update the display
TimeUpOn:
	STA PlayerStatus                             ; init player status (note A will always be zero here)
	JSR ForceInjury                              ; do sub to kill the player (note player is small here)
	INC GameTimerExpiredFlag                     ; set game timer expiration flag
ExGTimer:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------

WarpZoneObject:
	LDA ScrollLock                               ; check for scroll lock flag
	BEQ ExGTimer                                 ; branch if not set to leave
	LDA Player_Y_Position                        ; check to see if player's vertical coordinate has
	AND Player_Y_HighPos                         ; same bits set as in vertical high byte (why?)
	BNE ExGTimer                                 ; if so, branch to leave
	STA ScrollLock                               ; otherwise nullify scroll lock flag
	INC WarpZoneControl                          ; increment warp zone flag to make warp pipes for warp zone
	JMP EraseEnemyObject                         ; kill this object

; -------------------------------------------------------------------------------------
; $00 - used in WhirlpoolActivate to store whirlpool length / 2, page location of center of whirlpool
; and also to store movement force exerted on player
; $01 - used in ProcessWhirlpools to store page location of right extent of whirlpool
; and in WhirlpoolActivate to store center of whirlpool
; $02 - used in ProcessWhirlpools to store right extent of whirlpool and in
; WhirlpoolActivate to store maximum vertical speed

ProcessWhirlpools:
	LDA AreaType                                 ; check for water type level
	BNE ExitWh                                   ; branch to leave if not found
	STA Whirlpool_Flag                           ; otherwise initialize whirlpool flag
	LDA TimerControl                             ; if master timer control set,
	BNE ExitWh                                   ; branch to leave
	LDY #$04                                     ; otherwise start with last whirlpool data
WhLoop:
	LDA Whirlpool_LeftExtent,y                   ; get left extent of whirlpool
	CLC
	ADC Whirlpool_Length,y                       ; add length of whirlpool
	STA $02                                      ; store result as right extent here
	LDA Whirlpool_PageLoc,y                      ; get page location
	BEQ NextWh                                   ; if none or page 0, branch to get next data
	ADC #$00                                     ; add carry
	STA $01                                      ; store result as page location of right extent here
	LDA Player_X_Position                        ; get player's horizontal position
	SEC
	SBC Whirlpool_LeftExtent,y                   ; subtract left extent
	LDA Player_PageLoc                           ; get player's page location
	SBC Whirlpool_PageLoc,y                      ; subtract borrow
	BMI NextWh                                   ; if player too far left, branch to get next data
	LDA $02                                      ; otherwise get right extent
	SEC
	SBC Player_X_Position                        ; subtract player's horizontal coordinate
	LDA $01                                      ; get right extent's page location
	SBC Player_PageLoc                           ; subtract borrow
	BPL WhirlpoolActivate                        ; if player within right extent, branch to whirlpool code
NextWh:
	DEY                                          ; move onto next whirlpool data
	BPL WhLoop                                   ; do this until all whirlpools are checked
ExitWh:
	RTS                                          ; leave

WhirlpoolActivate:
	LDA Whirlpool_Length,y                       ; get length of whirlpool
	LSR                                          ; divide by 2
	STA $00                                      ; save here
	LDA Whirlpool_LeftExtent,y                   ; get left extent of whirlpool
	CLC
	ADC $00                                      ; add length divided by 2
	STA $01                                      ; save as center of whirlpool
	LDA Whirlpool_PageLoc,y                      ; get page location
	ADC #$00                                     ; add carry
	STA $00                                      ; save as page location of whirlpool center
	LDA FrameCounter                             ; get frame counter
	LSR                                          ; shift d0 into carry (to run on every other frame)
	BCC WhPull                                   ; if d0 not set, branch to last part of code
	LDA $01                                      ; get center
	SEC
	SBC Player_X_Position                        ; subtract player's horizontal coordinate
	LDA $00                                      ; get page location of center
	SBC Player_PageLoc                           ; subtract borrow
	BPL LeftWh                                   ; if player to the left of center, branch
	LDA Player_X_Position                        ; otherwise slowly pull player left, towards the center
	SEC
	SBC #$01                                     ; subtract one pixel
	STA Player_X_Position                        ; set player's new horizontal coordinate
	LDA Player_PageLoc
	SBC #$00                                     ; subtract borrow
	JMP SetPWh                                   ; jump to set player's new page location
LeftWh:
	LDA Player_CollisionBits                     ; get player's collision bits
	LSR                                          ; shift d0 into carry
	BCC WhPull                                   ; if d0 not set, branch
	LDA Player_X_Position                        ; otherwise slowly pull player right, towards the center
	CLC
	ADC #$01                                     ; add one pixel
	STA Player_X_Position                        ; set player's new horizontal coordinate
	LDA Player_PageLoc
	ADC #$00                                     ; add carry
SetPWh:
	STA Player_PageLoc                           ; set player's new page location
WhPull:
	LDA #$10
	STA $00                                      ; set vertical movement force
	LDA #$01
	STA Whirlpool_Flag                           ; set whirlpool flag to be used later
	STA $02                                      ; also set maximum vertical speed
	LSR
	TAX                                          ; set X for player offset
	JMP ImposeGravity                            ; jump to put whirlpool effect on player vertically, do not return

; -------------------------------------------------------------------------------------

FlagpoleScoreMods:
	.db $05, $02, $08, $04, $01

FlagpoleScoreDigits:
	.db $03, $03, $04, $04, $04

FlagpoleRoutine:
	LDX #$05                                     ; set enemy object offset
	STX ObjectOffset                             ; to special use slot
	LDA Enemy_ID,x
	CMP #FlagpoleFlagObject                      ; if flagpole flag not found,
	BNE ExitFlagP                                ; branch to leave
	LDA GameEngineSubroutine
	CMP #$04                                     ; if flagpole slide routine not running,
	BNE SkipScore                                ; branch to near the end of code
	LDA Player_State
	CMP #$03                                     ; if player state not climbing,
	BNE SkipScore                                ; branch to near the end of code
	LDA Enemy_Y_Position,x                       ; check flagpole flag's vertical coordinate
	CMP #$aa                                     ; if flagpole flag down to a certain point,
	BCS GiveFPScr                                ; branch to end the level
	LDA Player_Y_Position                        ; check player's vertical coordinate
	CMP #$a2                                     ; if player down to a certain point,
	BCS GiveFPScr                                ; branch to end the level
	LDA Enemy_YMF_Dummy,x
	ADC #$ff                                     ; add movement amount to dummy variable
	STA Enemy_YMF_Dummy,x                        ; save dummy variable
	LDA Enemy_Y_Position,x                       ; get flag's vertical coordinate
	ADC #$01                                     ; add 1 plus carry to move flag, and
	STA Enemy_Y_Position,x                       ; store vertical coordinate
	LDA FlagpoleFNum_YMFDummy
	SEC                                          ; subtract movement amount from dummy variable
	SBC #$ff
	STA FlagpoleFNum_YMFDummy                    ; save dummy variable
	LDA FlagpoleFNum_Y_Pos
	SBC #$01                                     ; subtract one plus borrow to move floatey number,
	STA FlagpoleFNum_Y_Pos                       ; and store vertical coordinate here
SkipScore:
	JMP FPGfx                                    ; jump to skip ahead and draw flag and floatey number
GiveFPScr:
	LDY FlagpoleScore                            ; get score offset from earlier (when player touched flagpole)
	LDA FlagpoleScoreMods,y                      ; get amount to award player points
	LDX FlagpoleScoreDigits,y                    ; get digit with which to award points
	STA DigitModifier,x                          ; store in digit modifier
	JSR AddToScore                               ; do sub to award player points depending on height of collision
	LDA #$05
	STA GameEngineSubroutine                     ; set to run end-of-level subroutine on next frame
FPGfx:
	JSR GetEnemyOffscreenBits                    ; get offscreen information
	JSR RelativeEnemyPosition                    ; get relative coordinates
	JSR FlagpoleGfxHandler                       ; draw flagpole flag and floatey number
ExitFlagP:
	RTS

; -------------------------------------------------------------------------------------

Jumpspring_Y_PosData:
	.db $08, $10, $08, $00

JumpspringHandler:
	JSR GetEnemyOffscreenBits                    ; get offscreen information
	LDA TimerControl                             ; check master timer control
	BNE DrawJSpr                                 ; branch to last section if set
	LDA JumpspringAnimCtrl                       ; check jumpspring frame control
	BEQ DrawJSpr                                 ; branch to last section if not set
	TAY
	DEY                                          ; subtract one from frame control,
	TYA                                          ; the only way a poor nmos 6502 can
	AND #%00000010                               ; mask out all but d1, original value still in Y
	BNE DownJSpr                                 ; if set, branch to move player up
	INC Player_Y_Position
	INC Player_Y_Position                        ; move player's vertical position down two pixels
	JMP PosJSpr                                  ; skip to next part
DownJSpr:
	DEC Player_Y_Position                        ; move player's vertical position up two pixels
	DEC Player_Y_Position
PosJSpr:
	LDA Jumpspring_FixedYPos,x                   ; get permanent vertical position
	CLC
	ADC Jumpspring_Y_PosData,y                   ; add value using frame control as offset
	STA Enemy_Y_Position,x                       ; store as new vertical position
	CPY #$01                                     ; check frame control offset (second frame is $00)
	BCC BounceJS                                 ; if offset not yet at third frame ($01), skip to next part
	LDA A_B_Buttons
	AND #A_Button                                ; check saved controller bits for A button press
	BEQ BounceJS                                 ; skip to next part if A not pressed
	AND PreviousA_B_Buttons                      ; check for A button pressed in previous frame
	BNE BounceJS                                 ; skip to next part if so
	LDA #$f4
	STA JumpspringForce                          ; otherwise write new jumpspring force here
BounceJS:
	CPY #$03                                     ; check frame control offset again
	BNE DrawJSpr                                 ; skip to last part if not yet at fifth frame ($03)
	LDA JumpspringForce
	STA Player_Y_Speed                           ; store jumpspring force as player's new vertical speed
	LDA #$00
	STA JumpspringAnimCtrl                       ; initialize jumpspring frame control
DrawJSpr:
	JSR RelativeEnemyPosition                    ; get jumpspring's relative coordinates
	JSR EnemyGfxHandler                          ; draw jumpspring
	JSR OffscreenBoundsCheck                     ; check to see if we need to kill it
	LDA JumpspringAnimCtrl                       ; if frame control at zero, don't bother
	BEQ ExJSpring                                ; trying to animate it, just leave
	LDA JumpspringTimer
	BNE ExJSpring                                ; if jumpspring timer not expired yet, leave
	LDA #$04
	STA JumpspringTimer                          ; otherwise initialize jumpspring timer
	INC JumpspringAnimCtrl                       ; increment frame control to animate jumpspring
ExJSpring:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------

Setup_Vine:
	LDA #VineObject                              ; load identifier for vine object
	STA Enemy_ID,x                               ; store in buffer
	LDA #$01
	STA Enemy_Flag,x                             ; set flag for enemy object buffer
	LDA Block_PageLoc,y
	STA Enemy_PageLoc,x                          ; copy page location from previous object
	LDA Block_X_Position,y
	STA Enemy_X_Position,x                       ; copy horizontal coordinate from previous object
	LDA Block_Y_Position,y
	STA Enemy_Y_Position,x                       ; copy vertical coordinate from previous object
	LDY VineFlagOffset                           ; load vine flag/offset to next available vine slot
	BNE NextVO                                   ; if set at all, don't bother to store vertical
	STA VineStart_Y_Position                     ; otherwise store vertical coordinate here
NextVO:
	TXA                                          ; store object offset to next available vine slot
	STA VineObjOffset,y                          ; using vine flag as offset
	INC VineFlagOffset                           ; increment vine flag offset
	LDA #Sfx_GrowVine
	STA Square2SoundQueue                        ; load vine grow sound
	RTS

; -------------------------------------------------------------------------------------
; $06-$07 - used as address to block buffer data
; $02 - used as vertical high nybble of block buffer offset

VineHeightData:
	.db $30, $60

VineObjectHandler:
	CPX #$05                                     ; check enemy offset for special use slot
	BNE ExitVH                                   ; if not in last slot, branch to leave
	LDY VineFlagOffset
	DEY                                          ; decrement vine flag in Y, use as offset
	LDA VineHeight
	CMP VineHeightData,y                         ; if vine has reached certain height,
	BEQ RunVSubs                                 ; branch ahead to skip this part
	LDA FrameCounter                             ; get frame counter
	LSR                                          ; shift d1 into carry
	LSR
	BCC RunVSubs                                 ; if d1 not set (2 frames every 4) skip this part
	LDA Enemy_Y_Position+5
	SBC #$01                                     ; subtract vertical position of vine
	STA Enemy_Y_Position+5                       ; one pixel every frame it's time
	INC VineHeight                               ; increment vine height
RunVSubs:
	LDA VineHeight                               ; if vine still very small,
	CMP #$08                                     ; branch to leave
	BCC ExitVH
	JSR RelativeEnemyPosition                    ; get relative coordinates of vine,
	JSR GetEnemyOffscreenBits                    ; and any offscreen bits
	LDY #$00                                     ; initialize offset used in draw vine sub
VDrawLoop:
	JSR DrawVine                                 ; draw vine
	INY                                          ; increment offset
	CPY VineFlagOffset                           ; if offset in Y and offset here
	BNE VDrawLoop                                ; do not yet match, loop back to draw more vine
	LDA Enemy_OffscreenBits
	AND #%00001100                               ; mask offscreen bits
	BEQ WrCMTile                                 ; if none of the saved offscreen bits set, skip ahead
	DEY                                          ; otherwise decrement Y to get proper offset again
KillVine:
	LDX VineObjOffset,y                          ; get enemy object offset for this vine object
	JSR EraseEnemyObject                         ; kill this vine object
	DEY                                          ; decrement Y
	BPL KillVine                                 ; if any vine objects left, loop back to kill it
	STA VineFlagOffset                           ; initialize vine flag/offset
	STA VineHeight                               ; initialize vine height
WrCMTile:
	LDA VineHeight                               ; check vine height
	CMP #$20                                     ; if vine small (less than 32 pixels tall)
	BCC ExitVH                                   ; then branch ahead to leave
	LDX #$06                                     ; set offset in X to last enemy slot
	LDA #$01                                     ; set A to obtain horizontal in $04, but we don't care
	LDY #$1b                                     ; set Y to offset to get block at ($04, $10) of coordinates
	JSR BlockBufferCollision                     ; do a sub to get block buffer address set, return contents
	LDY $02
	CPY #$d0                                     ; if vertical high nybble offset beyond extent of
	BCS ExitVH                                   ; current block buffer, branch to leave, do not write
	LDA ($06),y                                  ; otherwise check contents of block buffer at
	BNE ExitVH                                   ; current offset, if not empty, branch to leave
	LDA #$26
	STA ($06),y                                  ; otherwise, write climbing metatile to block buffer
ExitVH:
	LDX ObjectOffset                             ; get enemy object offset and leave
	RTS

; -------------------------------------------------------------------------------------

CannonBitmasks:
	.db %00001111, %00000111

ProcessCannons:
	LDA AreaType                                 ; get area type
	BEQ ExCannon                                 ; if water type area, branch to leave
	LDX #$02
ThreeSChk:
	STX ObjectOffset                             ; start at third enemy slot
	LDA Enemy_Flag,x                             ; check enemy buffer flag
	BNE Chk_BB                                   ; if set, branch to check enemy
	LDA PseudoRandomBitReg+1,x                   ; otherwise get part of LSFR
	LDY SecondaryHardMode                        ; get secondary hard mode flag, use as offset
	AND CannonBitmasks,y                         ; mask out bits of LSFR as decided by flag
	CMP #$06                                     ; check to see if lower nybble is above certain value
	BCS Chk_BB                                   ; if so, branch to check enemy
	TAY                                          ; transfer masked contents of LSFR to Y as pseudorandom offset
	LDA Cannon_PageLoc,y                         ; get page location
	BEQ Chk_BB                                   ; if not set or on page 0, branch to check enemy
	LDA Cannon_Timer,y                           ; get cannon timer
	BEQ FireCannon                               ; if expired, branch to fire cannon
	SBC #$00                                     ; otherwise subtract borrow (note carry will always be clear here)
	STA Cannon_Timer,y                           ; to count timer down
	JMP Chk_BB                                   ; then jump ahead to check enemy

FireCannon:
	LDA TimerControl                             ; if master timer control set,
	BNE Chk_BB                                   ; branch to check enemy
	LDA #$0e                                     ; otherwise we start creating one
	STA Cannon_Timer,y                           ; first, reset cannon timer
	LDA Cannon_PageLoc,y                         ; get page location of cannon
	STA Enemy_PageLoc,x                          ; save as page location of bullet bill
	LDA Cannon_X_Position,y                      ; get horizontal coordinate of cannon
	STA Enemy_X_Position,x                       ; save as horizontal coordinate of bullet bill
	LDA Cannon_Y_Position,y                      ; get vertical coordinate of cannon
	SEC
	SBC #$08                                     ; subtract eight pixels (because enemies are 24 pixels tall)
	STA Enemy_Y_Position,x                       ; save as vertical coordinate of bullet bill
	LDA #$01
	STA Enemy_Y_HighPos,x                        ; set vertical high byte of bullet bill
	STA Enemy_Flag,x                             ; set buffer flag
	LSR                                          ; shift right once to init A
	STA Enemy_State,x                            ; then initialize enemy's state
	LDA #$09
	STA Enemy_BoundBoxCtrl,x                     ; set bounding box size control for bullet bill
	LDA #BulletBill_CannonVar
	STA Enemy_ID,x                               ; load identifier for bullet bill (cannon variant)
	JMP Next3Slt                                 ; move onto next slot
Chk_BB:
	LDA Enemy_ID,x                               ; check enemy identifier for bullet bill (cannon variant)
	CMP #BulletBill_CannonVar
	BNE Next3Slt                                 ; if not found, branch to get next slot
	JSR OffscreenBoundsCheck                     ; otherwise, check to see if it went offscreen
	LDA Enemy_Flag,x                             ; check enemy buffer flag
	BEQ Next3Slt                                 ; if not set, branch to get next slot
	JSR GetEnemyOffscreenBits                    ; otherwise, get offscreen information
	JSR BulletBillHandler                        ; then do sub to handle bullet bill
Next3Slt:
	DEX                                          ; move onto next slot
	BPL ThreeSChk                                ; do this until first three slots are checked
ExCannon:
	RTS                                          ; then leave

; --------------------------------

BulletBillXSpdData:
	.db $18, $e8

BulletBillHandler:
	LDA TimerControl                             ; if master timer control set,
	BNE RunBBSubs                                ; branch to run subroutines except movement sub
	LDA Enemy_State,x
	BNE ChkDSte                                  ; if bullet bill's state set, branch to check defeated state
	LDA Enemy_OffscreenBits                      ; otherwise load offscreen bits
	AND #%00001100                               ; mask out bits
	CMP #%00001100                               ; check to see if all bits are set
	BEQ KillBB                                   ; if so, branch to kill this object
	LDY #$01                                     ; set to move right by default
	JSR PlayerEnemyDiff                          ; get horizontal difference between player and bullet bill
	BMI SetupBB                                  ; if enemy to the left of player, branch
	INY                                          ; otherwise increment to move left
SetupBB:
	STY Enemy_MovingDir,x                        ; set bullet bill's moving direction
	DEY                                          ; decrement to use as offset
	LDA BulletBillXSpdData,y                     ; get horizontal speed based on moving direction
	STA Enemy_X_Speed,x                          ; and store it
	LDA $00                                      ; get horizontal difference
	ADC #$28                                     ; add 40 pixels
	CMP #$50                                     ; if less than a certain amount, player is too close
	BCC KillBB                                   ; to cannon either on left or right side, thus branch
	LDA #$01
	STA Enemy_State,x                            ; otherwise set bullet bill's state
	LDA #$0a
	STA EnemyFrameTimer,x                        ; set enemy frame timer
	LDA #Sfx_Blast
	STA Square2SoundQueue                        ; play fireworks/gunfire sound
ChkDSte:
	LDA Enemy_State,x                            ; check enemy state for d5 set
	AND #%00100000
	BEQ BBFly                                    ; if not set, skip to move horizontally
	JSR MoveD_EnemyVertically                    ; otherwise do sub to move bullet bill vertically
BBFly:
	JSR MoveEnemyHorizontally                    ; do sub to move bullet bill horizontally
RunBBSubs:
	JSR GetEnemyOffscreenBits                    ; get offscreen information
	JSR RelativeEnemyPosition                    ; get relative coordinates
	JSR GetEnemyBoundBox                         ; get bounding box coordinates
	JSR PlayerEnemyCollision                     ; handle player to enemy collisions
	JMP EnemyGfxHandler                          ; draw the bullet bill and leave
KillBB:
	JSR EraseEnemyObject                         ; kill bullet bill and leave
	RTS

; -------------------------------------------------------------------------------------

HammerEnemyOfsData:
	.db $04, $04, $04, $05, $05, $05
	.db $06, $06, $06

HammerXSpdData:
	.db $10, $f0

SpawnHammerObj:
	LDA PseudoRandomBitReg+1                     ; get pseudorandom bits from
	AND #%00000111                               ; second part of LSFR
	BNE SetMOfs                                  ; if any bits are set, branch and use as offset
	LDA PseudoRandomBitReg+1
	AND #%00001000                               ; get d3 from same part of LSFR
SetMOfs:
	TAY                                          ; use either d3 or d2-d0 for offset here
	LDA Misc_State,y                             ; if any values loaded in
	BNE NoHammer                                 ; $2a-$32 where offset is then leave with carry clear
	LDX HammerEnemyOfsData,y                     ; get offset of enemy slot to check using Y as offset
	LDA Enemy_Flag,x                             ; check enemy buffer flag at offset
	BNE NoHammer                                 ; if buffer flag set, branch to leave with carry clear
	LDX ObjectOffset                             ; get original enemy object offset
	TXA
	STA HammerEnemyOffset,y                      ; save here
	LDA #$90
	STA Misc_State,y                             ; save hammer's state here
	LDA #$07
	STA Misc_BoundBoxCtrl,y                      ; set something else entirely, here
	SEC                                          ; return with carry set
	RTS
NoHammer:
	LDX ObjectOffset                             ; get original enemy object offset
	CLC                                          ; return with carry clear
	RTS

; --------------------------------
; $00 - used to set downward force
; $01 - used to set upward force (residual)
; $02 - used to set maximum speed

ProcHammerObj:
	LDA TimerControl                             ; if master timer control set
	BNE RunHSubs                                 ; skip all of this code and go to last subs at the end
	LDA Misc_State,x                             ; otherwise get hammer's state
	AND #%01111111                               ; mask out d7
	LDY HammerEnemyOffset,x                      ; get enemy object offset that spawned this hammer
	CMP #$02                                     ; check hammer's state
	BEQ SetHSpd                                  ; if currently at 2, branch
	BCS SetHPos                                  ; if greater than 2, branch elsewhere
	TXA
	CLC                                          ; add 13 bytes to use
	ADC #$0d                                     ; proper misc object
	TAX                                          ; return offset to X
	LDA #$10
	STA $00                                      ; set downward movement force
	LDA #$0f
	STA $01                                      ; set upward movement force (not used)
	LDA #$04
	STA $02                                      ; set maximum vertical speed
	LDA #$00                                     ; set A to impose gravity on hammer
	JSR ImposeGravity                            ; do sub to impose gravity on hammer and move vertically
	JSR MoveObjectHorizontally                   ; do sub to move it horizontally
	LDX ObjectOffset                             ; get original misc object offset
	JMP RunAllH                                  ; branch to essential subroutines
SetHSpd:
	LDA #$fe
	STA Misc_Y_Speed,x                           ; set hammer's vertical speed
	LDA Enemy_State,y                            ; get enemy object state
	AND #%11110111                               ; mask out d3
	STA Enemy_State,y                            ; store new state
	LDX Enemy_MovingDir,y                        ; get enemy's moving direction
	DEX                                          ; decrement to use as offset
	LDA HammerXSpdData,x                         ; get proper speed to use based on moving direction
	LDX ObjectOffset                             ; reobtain hammer's buffer offset
	STA Misc_X_Speed,x                           ; set hammer's horizontal speed
SetHPos:
	DEC Misc_State,x                             ; decrement hammer's state
	LDA Enemy_X_Position,y                       ; get enemy's horizontal position
	CLC
	ADC #$02                                     ; set position 2 pixels to the right
	STA Misc_X_Position,x                        ; store as hammer's horizontal position
	LDA Enemy_PageLoc,y                          ; get enemy's page location
	ADC #$00                                     ; add carry
	STA Misc_PageLoc,x                           ; store as hammer's page location
	LDA Enemy_Y_Position,y                       ; get enemy's vertical position
	SEC
	SBC #$0a                                     ; move position 10 pixels upward
	STA Misc_Y_Position,x                        ; store as hammer's vertical position
	LDA #$01
	STA Misc_Y_HighPos,x                         ; set hammer's vertical high byte
	BNE RunHSubs                                 ; unconditional branch to skip first routine
RunAllH:
	JSR PlayerHammerCollision                    ; handle collisions
RunHSubs:
	JSR GetMiscOffscreenBits                     ; get offscreen information
	JSR RelativeMiscPosition                     ; get relative coordinates
	JSR GetMiscBoundBox                          ; get bounding box coordinates
	JSR DrawHammer                               ; draw the hammer
	RTS                                          ; and we are done here

; -------------------------------------------------------------------------------------
; $02 - used to store vertical high nybble offset from block buffer routine
; $06 - used to store low byte of block buffer address

CoinBlock:
	JSR FindEmptyMiscSlot                        ; set offset for empty or last misc object buffer slot
	LDA Block_PageLoc,x                          ; get page location of block object
	STA Misc_PageLoc,y                           ; store as page location of misc object
	LDA Block_X_Position,x                       ; get horizontal coordinate of block object
	ORA #$05                                     ; add 5 pixels
	STA Misc_X_Position,y                        ; store as horizontal coordinate of misc object
	LDA Block_Y_Position,x                       ; get vertical coordinate of block object
	SBC #$10                                     ; subtract 16 pixels
	STA Misc_Y_Position,y                        ; store as vertical coordinate of misc object
	JMP JCoinC                                   ; jump to rest of code as applies to this misc object

SetupJumpCoin:
	JSR FindEmptyMiscSlot                        ; set offset for empty or last misc object buffer slot
	LDA Block_PageLoc2,x                         ; get page location saved earlier
	STA Misc_PageLoc,y                           ; and save as page location for misc object
	LDA $06                                      ; get low byte of block buffer offset
	ASL
	ASL                                          ; multiply by 16 to use lower nybble
	ASL
	ASL
	ORA #$05                                     ; add five pixels
	STA Misc_X_Position,y                        ; save as horizontal coordinate for misc object
	LDA $02                                      ; get vertical high nybble offset from earlier
	ADC #$20                                     ; add 32 pixels for the status bar
	STA Misc_Y_Position,y                        ; store as vertical coordinate
JCoinC:
	LDA #$fb
	STA Misc_Y_Speed,y                           ; set vertical speed
	LDA #$01
	STA Misc_Y_HighPos,y                         ; set vertical high byte
	STA Misc_State,y                             ; set state for misc object
	STA Square2SoundQueue                        ; load coin grab sound
	STX ObjectOffset                             ; store current control bit as misc object offset
	JSR GiveOneCoin                              ; update coin tally on the screen and coin amount variable
	INC CoinTallyFor1Ups                         ; increment coin tally used to activate 1-up block flag
	RTS

FindEmptyMiscSlot:
	LDY #$08                                     ; start at end of misc objects buffer
FMiscLoop:
	LDA Misc_State,y                             ; get misc object state
	BEQ UseMiscS                                 ; branch if none found to use current offset
	DEY                                          ; decrement offset
	CPY #$05                                     ; do this for three slots
	BNE FMiscLoop                                ; do this until all slots are checked
	LDY #$08                                     ; if no empty slots found, use last slot
UseMiscS:
	STY JumpCoinMiscOffset                       ; store offset of misc object buffer here (residual)
	RTS

; -------------------------------------------------------------------------------------

MiscObjectsCore:
	LDX #$08                                     ; set at end of misc object buffer
MiscLoop:
	STX ObjectOffset                             ; store misc object offset here
	LDA Misc_State,x                             ; check misc object state
	BEQ MiscLoopBack                             ; branch to check next slot
	ASL                                          ; otherwise shift d7 into carry
	BCC ProcJumpCoin                             ; if d7 not set, jumping coin, thus skip to rest of code here
	JSR ProcHammerObj                            ; otherwise go to process hammer,
	JMP MiscLoopBack                             ; then check next slot

; --------------------------------
; $00 - used to set downward force
; $01 - used to set upward force (residual)
; $02 - used to set maximum speed

ProcJumpCoin:
	LDY Misc_State,x                             ; check misc object state
	DEY                                          ; decrement to see if it's set to 1
	BEQ JCoinRun                                 ; if so, branch to handle jumping coin
	INC Misc_State,x                             ; otherwise increment state to either start off or as timer
	LDA Misc_X_Position,x                        ; get horizontal coordinate for misc object
	CLC                                          ; whether its jumping coin (state 0 only) or floatey number
	ADC ScrollAmount                             ; add current scroll speed
	STA Misc_X_Position,x                        ; store as new horizontal coordinate
	LDA Misc_PageLoc,x                           ; get page location
	ADC #$00                                     ; add carry
	STA Misc_PageLoc,x                           ; store as new page location
	LDA Misc_State,x
	CMP #$30                                     ; check state of object for preset value
	BNE RunJCSubs                                ; if not yet reached, branch to subroutines
	LDA #$00
	STA Misc_State,x                             ; otherwise nullify object state
	JMP MiscLoopBack                             ; and move onto next slot
JCoinRun:
	TXA
	CLC                                          ; add 13 bytes to offset for next subroutine
	ADC #$0d
	TAX
	LDA #$50                                     ; set downward movement amount
	STA $00
	LDA #$06                                     ; set maximum vertical speed
	STA $02
	LSR                                          ; divide by 2 and set
	STA $01                                      ; as upward movement amount (apparently residual)
	LDA #$00                                     ; set A to impose gravity on jumping coin
	JSR ImposeGravity                            ; do sub to move coin vertically and impose gravity on it
	LDX ObjectOffset                             ; get original misc object offset
	LDA Misc_Y_Speed,x                           ; check vertical speed
	CMP #$05
	BNE RunJCSubs                                ; if not moving downward fast enough, keep state as-is
	INC Misc_State,x                             ; otherwise increment state to change to floatey number
RunJCSubs:
	JSR RelativeMiscPosition                     ; get relative coordinates
	JSR GetMiscOffscreenBits                     ; get offscreen information
	JSR GetMiscBoundBox                          ; get bounding box coordinates (why?)
	JSR JCoinGfxHandler                          ; draw the coin or floatey number

MiscLoopBack:

	DEX                                          ; decrement misc object offset
	BPL MiscLoop                                 ; loop back until all misc objects handled
	RTS                                          ; then leave

; -------------------------------------------------------------------------------------

CoinTallyOffsets:
	.db $17, $1d

ScoreOffsets:
	.db $0b, $11

StatusBarNybbles:
	.db $02, $13

GiveOneCoin:
	LDA #$01                                     ; set digit modifier to add 1 coin
	STA DigitModifier+5                          ; to the current player's coin tally
	LDX CurrentPlayer                            ; get current player on the screen
	LDY CoinTallyOffsets,x                       ; get offset for player's coin tally
	JSR DigitsMathRoutine                        ; update the coin tally
	INC CoinTally                                ; increment onscreen player's coin amount
	LDA CoinTally
	CMP #100                                     ; does player have 100 coins yet?
	BNE CoinPoints                               ; if not, skip all of this
	LDA #$00
	STA CoinTally                                ; otherwise, reinitialize coin amount
	INC NumberofLives                            ; give the player an extra life
	LDA #Sfx_ExtraLife
	STA Square2SoundQueue                        ; play 1-up sound

CoinPoints:
	LDA #$02                                     ; set digit modifier to award
	STA DigitModifier+4                          ; 200 points to the player

AddToScore:
	LDX CurrentPlayer                            ; get current player
	LDY ScoreOffsets,x                           ; get offset for player's score
	JSR DigitsMathRoutine                        ; update the score internally with value in digit modifier

GetSBNybbles:
	LDY CurrentPlayer                            ; get current player
	LDA StatusBarNybbles,y                       ; get nybbles based on player, use to update score and coins

UpdateNumber:
	JSR PrintStatusBarNumbers                    ; print status bar numbers based on nybbles, whatever they be
	LDY VRAM_Buffer1_Offset
	LDA VRAM_Buffer1-6,y                         ; check highest digit of score
	BNE NoZSup                                   ; if zero, overwrite with space tile for zero suppression
	LDA #$24
	STA VRAM_Buffer1-6,y
NoZSup:
	LDX ObjectOffset                             ; get enemy object buffer offset
	RTS

; -------------------------------------------------------------------------------------

SetupPowerUp:
	LDA #PowerUpObject                           ; load power-up identifier into
	STA Enemy_ID+5                               ; special use slot of enemy object buffer
	LDA Block_PageLoc,x                          ; store page location of block object
	STA Enemy_PageLoc+5                          ; as page location of power-up object
	LDA Block_X_Position,x                       ; store horizontal coordinate of block object
	STA Enemy_X_Position+5                       ; as horizontal coordinate of power-up object
	LDA #$01
	STA Enemy_Y_HighPos+5                        ; set vertical high byte of power-up object
	LDA Block_Y_Position,x                       ; get vertical coordinate of block object
	SEC
	SBC #$08                                     ; subtract 8 pixels
	STA Enemy_Y_Position+5                       ; and use as vertical coordinate of power-up object
PwrUpJmp:
	LDA #$01                                     ; this is a residual jump point in enemy object jump table
	STA Enemy_State+5                            ; set power-up object's state
	STA Enemy_Flag+5                             ; set buffer flag
	LDA #$03
	STA Enemy_BoundBoxCtrl+5                     ; set bounding box size control for power-up object
	LDA PowerUpType
	CMP #$02                                     ; check currently loaded power-up type
	BCS PutBehind                                ; if star or 1-up, branch ahead
	LDA PlayerStatus                             ; otherwise check player's current status
	CMP #$02
	BCC StrType                                  ; if player not fiery, use status as power-up type
	LSR                                          ; otherwise shift right to force fire flower type
StrType:
	STA PowerUpType                              ; store type here
PutBehind:
	LDA #%00100000
	STA Enemy_SprAttrib+5                        ; set background priority bit
	LDA #Sfx_GrowPowerUp
	STA Square2SoundQueue                        ; load power-up reveal sound and leave
	RTS

; -------------------------------------------------------------------------------------

PowerUpObjHandler:
	LDX #$05                                     ; set object offset for last slot in enemy object buffer
	STX ObjectOffset
	LDA Enemy_State+5                            ; check power-up object's state
	BEQ ExitPUp                                  ; if not set, branch to leave
	ASL                                          ; shift to check if d7 was set in object state
	BCC GrowThePowerUp                           ; if not set, branch ahead to skip this part
	LDA TimerControl                             ; if master timer control set,
	BNE RunPUSubs                                ; branch ahead to enemy object routines
	LDA PowerUpType                              ; check power-up type
	BEQ ShroomM                                  ; if normal mushroom, branch ahead to move it
	CMP #$03
	BEQ ShroomM                                  ; if 1-up mushroom, branch ahead to move it
	CMP #$02
	BNE RunPUSubs                                ; if not star, branch elsewhere to skip movement
	JSR MoveJumpingEnemy                         ; otherwise impose gravity on star power-up and make it jump
	JSR EnemyJump                                ; note that green paratroopa shares the same code here
	JMP RunPUSubs                                ; then jump to other power-up subroutines
ShroomM:
	JSR MoveNormalEnemy                          ; do sub to make mushrooms move
	JSR EnemyToBGCollisionDet                    ; deal with collisions
	JMP RunPUSubs                                ; run the other subroutines

GrowThePowerUp:
	LDA FrameCounter                             ; get frame counter
	AND #$03                                     ; mask out all but 2 LSB
	BNE ChkPUSte                                 ; if any bits set here, branch
	DEC Enemy_Y_Position+5                       ; otherwise decrement vertical coordinate slowly
	LDA Enemy_State+5                            ; load power-up object state
	INC Enemy_State+5                            ; increment state for next frame (to make power-up rise)
	CMP #$11                                     ; if power-up object state not yet past 16th pixel,
	BCC ChkPUSte                                 ; branch ahead to last part here
	LDA #$10
	STA Enemy_X_Speed,x                          ; otherwise set horizontal speed
	LDA #%10000000
	STA Enemy_State+5                            ; and then set d7 in power-up object's state
	ASL                                          ; shift once to init A
	STA Enemy_SprAttrib+5                        ; initialize background priority bit set here
	ROL                                          ; rotate A to set right moving direction
	STA Enemy_MovingDir,x                        ; set moving direction
ChkPUSte:
	LDA Enemy_State+5                            ; check power-up object's state
	CMP #$06                                     ; for if power-up has risen enough
	BCC ExitPUp                                  ; if not, don't even bother running these routines
RunPUSubs:
	JSR RelativeEnemyPosition                    ; get coordinates relative to screen
	JSR GetEnemyOffscreenBits                    ; get offscreen bits
	JSR GetEnemyBoundBox                         ; get bounding box coordinates
	JSR DrawPowerUp                              ; draw the power-up object
	JSR PlayerEnemyCollision                     ; check for collision with player
	JSR OffscreenBoundsCheck                     ; check to see if it went offscreen
ExitPUp:
	RTS                                          ; and we're done

; -------------------------------------------------------------------------------------
; These apply to all routines in this section unless otherwise noted:
; $00 - used to store metatile from block buffer routine
; $02 - used to store vertical high nybble offset from block buffer routine
; $05 - used to store metatile stored in A at beginning of PlayerHeadCollision
; $06-$07 - used as block buffer address indirect

BlockYPosAdderData:
	.db $04, $12

PlayerHeadCollision:
	PHA                                          ; store metatile number to stack
	LDA #$11                                     ; load unbreakable block object state by default
	LDX SprDataOffset_Ctrl                       ; load offset control bit here
	LDY PlayerSize                               ; check player's size
	BNE DBlockSte                                ; if small, branch
	LDA #$12                                     ; otherwise load breakable block object state
DBlockSte:
	STA Block_State,x                            ; store into block object buffer
	JSR DestroyBlockMetatile                     ; store blank metatile in vram buffer to write to name table
	LDX SprDataOffset_Ctrl                       ; load offset control bit
	LDA $02                                      ; get vertical high nybble offset used in block buffer routine
	STA Block_Orig_YPos,x                        ; set as vertical coordinate for block object
	TAY
	LDA $06                                      ; get low byte of block buffer address used in same routine
	STA Block_BBuf_Low,x                         ; save as offset here to be used later
	LDA ($06),y                                  ; get contents of block buffer at old address at $06, $07
	JSR BlockBumpedChk                           ; do a sub to check which block player bumped head on
	STA $00                                      ; store metatile here
	LDY PlayerSize                               ; check player's size
	BNE ChkBrick                                 ; if small, use metatile itself as contents of A
	TYA                                          ; otherwise init A (note: big = 0)
ChkBrick:
	BCC PutMTileB                                ; if no match was found in previous sub, skip ahead
	LDY #$11                                     ; otherwise load unbreakable state into block object buffer
	STY Block_State,x                            ; note this applies to both player sizes
	LDA #$c4                                     ; load empty block metatile into A for now
	LDY $00                                      ; get metatile from before
	CPY #$58                                     ; is it brick with coins (with line)?
	BEQ StartBTmr                                ; if so, branch
	CPY #$5d                                     ; is it brick with coins (without line)?
	BNE PutMTileB                                ; if not, branch ahead to store empty block metatile
StartBTmr:
	LDA BrickCoinTimerFlag                       ; check brick coin timer flag
	BNE ContBTmr                                 ; if set, timer expired or counting down, thus branch
	LDA #$0b
	STA BrickCoinTimer                           ; if not set, set brick coin timer
	INC BrickCoinTimerFlag                       ; and set flag linked to it
ContBTmr:
	LDA BrickCoinTimer                           ; check brick coin timer
	BNE PutOldMT                                 ; if not yet expired, branch to use current metatile
	LDY #$c4                                     ; otherwise use empty block metatile
PutOldMT:
	TYA                                          ; put metatile into A
PutMTileB:
	STA Block_Metatile,x                         ; store whatever metatile be appropriate here
	JSR InitBlock_XY_Pos                         ; get block object horizontal coordinates saved
	LDY $02                                      ; get vertical high nybble offset
	LDA #$23
	STA ($06),y                                  ; write blank metatile $23 to block buffer
	LDA #$10
	STA BlockBounceTimer                         ; set block bounce timer
	PLA                                          ; pull original metatile from stack
	STA $05                                      ; and save here
	LDY #$00                                     ; set default offset
	LDA CrouchingFlag                            ; is player crouching?
	BNE SmallBP                                  ; if so, branch to increment offset
	LDA PlayerSize                               ; is player big?
	BEQ BigBP                                    ; if so, branch to use default offset
SmallBP:
	INY                                          ; increment for small or big and crouching
BigBP:
	LDA Player_Y_Position                        ; get player's vertical coordinate
	CLC
	ADC BlockYPosAdderData,y                     ; add value determined by size
	AND #$f0                                     ; mask out low nybble to get 16-pixel correspondence
	STA Block_Y_Position,x                       ; save as vertical coordinate for block object
	LDY Block_State,x                            ; get block object state
	CPY #$11
	BEQ Unbreak                                  ; if set to value loaded for unbreakable, branch
	JSR BrickShatter                             ; execute code for breakable brick
	JMP InvOBit                                  ; skip subroutine to do last part of code here
Unbreak:
	JSR BumpBlock                                ; execute code for unbreakable brick or question block
InvOBit:
	LDA SprDataOffset_Ctrl                       ; invert control bit used by block objects
	EOR #$01                                     ; and floatey numbers
	STA SprDataOffset_Ctrl
	RTS                                          ; leave!

; --------------------------------

InitBlock_XY_Pos:
	LDA Player_X_Position                        ; get player's horizontal coordinate
	CLC
	ADC #$08                                     ; add eight pixels
	AND #$f0                                     ; mask out low nybble to give 16-pixel correspondence
	STA Block_X_Position,x                       ; save as horizontal coordinate for block object
	LDA Player_PageLoc
	ADC #$00                                     ; add carry to page location of player
	STA Block_PageLoc,x                          ; save as page location of block object
	STA Block_PageLoc2,x                         ; save elsewhere to be used later
	LDA Player_Y_HighPos
	STA Block_Y_HighPos,x                        ; save vertical high byte of player into
	RTS                                          ; vertical high byte of block object and leave

; --------------------------------

BumpBlock:
	JSR CheckTopOfBlock                          ; check to see if there's a coin directly above this block
	LDA #Sfx_Bump
	STA Square1SoundQueue                        ; play bump sound
	LDA #$00
	STA Block_X_Speed,x                          ; initialize horizontal speed for block object
	STA Block_Y_MoveForce,x                      ; init fractional movement force
	STA Player_Y_Speed                           ; init player's vertical speed
	LDA #$fe
	STA Block_Y_Speed,x                          ; set vertical speed for block object
	LDA $05                                      ; get original metatile from stack
	JSR BlockBumpedChk                           ; do a sub to check which block player bumped head on
	BCC ExitBlockChk                             ; if no match was found, branch to leave
	TYA                                          ; move block number to A
	CMP #$09                                     ; if block number was within 0-8 range,
	BCC BlockCode                                ; branch to use current number
	SBC #$05                                     ; otherwise subtract 5 for second set to get proper number
BlockCode:
	JSR JumpEngine                               ; run appropriate subroutine depending on block number

	.dw MushFlowerBlock
	.dw CoinBlock
	.dw CoinBlock
	.dw ExtraLifeMushBlock
	.dw MushFlowerBlock
	.dw VineBlock
	.dw StarBlock
	.dw CoinBlock
	.dw ExtraLifeMushBlock

; --------------------------------

MushFlowerBlock:
	LDA #$00                                     ; load mushroom/fire flower into power-up type
	.db $2c                                      ; BIT instruction opcode

StarBlock:
	LDA #$02                                     ; load star into power-up type
	.db $2c                                      ; BIT instruction opcode

ExtraLifeMushBlock:
	LDA #$03                                     ; load 1-up mushroom into power-up type
	STA $39                                      ; store correct power-up type
	JMP SetupPowerUp

VineBlock:
	LDX #$05                                     ; load last slot for enemy object buffer
	LDY SprDataOffset_Ctrl                       ; get control bit
	JSR Setup_Vine                               ; set up vine object

ExitBlockChk:
	RTS                                          ; leave

; --------------------------------

BrickQBlockMetatiles:
	.db $c1, $c0, $5f, $60                       ; used by question blocks

; these two sets are functionally identical, but look different
	.db $55, $56, $57, $58, $59                  ; used by ground level types
	.db $5a, $5b, $5c, $5d, $5e                  ; used by other level types

BlockBumpedChk:
	LDY #$0d                                     ; start at end of metatile data
BumpChkLoop:
	CMP BrickQBlockMetatiles,y                   ; check to see if current metatile matches
	BEQ MatchBump                                ; metatile found in block buffer, branch if so
	DEY                                          ; otherwise move onto next metatile
	BPL BumpChkLoop                              ; do this until all metatiles are checked
	CLC                                          ; if none match, return with carry clear
MatchBump:
	RTS                                          ; note carry is set if found match

; --------------------------------

BrickShatter:
	JSR CheckTopOfBlock                          ; check to see if there's a coin directly above this block
	LDA #Sfx_BrickShatter
	STA Block_RepFlag,x                          ; set flag for block object to immediately replace metatile
	STA NoiseSoundQueue                          ; load brick shatter sound
	JSR SpawnBrickChunks                         ; create brick chunk objects
	LDA #$fe
	STA Player_Y_Speed                           ; set vertical speed for player
	LDA #$05
	STA DigitModifier+5                          ; set digit modifier to give player 50 points
	JSR AddToScore                               ; do sub to update the score
	LDX SprDataOffset_Ctrl                       ; load control bit and leave
	RTS

; --------------------------------

CheckTopOfBlock:
	LDX SprDataOffset_Ctrl                       ; load control bit
	LDY $02                                      ; get vertical high nybble offset used in block buffer
	BEQ TopEx                                    ; branch to leave if set to zero, because we're at the top
	TYA                                          ; otherwise set to A
	SEC
	SBC #$10                                     ; subtract $10 to move up one row in the block buffer
	STA $02                                      ; store as new vertical high nybble offset
	    tay
	LDA ($06),y                                  ; get contents of block buffer in same column, one row up
	CMP #$c2                                     ; is it a coin? (not underwater)
	BNE TopEx                                    ; if not, branch to leave
	LDA #$00
	STA ($06),y                                  ; otherwise put blank metatile where coin was
	JSR RemoveCoin_Axe                           ; write blank metatile to vram buffer
	LDX SprDataOffset_Ctrl                       ; get control bit
	JSR SetupJumpCoin                            ; create jumping coin object and update coin variables
TopEx:
	RTS                                          ; leave!

; --------------------------------

SpawnBrickChunks:
	LDA Block_X_Position,x                       ; set horizontal coordinate of block object
	STA Block_Orig_XPos,x                        ; as original horizontal coordinate here
	LDA #$f0
	STA Block_X_Speed,x                          ; set horizontal speed for brick chunk objects
	STA Block_X_Speed+2,x
	LDA #$fa
	STA Block_Y_Speed,x                          ; set vertical speed for one
	LDA #$fc
	STA Block_Y_Speed+2,x                        ; set lower vertical speed for the other
	LDA #$00
	STA Block_Y_MoveForce,x                      ; init fractional movement force for both
	STA Block_Y_MoveForce+2,x
	LDA Block_PageLoc,x
	STA Block_PageLoc+2,x                        ; copy page location
	LDA Block_X_Position,x
	STA Block_X_Position+2,x                     ; copy horizontal coordinate
	LDA Block_Y_Position,x
	CLC                                          ; add 8 pixels to vertical coordinate
	ADC #$08                                     ; and save as vertical coordinate for one of them
	STA Block_Y_Position+2,x
	LDA #$fa
	STA Block_Y_Speed,x                          ; set vertical speed...again??? (redundant)
	RTS

; -------------------------------------------------------------------------------------

BlockObjectsCore:
	LDA Block_State,x                            ; get state of block object
	BEQ UpdSte                                   ; if not set, branch to leave
	AND #$0f                                     ; mask out high nybble
	PHA                                          ; push to stack
	TAY                                          ; put in Y for now
	TXA
	CLC
	ADC #$09                                     ; add 9 bytes to offset (note two block objects are created
	TAX                                          ; when using brick chunks, but only one offset for both)
	DEY                                          ; decrement Y to check for solid block state
	BEQ BouncingBlockHandler                     ; branch if found, otherwise continue for brick chunks
	JSR ImposeGravityBlock                       ; do sub to impose gravity on one block object object
	JSR MoveObjectHorizontally                   ; do another sub to move horizontally
	TXA
	CLC                                          ; move onto next block object
	ADC #$02
	TAX
	JSR ImposeGravityBlock                       ; do sub to impose gravity on other block object
	JSR MoveObjectHorizontally                   ; do another sub to move horizontally
	LDX ObjectOffset                             ; get block object offset used for both
	JSR RelativeBlockPosition                    ; get relative coordinates
	JSR GetBlockOffscreenBits                    ; get offscreen information
	JSR DrawBrickChunks                          ; draw the brick chunks
	PLA                                          ; get lower nybble of saved state
	LDY Block_Y_HighPos,x                        ; check vertical high byte of block object
	BEQ UpdSte                                   ; if above the screen, branch to kill it
	PHA                                          ; otherwise save state back into stack
	LDA #$f0
	CMP Block_Y_Position+2,x                     ; check to see if bottom block object went
	BCS ChkTop                                   ; to the bottom of the screen, and branch if not
	STA Block_Y_Position+2,x                     ; otherwise set offscreen coordinate
ChkTop:
	LDA Block_Y_Position,x                       ; get top block object's vertical coordinate
	CMP #$f0                                     ; see if it went to the bottom of the screen
	PLA                                          ; pull block object state from stack
	BCC UpdSte                                   ; if not, branch to save state
	BCS KillBlock                                ; otherwise do unconditional branch to kill it

BouncingBlockHandler:
	JSR ImposeGravityBlock                       ; do sub to impose gravity on block object
	LDX ObjectOffset                             ; get block object offset
	JSR RelativeBlockPosition                    ; get relative coordinates
	JSR GetBlockOffscreenBits                    ; get offscreen information
	JSR DrawBlock                                ; draw the block
	LDA Block_Y_Position,x                       ; get vertical coordinate
	AND #$0f                                     ; mask out high nybble
	CMP #$05                                     ; check to see if low nybble wrapped around
	PLA                                          ; pull state from stack
	BCS UpdSte                                   ; if still above amount, not time to kill block yet, thus branch
	LDA #$01
	STA Block_RepFlag,x                          ; otherwise set flag to replace metatile
KillBlock:
	LDA #$00                                     ; if branched here, nullify object state
UpdSte:
	STA Block_State,x                            ; store contents of A in block object state
	RTS

; -------------------------------------------------------------------------------------
; $02 - used to store offset to block buffer
; $06-$07 - used to store block buffer address

BlockObjMT_Updater:
	LDX #$01                                     ; set offset to start with second block object
UpdateLoop:
	STX ObjectOffset                             ; set offset here
	LDA VRAM_Buffer1                             ; if vram buffer already being used here,
	BNE NextBUpd                                 ; branch to move onto next block object
	LDA Block_RepFlag,x                          ; if flag for block object already clear,
	BEQ NextBUpd                                 ; branch to move onto next block object
	LDA Block_BBuf_Low,x                         ; get low byte of block buffer
	STA $06                                      ; store into block buffer address
	LDA #$05
	STA $07                                      ; set high byte of block buffer address
	LDA Block_Orig_YPos,x                        ; get original vertical coordinate of block object
	STA $02                                      ; store here and use as offset to block buffer
	TAY
	LDA Block_Metatile,x                         ; get metatile to be written
	STA ($06),y                                  ; write it to the block buffer
	JSR ReplaceBlockMetatile                     ; do sub to replace metatile where block object is
	LDA #$00
	STA Block_RepFlag,x                          ; clear block object flag
NextBUpd:
	DEX                                          ; decrement block object offset
	BPL UpdateLoop                               ; do this until both block objects are dealt with
	RTS                                          ; then leave

; -------------------------------------------------------------------------------------
; $00 - used to store high nybble of horizontal speed as adder
; $01 - used to store low nybble of horizontal speed
; $02 - used to store adder to page location

MoveEnemyHorizontally:
	INX                                          ; increment offset for enemy offset
	JSR MoveObjectHorizontally                   ; position object horizontally according to
	LDX ObjectOffset                             ; counters, return with saved value in A,
	RTS                                          ; put enemy offset back in X and leave

MovePlayerHorizontally:
	LDA JumpspringAnimCtrl                       ; if jumpspring currently animating,
	BNE ExXMove                                  ; branch to leave
	TAX                                          ; otherwise set zero for offset to use player's stuff

MoveObjectHorizontally:
	LDA SprObject_X_Speed,x                      ; get currently saved value (horizontal
	ASL                                          ; speed, secondary counter, whatever)
	ASL                                          ; and move low nybble to high
	ASL
	ASL
	STA $01                                      ; store result here
	LDA SprObject_X_Speed,x                      ; get saved value again
	LSR                                          ; move high nybble to low
	LSR
	LSR
	LSR
	CMP #$08                                     ; if < 8, branch, do not change
	BCC SaveXSpd
	ORA #%11110000                               ; otherwise alter high nybble
SaveXSpd:
	STA $00                                      ; save result here
	LDY #$00                                     ; load default Y value here
	CMP #$00                                     ; if result positive, leave Y alone
	BPL UseAdder
	DEY                                          ; otherwise decrement Y
UseAdder:
	STY $02                                      ; save Y here
	LDA SprObject_X_MoveForce,x                  ; get whatever number's here
	CLC
	ADC $01                                      ; add low nybble moved to high
	STA SprObject_X_MoveForce,x                  ; store result here
	LDA #$00                                     ; init A
	ROL                                          ; rotate carry into d0
	PHA                                          ; push onto stack
	ROR                                          ; rotate d0 back onto carry
	LDA SprObject_X_Position,x
	ADC $00                                      ; add carry plus saved value (high nybble moved to low
	STA SprObject_X_Position,x                   ; plus $f0 if necessary) to object's horizontal position
	LDA SprObject_PageLoc,x
	ADC $02                                      ; add carry plus other saved value to the
	STA SprObject_PageLoc,x                      ; object's page location and save
	PLA
	CLC                                          ; pull old carry from stack and add
	ADC $00                                      ; to high nybble moved to low
ExXMove:
	RTS                                          ; and leave

; -------------------------------------------------------------------------------------
; $00 - used for downward force
; $01 - used for upward force
; $02 - used for maximum vertical speed

MovePlayerVertically:
	LDX #$00                                     ; set X for player offset
	LDA TimerControl
	BNE NoJSChk                                  ; if master timer control set, branch ahead
	LDA JumpspringAnimCtrl                       ; otherwise check to see if jumpspring is animating
	BNE ExXMove                                  ; branch to leave if so
NoJSChk:
	LDA VerticalForce                            ; dump vertical force
	STA $00
	LDA #$04                                     ; set maximum vertical speed here
	JMP ImposeGravitySprObj                      ; then jump to move player vertically

; --------------------------------

MoveD_EnemyVertically:
	LDY #$3d                                     ; set quick movement amount downwards
	LDA Enemy_State,x                            ; then check enemy state
	CMP #$05                                     ; if not set to unique state for spiny's egg, go ahead
	BNE ContVMove                                ; and use, otherwise set different movement amount, continue on

MoveFallingPlatform:
	LDY #$20                                     ; set movement amount
ContVMove:
	JMP SetHiMax                                 ; jump to skip the rest of this

; --------------------------------

MoveRedPTroopaDown:
	LDY #$00                                     ; set Y to move downwards
	JMP MoveRedPTroopa                           ; skip to movement routine

MoveRedPTroopaUp:
	LDY #$01                                     ; set Y to move upwards

MoveRedPTroopa:
	INX                                          ; increment X for enemy offset
	LDA #$03
	STA $00                                      ; set downward movement amount here
	LDA #$06
	STA $01                                      ; set upward movement amount here
	LDA #$02
	STA $02                                      ; set maximum speed here
	TYA                                          ; set movement direction in A, and
	JMP RedPTroopaGrav                           ; jump to move this thing

; --------------------------------

MoveDropPlatform:
	LDY #$7f                                     ; set movement amount for drop platform
	BNE SetMdMax                                 ; skip ahead of other value set here

MoveEnemySlowVert:
	LDY #$0f                                     ; set movement amount for bowser/other objects
SetMdMax:
	LDA #$02                                     ; set maximum speed in A
	BNE SetXMoveAmt                              ; unconditional branch

; --------------------------------

MoveJ_EnemyVertically:
	LDY #$1c                                     ; set movement amount for podoboo/other objects
SetHiMax:
	LDA #$03                                     ; set maximum speed in A
SetXMoveAmt:
	STY $00                                      ; set movement amount here
	INX                                          ; increment X for enemy offset
	JSR ImposeGravitySprObj                      ; do a sub to move enemy object downwards
	LDX ObjectOffset                             ; get enemy object buffer offset and leave
	RTS

; --------------------------------

MaxSpdBlockData:
	.db $06, $08

ResidualGravityCode:
	LDY #$00                                     ; this part appears to be residual,
	.db $2c                                      ; no code branches or jumps to it...

ImposeGravityBlock:
	LDY #$01                                     ; set offset for maximum speed
	LDA #$50                                     ; set movement amount here
	STA $00
	LDA MaxSpdBlockData,y                        ; get maximum speed

ImposeGravitySprObj:
	STA $02                                      ; set maximum speed here
	LDA #$00                                     ; set value to move downwards
	JMP ImposeGravity                            ; jump to the code that actually moves it

; --------------------------------

MovePlatformDown:
	LDA #$00                                     ; save value to stack (if branching here, execute next
	.db $2c                                      ; part as BIT instruction)

MovePlatformUp:
	LDA #$01                                     ; save value to stack
	PHA
	LDY Enemy_ID,x                               ; get enemy object identifier
	INX                                          ; increment offset for enemy object
	LDA #$05                                     ; load default value here
	CPY #$29                                     ; residual comparison, object #29 never executes
	BNE SetDplSpd                                ; this code, thus unconditional branch here
	LDA #$09                                     ; residual code
SetDplSpd:
	STA $00                                      ; save downward movement amount here
	LDA #$0a                                     ; save upward movement amount here
	STA $01
	LDA #$03                                     ; save maximum vertical speed here
	STA $02
	PLA                                          ; get value from stack
	TAY                                          ; use as Y, then move onto code shared by red koopa

RedPTroopaGrav:
	JSR ImposeGravity                            ; do a sub to move object gradually
	LDX ObjectOffset                             ; get enemy object offset and leave
	RTS

; -------------------------------------------------------------------------------------
; $00 - used for downward force
; $01 - used for upward force
; $07 - used as adder for vertical position

ImposeGravity:
	PHA                                          ; push value to stack
	LDA SprObject_YMF_Dummy,x
	CLC                                          ; add value in movement force to contents of dummy variable
	ADC SprObject_Y_MoveForce,x
	STA SprObject_YMF_Dummy,x
	LDY #$00                                     ; set Y to zero by default
	LDA SprObject_Y_Speed,x                      ; get current vertical speed
	BPL AlterYP                                  ; if currently moving downwards, do not decrement Y
	DEY                                          ; otherwise decrement Y
AlterYP:
	STY $07                                      ; store Y here
	ADC SprObject_Y_Position,x                   ; add vertical position to vertical speed plus carry
	STA SprObject_Y_Position,x                   ; store as new vertical position
	LDA SprObject_Y_HighPos,x
	ADC $07                                      ; add carry plus contents of $07 to vertical high byte
	STA SprObject_Y_HighPos,x                    ; store as new vertical high byte
	LDA SprObject_Y_MoveForce,x
	CLC
	ADC $00                                      ; add downward movement amount to contents of $0433
	STA SprObject_Y_MoveForce,x
	LDA SprObject_Y_Speed,x                      ; add carry to vertical speed and store
	ADC #$00
	STA SprObject_Y_Speed,x
	CMP $02                                      ; compare to maximum speed
	BMI ChkUpM                                   ; if less than preset value, skip this part
	LDA SprObject_Y_MoveForce,x
	CMP #$80                                     ; if less positively than preset maximum, skip this part
	BCC ChkUpM
	LDA $02
	STA SprObject_Y_Speed,x                      ; keep vertical speed within maximum value
	LDA #$00
	STA SprObject_Y_MoveForce,x                  ; clear fractional
ChkUpM:
	PLA                                          ; get value from stack
	BEQ ExVMove                                  ; if set to zero, branch to leave
	LDA $02
	EOR #%11111111                               ; otherwise get two's compliment of maximum speed
	TAY
	INY
	STY $07                                      ; store two's compliment here
	LDA SprObject_Y_MoveForce,x
	SEC                                          ; subtract upward movement amount from contents
	SBC $01                                      ; of movement force, note that $01 is twice as large as $00,
	STA SprObject_Y_MoveForce,x                  ; thus it effectively undoes add we did earlier
	LDA SprObject_Y_Speed,x
	SBC #$00                                     ; subtract borrow from vertical speed and store
	STA SprObject_Y_Speed,x
	CMP $07                                      ; compare vertical speed to two's compliment
	BPL ExVMove                                  ; if less negatively than preset maximum, skip this part
	LDA SprObject_Y_MoveForce,x
	CMP #$80                                     ; check if fractional part is above certain amount,
	BCS ExVMove                                  ; and if so, branch to leave
	LDA $07
	STA SprObject_Y_Speed,x                      ; keep vertical speed within maximum value
	LDA #$ff
	STA SprObject_Y_MoveForce,x                  ; clear fractional
ExVMove:
	RTS                                          ; leave!

; -------------------------------------------------------------------------------------

EnemiesAndLoopsCore:
	LDA Enemy_Flag,x                             ; check data here for MSB set
	PHA                                          ; save in stack
	ASL
	BCS ChkBowserF                               ; if MSB set in enemy flag, branch ahead of jumps
	PLA                                          ; get from stack
	BEQ ChkAreaTsk                               ; if data zero, branch
	JMP RunEnemyObjectsCore                      ; otherwise, jump to run enemy subroutines
ChkAreaTsk:
	LDA AreaParserTaskNum                        ; check number of tasks to perform
	AND #$07
	CMP #$07                                     ; if at a specific task, jump and leave
	BEQ ExitELCore
	JMP ProcLoopCommand                          ; otherwise, jump to process loop command/load enemies
ChkBowserF:
	PLA                                          ; get data from stack
	AND #%00001111                               ; mask out high nybble
	TAY
	LDA Enemy_Flag,y                             ; use as pointer and load same place with different offset
	BNE ExitELCore
	STA Enemy_Flag,x                             ; if second enemy flag not set, also clear first one
ExitELCore:
	RTS

; --------------------------------

; loop command data
LoopCmdWorldNumber:
	.db $03, $03, $06, $06, $06, $06, $06, $06, $07, $07, $07

LoopCmdPageNumber:
	.db $05, $09, $04, $05, $06, $08, $09, $0a, $06, $0b, $10

LoopCmdYPosition:
	.db $40, $b0, $b0, $80, $40, $40, $80, $40, $f0, $f0, $f0

ExecGameLoopback:
	LDA Player_PageLoc                           ; send player back four pages
	SEC
	SBC #$04
	STA Player_PageLoc
	LDA CurrentPageLoc                           ; send current page back four pages
	SEC
	SBC #$04
	STA CurrentPageLoc
	LDA ScreenLeft_PageLoc                       ; subtract four from page location
	SEC                                          ; of screen's left border
	SBC #$04
	STA ScreenLeft_PageLoc
	LDA ScreenRight_PageLoc                      ; do the same for the page location
	SEC                                          ; of screen's right border
	SBC #$04
	STA ScreenRight_PageLoc
	LDA AreaObjectPageLoc                        ; subtract four from page control
	SEC                                          ; for area objects
	SBC #$04
	STA AreaObjectPageLoc
	LDA #$00                                     ; initialize page select for both
	STA EnemyObjectPageSel                       ; area and enemy objects
	STA AreaObjectPageSel
	STA EnemyDataOffset                          ; initialize enemy object data offset
	STA EnemyObjectPageLoc                       ; and enemy object page control
	LDA AreaDataOfsLoopback,y                    ; adjust area object offset based on
	STA AreaDataOffset                           ; which loop command we encountered
	RTS

ProcLoopCommand:
	LDA LoopCommand                              ; check if loop command was found
	BEQ ChkEnemyFrenzy
	LDA CurrentColumnPos                         ; check to see if we're still on the first page
	BNE ChkEnemyFrenzy                           ; if not, do not loop yet
	LDY #$0b                                     ; start at the end of each set of loop data
FindLoop:
	DEY
	BMI ChkEnemyFrenzy                           ; if all data is checked and not match, do not loop
	LDA WorldNumber                              ; check to see if one of the world numbers
	CMP LoopCmdWorldNumber,y                     ; matches our current world number
	BNE FindLoop
	LDA CurrentPageLoc                           ; check to see if one of the page numbers
	CMP LoopCmdPageNumber,y                      ; matches the page we're currently on
	BNE FindLoop
	LDA Player_Y_Position                        ; check to see if the player is at the correct position
	CMP LoopCmdYPosition,y                       ; if not, branch to check for world 7
	BNE WrongChk
	LDA Player_State                             ; check to see if the player is
	CMP #$00                                     ; on solid ground (i.e. not jumping or falling)
	BNE WrongChk                                 ; if not, player fails to pass loop, and loopback
	LDA WorldNumber                              ; are we in world 7? (check performed on correct
	CMP #World7                                  ; vertical position and on solid ground)
	BNE InitMLp                                  ; if not, initialize flags used there, otherwise
	INC MultiLoopCorrectCntr                     ; increment counter for correct progression
IncMLoop:
	INC MultiLoopPassCntr                        ; increment master multi-part counter
	LDA MultiLoopPassCntr                        ; have we done all three parts?
	CMP #$03
	BNE InitLCmd                                 ; if not, skip this part
	LDA MultiLoopCorrectCntr                     ; if so, have we done them all correctly?
	CMP #$03
	BEQ InitMLp                                  ; if so, branch past unnecessary check here
	BNE DoLpBack                                 ; unconditional branch if previous branch fails
WrongChk:
	LDA WorldNumber                              ; are we in world 7? (check performed on
	CMP #World7                                  ; incorrect vertical position or not on solid ground)
	BEQ IncMLoop
DoLpBack:
	JSR ExecGameLoopback                         ; if player is not in right place, loop back
	JSR KillAllEnemies
InitMLp:
	LDA #$00                                     ; initialize counters used for multi-part loop commands
	STA MultiLoopPassCntr
	STA MultiLoopCorrectCntr
InitLCmd:
	LDA #$00                                     ; initialize loop command flag
	STA LoopCommand

; --------------------------------

ChkEnemyFrenzy:
	LDA EnemyFrenzyQueue                         ; check for enemy object in frenzy queue
	BEQ ProcessEnemyData                         ; if not, skip this part
	STA Enemy_ID,x                               ; store as enemy object identifier here
	LDA #$01
	STA Enemy_Flag,x                             ; activate enemy object flag
	LDA #$00
	STA Enemy_State,x                            ; initialize state and frenzy queue
	STA EnemyFrenzyQueue
	JMP InitEnemyObject                          ; and then jump to deal with this enemy

; --------------------------------
; $06 - used to hold page location of extended right boundary
; $07 - used to hold high nybble of position of extended right boundary

ProcessEnemyData:
	LDY EnemyDataOffset                          ; get offset of enemy object data
	LDA (EnemyData),y                            ; load first byte
	CMP #$ff                                     ; check for EOD terminator
	BNE CheckEndofBuffer
	JMP CheckFrenzyBuffer                        ; if found, jump to check frenzy buffer, otherwise

CheckEndofBuffer:
	AND #%00001111                               ; check for special row $0e
	CMP #$0e
	BEQ CheckRightBounds                         ; if found, branch, otherwise
	CPX #$05                                     ; check for end of buffer
	BCC CheckRightBounds                         ; if not at end of buffer, branch
	INY
	LDA (EnemyData),y                            ; check for specific value here
	AND #%00111111                               ; not sure what this was intended for, exactly
	CMP #$2e                                     ; this part is quite possibly residual code
	BEQ CheckRightBounds                         ; but it has the effect of keeping enemies out of
	RTS                                          ; the sixth slot

CheckRightBounds:
	LDA ScreenRight_X_Pos                        ; add 48 to pixel coordinate of right boundary
	CLC
	ADC #$30
	AND #%11110000                               ; store high nybble
	STA $07
	LDA ScreenRight_PageLoc                      ; add carry to page location of right boundary
	ADC #$00
	STA $06                                      ; store page location + carry
	LDY EnemyDataOffset
	INY
	LDA (EnemyData),y                            ; if MSB of enemy object is clear, branch to check for row $0f
	ASL
	BCC CheckPageCtrlRow
	LDA EnemyObjectPageSel                       ; if page select already set, do not set again
	BNE CheckPageCtrlRow
	INC EnemyObjectPageSel                       ; otherwise, if MSB is set, set page select
	INC EnemyObjectPageLoc                       ; and increment page control

CheckPageCtrlRow:
	DEY
	LDA (EnemyData),y                            ; reread first byte
	AND #$0f
	CMP #$0f                                     ; check for special row $0f
	BNE PositionEnemyObj                         ; if not found, branch to position enemy object
	LDA EnemyObjectPageSel                       ; if page select set,
	BNE PositionEnemyObj                         ; branch without reading second byte
	INY
	LDA (EnemyData),y                            ; otherwise, get second byte, mask out 2 MSB
	AND #%00111111
	STA EnemyObjectPageLoc                       ; store as page control for enemy object data
	INC EnemyDataOffset                          ; increment enemy object data offset 2 bytes
	INC EnemyDataOffset
	INC EnemyObjectPageSel                       ; set page select for enemy object data and
	JMP ProcLoopCommand                          ; jump back to process loop commands again

PositionEnemyObj:
	LDA EnemyObjectPageLoc                       ; store page control as page location
	STA Enemy_PageLoc,x                          ; for enemy object
	LDA (EnemyData),y                            ; get first byte of enemy object
	AND #%11110000
	STA Enemy_X_Position,x                       ; store column position
	CMP ScreenRight_X_Pos                        ; check column position against right boundary
	LDA Enemy_PageLoc,x                          ; without subtracting, then subtract borrow
	SBC ScreenRight_PageLoc                      ; from page location
	BCS CheckRightExtBounds                      ; if enemy object beyond or at boundary, branch
	LDA (EnemyData),y
	AND #%00001111                               ; check for special row $0e
	CMP #$0e                                     ; if found, jump elsewhere
	BEQ ParseRow0e
	JMP CheckThreeBytes                          ; if not found, unconditional jump

CheckRightExtBounds:
	LDA $07                                      ; check right boundary + 48 against
	CMP Enemy_X_Position,x                       ; column position without subtracting,
	LDA $06                                      ; then subtract borrow from page control temp
	SBC Enemy_PageLoc,x                          ; plus carry
	BCC CheckFrenzyBuffer                        ; if enemy object beyond extended boundary, branch
	LDA #$01                                     ; store value in vertical high byte
	STA Enemy_Y_HighPos,x
	LDA (EnemyData),y                            ; get first byte again
	ASL                                          ; multiply by four to get the vertical
	ASL                                          ; coordinate
	ASL
	ASL
	STA Enemy_Y_Position,x
	CMP #$e0                                     ; do one last check for special row $0e
	BEQ ParseRow0e                               ; (necessary if branched to $c1cb)
	INY
	LDA (EnemyData),y                            ; get second byte of object
	AND #%01000000                               ; check to see if hard mode bit is set
	BEQ CheckForEnemyGroup                       ; if not, branch to check for group enemy objects
	LDA SecondaryHardMode                        ; if set, check to see if secondary hard mode flag
	BEQ Inc2B                                    ; is on, and if not, branch to skip this object completely

CheckForEnemyGroup:
	LDA (EnemyData),y                            ; get second byte and mask out 2 MSB
	AND #%00111111
	CMP #$37                                     ; check for value below $37
	BCC BuzzyBeetleMutate
	CMP #$3f                                     ; if $37 or greater, check for value
	BCC DoGroup                                  ; below $3f, branch if below $3f

BuzzyBeetleMutate:
	CMP #Goomba                                  ; if below $37, check for goomba
	BNE StrID                                    ; value ($3f or more always fails)
	LDY PrimaryHardMode                          ; check if primary hard mode flag is set
	BEQ StrID                                    ; and if so, change goomba to buzzy beetle
	LDA #BuzzyBeetle
StrID:
	STA Enemy_ID,x                               ; store enemy object number into buffer
	LDA #$01
	STA Enemy_Flag,x                             ; set flag for enemy in buffer
	JSR InitEnemyObject
	LDA Enemy_Flag,x                             ; check to see if flag is set
	BNE Inc2B                                    ; if not, leave, otherwise branch
	RTS

CheckFrenzyBuffer:
	LDA EnemyFrenzyBuffer                        ; if enemy object stored in frenzy buffer
	BNE StrFre                                   ; then branch ahead to store in enemy object buffer
	LDA VineFlagOffset                           ; otherwise check vine flag offset
	CMP #$01
	BNE ExEPar                                   ; if other value <> 1, leave
	LDA #VineObject                              ; otherwise put vine in enemy identifier
StrFre:
	STA Enemy_ID,x                               ; store contents of frenzy buffer into enemy identifier value

InitEnemyObject:
	LDA #$00                                     ; initialize enemy state
	STA Enemy_State,x
	JSR CheckpointEnemyID                        ; jump ahead to run jump engine and subroutines
ExEPar:
	RTS                                          ; then leave

DoGroup:
	JMP HandleGroupEnemies                       ; handle enemy group objects

ParseRow0e:
	INY                                          ; increment Y to load third byte of object
	INY
	LDA (EnemyData),y
	LSR                                          ; move 3 MSB to the bottom, effectively
	LSR                                          ; making %xxx00000 into %00000xxx
	LSR
	LSR
	LSR
	CMP WorldNumber                              ; is it the same world number as we're on?
	BNE NotUse                                   ; if not, do not use (this allows multiple uses
	DEY                                          ; of the same area, like the underground bonus areas)
	LDA (EnemyData),y                            ; otherwise, get second byte and use as offset
	STA AreaPointer                              ; to addresses for level and enemy object data
	INY
	LDA (EnemyData),y                            ; get third byte again, and this time mask out
	AND #%00011111                               ; the 3 MSB from before, save as page number to be
	STA EntrancePage                             ; used upon entry to area, if area is entered
NotUse:
	JMP Inc3B

CheckThreeBytes:
	LDY EnemyDataOffset                          ; load current offset for enemy object data
	LDA (EnemyData),y                            ; get first byte
	AND #%00001111                               ; check for special row $0e
	CMP #$0e
	BNE Inc2B
Inc3B:
	INC EnemyDataOffset                          ; if row = $0e, increment three bytes
Inc2B:
	INC EnemyDataOffset                          ; otherwise increment two bytes
	INC EnemyDataOffset
	LDA #$00                                     ; init page select for enemy objects
	STA EnemyObjectPageSel
	LDX ObjectOffset                             ; reload current offset in enemy buffers
	RTS                                          ; and leave

CheckpointEnemyID:
	LDA Enemy_ID,x
	CMP #$15                                     ; check enemy object identifier for $15 or greater
	BCS InitEnemyRoutines                        ; and branch straight to the jump engine if found
	TAY                                          ; save identifier in Y register for now
	LDA Enemy_Y_Position,x
	ADC #$08                                     ; add eight pixels to what will eventually be the
	STA Enemy_Y_Position,x                       ; enemy object's vertical coordinate ($00-$14 only)
	LDA #$01
	STA EnemyOffscrBitsMasked,x                  ; set offscreen masked bit
	TYA                                          ; get identifier back and use as offset for jump engine

InitEnemyRoutines:
	JSR JumpEngine

; jump engine table for newly loaded enemy objects

	.dw InitNormalEnemy                          ; for objects $00-$0f
	.dw InitNormalEnemy
	.dw InitNormalEnemy
	.dw InitRedKoopa
	.dw NoInitCode
	.dw InitHammerBro
	.dw InitGoomba
	.dw InitBloober
	.dw InitBulletBill
	.dw NoInitCode
	.dw InitCheepCheep
	.dw InitCheepCheep
	.dw InitPodoboo
	.dw InitPiranhaPlant
	.dw InitJumpGPTroopa
	.dw InitRedPTroopa

	.dw InitHorizFlySwimEnemy                    ; for objects $10-$1f
	.dw InitLakitu
	.dw InitEnemyFrenzy
	.dw NoInitCode
	.dw InitEnemyFrenzy
	.dw InitEnemyFrenzy
	.dw InitEnemyFrenzy
	.dw InitEnemyFrenzy
	.dw EndFrenzy
	.dw NoInitCode
	.dw NoInitCode
	.dw InitShortFirebar
	.dw InitShortFirebar
	.dw InitShortFirebar
	.dw InitShortFirebar
	.dw InitLongFirebar

	.dw NoInitCode                               ; for objects $20-$2f
	.dw NoInitCode
	.dw NoInitCode
	.dw NoInitCode
	.dw InitBalPlatform
	.dw InitVertPlatform
	.dw LargeLiftUp
	.dw LargeLiftDown
	.dw InitHoriPlatform
	.dw InitDropPlatform
	.dw InitHoriPlatform
	.dw PlatLiftUp
	.dw PlatLiftDown
	.dw InitBowser
	.dw PwrUpJmp                                 ; possibly dummy value
	.dw Setup_Vine

	.dw NoInitCode                               ; for objects $30-$36
	.dw NoInitCode
	.dw NoInitCode
	.dw NoInitCode
	.dw NoInitCode
	.dw InitRetainerObj
	.dw EndOfEnemyInitCode

; -------------------------------------------------------------------------------------

NoInitCode:
	RTS                                          ; this executed when enemy object has no init code

; --------------------------------

InitGoomba:
	JSR InitNormalEnemy                          ; set appropriate horizontal speed
	JMP SmallBBox                                ; set $09 as bounding box control, set other values

; --------------------------------

InitPodoboo:
	LDA #$02                                     ; set enemy position to below
	STA Enemy_Y_HighPos,x                        ; the bottom of the screen
	STA Enemy_Y_Position,x
	LSR
	STA EnemyIntervalTimer,x                     ; set timer for enemy
	LSR
	STA Enemy_State,x                            ; initialize enemy state, then jump to use
	JMP SmallBBox                                ; $09 as bounding box size and set other things

; --------------------------------

InitRetainerObj:
	LDA #$b8                                     ; set fixed vertical position for
	STA Enemy_Y_Position,x                       ; princess/mushroom retainer object
	RTS

; --------------------------------

NormalXSpdData:
	.db $f8, $f4

InitNormalEnemy:
	LDY #$01                                     ; load offset of 1 by default
	LDA PrimaryHardMode                          ; check for primary hard mode flag set
	BNE GetESpd
	DEY                                          ; if not set, decrement offset
GetESpd:
	LDA NormalXSpdData,y                         ; get appropriate horizontal speed
SetESpd:
	STA Enemy_X_Speed,x                          ; store as speed for enemy object
	JMP TallBBox                                 ; branch to set bounding box control and other data

; --------------------------------

InitRedKoopa:
	JSR InitNormalEnemy                          ; load appropriate horizontal speed
	LDA #$01                                     ; set enemy state for red koopa troopa $03
	STA Enemy_State,x
	RTS

; --------------------------------

HBroWalkingTimerData:
	.db $80, $50

InitHammerBro:
	LDA #$00                                     ; init horizontal speed and timer used by hammer bro
	STA HammerThrowingTimer,x                    ; apparently to time hammer throwing
	STA Enemy_X_Speed,x
	LDY SecondaryHardMode                        ; get secondary hard mode flag
	LDA HBroWalkingTimerData,y
	STA EnemyIntervalTimer,x                     ; set value as delay for hammer bro to walk left
	LDA #$0b                                     ; set specific value for bounding box size control
	JMP SetBBox

; --------------------------------

InitHorizFlySwimEnemy:
	LDA #$00                                     ; initialize horizontal speed
	JMP SetESpd

; --------------------------------

InitBloober:
	LDA #$00                                     ; initialize horizontal speed
	STA BlooperMoveSpeed,x
SmallBBox:
	LDA #$09                                     ; set specific bounding box size control
	BNE SetBBox                                  ; unconditional branch

; --------------------------------

InitRedPTroopa:
	LDY #$30                                     ; load central position adder for 48 pixels down
	LDA Enemy_Y_Position,x                       ; set vertical coordinate into location to
	STA RedPTroopaOrigXPos,x                     ; be used as original vertical coordinate
	BPL GetCent                                  ; if vertical coordinate < $80
	LDY #$e0                                     ; if => $80, load position adder for 32 pixels up
GetCent:
	TYA                                          ; send central position adder to A
	ADC Enemy_Y_Position,x                       ; add to current vertical coordinate
	STA RedPTroopaCenterYPos,x                   ; store as central vertical coordinate
TallBBox:
	LDA #$03                                     ; set specific bounding box size control
SetBBox:
	STA Enemy_BoundBoxCtrl,x                     ; set bounding box control here
	LDA #$02                                     ; set moving direction for left
	STA Enemy_MovingDir,x
InitVStf:
	LDA #$00                                     ; initialize vertical speed
	STA Enemy_Y_Speed,x                          ; and movement force
	STA Enemy_Y_MoveForce,x
	RTS

; --------------------------------

InitBulletBill:
	LDA #$02                                     ; set moving direction for left
	STA Enemy_MovingDir,x
	LDA #$09                                     ; set bounding box control for $09
	STA Enemy_BoundBoxCtrl,x
	RTS

; --------------------------------

InitCheepCheep:
	JSR SmallBBox                                ; set vertical bounding box, speed, init others
	LDA PseudoRandomBitReg,x                     ; check one portion of LSFR
	AND #%00010000                               ; get d4 from it
	STA CheepCheepMoveMFlag,x                    ; save as movement flag of some sort
	LDA Enemy_Y_Position,x
	STA CheepCheepOrigYPos,x                     ; save original vertical coordinate here
	RTS

; --------------------------------

InitLakitu:
	LDA EnemyFrenzyBuffer                        ; check to see if an enemy is already in
	BNE KillLakitu                               ; the frenzy buffer, and branch to kill lakitu if so

SetupLakitu:
	LDA #$00                                     ; erase counter for lakitu's reappearance
	STA LakituReappearTimer
	JSR InitHorizFlySwimEnemy                    ; set $03 as bounding box, set other attributes
	JMP TallBBox2                                ; set $03 as bounding box again (not necessary) and leave

KillLakitu:
	JMP EraseEnemyObject

; --------------------------------
; $01-$03 - used to hold pseudorandom difference adjusters

PRDiffAdjustData:
	.db $26, $2c, $32, $38
	.db $20, $22, $24, $26
	.db $13, $14, $15, $16

LakituAndSpinyHandler:
	LDA FrenzyEnemyTimer                         ; if timer here not expired, leave
	BNE ExLSHand
	CPX #$05                                     ; if we are on the special use slot, leave
	BCS ExLSHand
	LDA #$80                                     ; set timer
	STA FrenzyEnemyTimer
	LDY #$04                                     ; start with the last enemy slot
ChkLak:
	LDA Enemy_ID,y                               ; check all enemy slots to see
	CMP #Lakitu                                  ; if lakitu is on one of them
	BEQ CreateSpiny                              ; if so, branch out of this loop
	DEY                                          ; otherwise check another slot
	BPL ChkLak                                   ; loop until all slots are checked
	INC LakituReappearTimer                      ; increment reappearance timer
	LDA LakituReappearTimer
	CMP #$07                                     ; check to see if we're up to a certain value yet
	BCC ExLSHand                                 ; if not, leave
	LDX #$04                                     ; start with the last enemy slot again
ChkNoEn:
	LDA Enemy_Flag,x                             ; check enemy buffer flag for non-active enemy slot
	BEQ CreateL                                  ; branch out of loop if found
	DEX                                          ; otherwise check next slot
	BPL ChkNoEn                                  ; branch until all slots are checked
	BMI RetEOfs                                  ; if no empty slots were found, branch to leave
CreateL:
	LDA #$00                                     ; initialize enemy state
	STA Enemy_State,x
	LDA #Lakitu                                  ; create lakitu enemy object
	STA Enemy_ID,x
	JSR SetupLakitu                              ; do a sub to set up lakitu
	LDA #$20
	JSR PutAtRightExtent                         ; finish setting up lakitu
RetEOfs:
	LDX ObjectOffset                             ; get enemy object buffer offset again and leave
ExLSHand:
	RTS

; --------------------------------

CreateSpiny:
	LDA Player_Y_Position                        ; if player above a certain point, branch to leave
	CMP #$2c
	BCC ExLSHand
	LDA Enemy_State,y                            ; if lakitu is not in normal state, branch to leave
	BNE ExLSHand
	LDA Enemy_PageLoc,y                          ; store horizontal coordinates (high and low) of lakitu
	STA Enemy_PageLoc,x                          ; into the coordinates of the spiny we're going to create
	LDA Enemy_X_Position,y
	STA Enemy_X_Position,x
	LDA #$01                                     ; put spiny within vertical screen unit
	STA Enemy_Y_HighPos,x
	LDA Enemy_Y_Position,y                       ; put spiny eight pixels above where lakitu is
	SEC
	SBC #$08
	STA Enemy_Y_Position,x
	LDA PseudoRandomBitReg,x                     ; get 2 LSB of LSFR and save to Y
	AND #%00000011
	TAY
	LDX #$02
DifLoop:
	LDA PRDiffAdjustData,y                       ; get three values and save them
	STA $01,x                                    ; to $01-$03
	INY
	INY                                          ; increment Y four bytes for each value
	INY
	INY
	DEX                                          ; decrement X for each one
	BPL DifLoop                                  ; loop until all three are written
	LDX ObjectOffset                             ; get enemy object buffer offset
	JSR PlayerLakituDiff                         ; move enemy, change direction, get value - difference
	LDY Player_X_Speed                           ; check player's horizontal speed
	CPY #$08
	BCS SetSpSpd                                 ; if moving faster than a certain amount, branch elsewhere
	TAY                                          ; otherwise save value in A to Y for now
	LDA PseudoRandomBitReg+1,x
	AND #%00000011                               ; get one of the LSFR parts and save the 2 LSB
	BEQ UsePosv                                  ; branch if neither bits are set
	TYA
	EOR #%11111111                               ; otherwise get two's compliment of Y
	TAY
	INY
UsePosv:
	TYA                                          ; put value from A in Y back to A (they will be lost anyway)
SetSpSpd:
	JSR SmallBBox                                ; set bounding box control, init attributes, lose contents of A
	LDY #$02
	STA Enemy_X_Speed,x                          ; set horizontal speed to zero because previous contents
	CMP #$00                                     ; of A were lost...branch here will never be taken for
	BMI SpinyRte                                 ; the same reason
	DEY
SpinyRte:
	STY Enemy_MovingDir,x                        ; set moving direction to the right
	LDA #$fd
	STA Enemy_Y_Speed,x                          ; set vertical speed to move upwards
	LDA #$01
	STA Enemy_Flag,x                             ; enable enemy object by setting flag
	LDA #$05
	STA Enemy_State,x                            ; put spiny in egg state and leave
ChpChpEx:
	RTS

; --------------------------------

FirebarSpinSpdData:
	.db $28, $38, $28, $38, $28

FirebarSpinDirData:
	.db $00, $00, $10, $10, $00

InitLongFirebar:
	JSR DuplicateEnemyObj                        ; create enemy object for long firebar

InitShortFirebar:
	LDA #$00                                     ; initialize low byte of spin state
	STA FirebarSpinState_Low,x
	LDA Enemy_ID,x                               ; subtract $1b from enemy identifier
	SEC                                          ; to get proper offset for firebar data
	SBC #$1b
	TAY
	LDA FirebarSpinSpdData,y                     ; get spinning speed of firebar
	STA FirebarSpinSpeed,x
	LDA FirebarSpinDirData,y                     ; get spinning direction of firebar
	STA FirebarSpinDirection,x
	LDA Enemy_Y_Position,x
	CLC                                          ; add four pixels to vertical coordinate
	ADC #$04
	STA Enemy_Y_Position,x
	LDA Enemy_X_Position,x
	CLC                                          ; add four pixels to horizontal coordinate
	ADC #$04
	STA Enemy_X_Position,x
	LDA Enemy_PageLoc,x
	ADC #$00                                     ; add carry to page location
	STA Enemy_PageLoc,x
	JMP TallBBox2                                ; set bounding box control (not used) and leave

; --------------------------------
; $00-$01 - used to hold pseudorandom bits

FlyCCXPositionData:
	.db $80, $30, $40, $80
	.db $30, $50, $50, $70
	.db $20, $40, $80, $a0
	.db $70, $40, $90, $68

FlyCCXSpeedData:
	.db $0e, $05, $06, $0e
	.db $1c, $20, $10, $0c
	.db $1e, $22, $18, $14

FlyCCTimerData:
	.db $10, $60, $20, $48

InitFlyingCheepCheep:
	LDA FrenzyEnemyTimer                         ; if timer here not expired yet, branch to leave
	BNE ChpChpEx
	JSR SmallBBox                                ; jump to set bounding box size $09 and init other values
	LDA PseudoRandomBitReg+1,x
	AND #%00000011                               ; set pseudorandom offset here
	TAY
	LDA FlyCCTimerData,y                         ; load timer with pseudorandom offset
	STA FrenzyEnemyTimer
	LDY #$03                                     ; load Y with default value
	LDA SecondaryHardMode
	BEQ MaxCC                                    ; if secondary hard mode flag not set, do not increment Y
	INY                                          ; otherwise, increment Y to allow as many as four onscreen
MaxCC:
	STY $00                                      ; store whatever pseudorandom bits are in Y
	CPX $00                                      ; compare enemy object buffer offset with Y
	BCS ChpChpEx                                 ; if X => Y, branch to leave
	LDA PseudoRandomBitReg,x
	AND #%00000011                               ; get last two bits of LSFR, first part
	STA $00                                      ; and store in two places
	STA $01
	LDA #$fb                                     ; set vertical speed for cheep-cheep
	STA Enemy_Y_Speed,x
	LDA #$00                                     ; load default value
	LDY Player_X_Speed                           ; check player's horizontal speed
	BEQ GSeed                                    ; if player not moving left or right, skip this part
	LDA #$04
	CPY #$19                                     ; if moving to the right but not very quickly,
	BCC GSeed                                    ; do not change A
	ASL                                          ; otherwise, multiply A by 2
GSeed:
	PHA                                          ; save to stack
	CLC
	ADC $00                                      ; add to last two bits of LSFR we saved earlier
	STA $00                                      ; save it there
	LDA PseudoRandomBitReg+1,x
	AND #%00000011                               ; if neither of the last two bits of second LSFR set,
	BEQ RSeed                                    ; skip this part and save contents of $00
	LDA PseudoRandomBitReg+2,x
	AND #%00001111                               ; otherwise overwrite with lower nybble of
	STA $00                                      ; third LSFR part
RSeed:
	PLA                                          ; get value from stack we saved earlier
	CLC
	ADC $01                                      ; add to last two bits of LSFR we saved in other place
	TAY                                          ; use as pseudorandom offset here
	LDA FlyCCXSpeedData,y                        ; get horizontal speed using pseudorandom offset
	STA Enemy_X_Speed,x
	LDA #$01                                     ; set to move towards the right
	STA Enemy_MovingDir,x
	LDA Player_X_Speed                           ; if player moving left or right, branch ahead of this part
	BNE D2XPos1
	LDY $00                                      ; get first LSFR or third LSFR lower nybble
	TYA                                          ; and check for d1 set
	AND #%00000010
	BEQ D2XPos1                                  ; if d1 not set, branch
	LDA Enemy_X_Speed,x
	EOR #$ff                                     ; if d1 set, change horizontal speed
	CLC                                          ; into two's compliment, thus moving in the opposite
	ADC #$01                                     ; direction
	STA Enemy_X_Speed,x
	INC Enemy_MovingDir,x                        ; increment to move towards the left
D2XPos1:
	TYA                                          ; get first LSFR or third LSFR lower nybble again
	AND #%00000010
	BEQ D2XPos2                                  ; check for d1 set again, branch again if not set
	LDA Player_X_Position                        ; get player's horizontal position
	CLC
	ADC FlyCCXPositionData,y                     ; if d1 set, add value obtained from pseudorandom offset
	STA Enemy_X_Position,x                       ; and save as enemy's horizontal position
	LDA Player_PageLoc                           ; get player's page location
	ADC #$00                                     ; add carry and jump past this part
	JMP FinCCSt
D2XPos2:
	LDA Player_X_Position                        ; get player's horizontal position
	SEC
	SBC FlyCCXPositionData,y                     ; if d1 not set, subtract value obtained from pseudorandom
	STA Enemy_X_Position,x                       ; offset and save as enemy's horizontal position
	LDA Player_PageLoc                           ; get player's page location
	SBC #$00                                     ; subtract borrow
FinCCSt:
	STA Enemy_PageLoc,x                          ; save as enemy's page location
	LDA #$01
	STA Enemy_Flag,x                             ; set enemy's buffer flag
	STA Enemy_Y_HighPos,x                        ; set enemy's high vertical byte
	LDA #$f8
	STA Enemy_Y_Position,x                       ; put enemy below the screen, and we are done
	RTS

; --------------------------------

InitBowser:
	JSR DuplicateEnemyObj                        ; jump to create another bowser object
	STX BowserFront_Offset                       ; save offset of first here
	LDA #$00
	STA BowserBodyControls                       ; initialize bowser's body controls
	STA BridgeCollapseOffset                     ; and bridge collapse offset
	LDA Enemy_X_Position,x
	STA BowserOrigXPos                           ; store original horizontal position here
	LDA #$df
	STA BowserFireBreathTimer                    ; store something here
	STA Enemy_MovingDir,x                        ; and in moving direction
	LDA #$20
	STA BowserFeetCounter                        ; set bowser's feet timer and in enemy timer
	STA EnemyFrameTimer,x
	LDA #$05
	STA BowserHitPoints                          ; give bowser 5 hit points
	LSR
	STA BowserMovementSpeed                      ; set default movement speed here
	RTS

; --------------------------------

DuplicateEnemyObj:
	LDY #$ff                                     ; start at beginning of enemy slots
FSLoop:
	INY                                          ; increment one slot
	LDA Enemy_Flag,y                             ; check enemy buffer flag for empty slot
	BNE FSLoop                                   ; if set, branch and keep checking
	STY DuplicateObj_Offset                      ; otherwise set offset here
	TXA                                          ; transfer original enemy buffer offset
	ORA #%10000000                               ; store with d7 set as flag in new enemy
	STA Enemy_Flag,y                             ; slot as well as enemy offset
	LDA Enemy_PageLoc,x
	STA Enemy_PageLoc,y                          ; copy page location and horizontal coordinates
	LDA Enemy_X_Position,x                       ; from original enemy to new enemy
	STA Enemy_X_Position,y
	LDA #$01
	STA Enemy_Flag,x                             ; set flag as normal for original enemy
	STA Enemy_Y_HighPos,y                        ; set high vertical byte for new enemy
	LDA Enemy_Y_Position,x
	STA Enemy_Y_Position,y                       ; copy vertical coordinate from original to new
FlmEx:
	RTS                                          ; and then leave

; --------------------------------

FlameYPosData:
	.db $90, $80, $70, $90

FlameYMFAdderData:
	.db $ff, $01

InitBowserFlame:
	LDA FrenzyEnemyTimer                         ; if timer not expired yet, branch to leave
	BNE FlmEx
	STA Enemy_Y_MoveForce,x                      ; reset something here
	LDA NoiseSoundQueue
	ORA #Sfx_BowserFlame                         ; load bowser's flame sound into queue
	STA NoiseSoundQueue
	LDY BowserFront_Offset                       ; get bowser's buffer offset
	LDA Enemy_ID,y                               ; check for bowser
	CMP #Bowser
	BEQ SpawnFromMouth                           ; branch if found
	JSR SetFlameTimer                            ; get timer data based on flame counter
	CLC
	ADC #$20                                     ; add 32 frames by default
	LDY SecondaryHardMode
	BEQ SetFrT                                   ; if secondary mode flag not set, use as timer setting
	SEC
	SBC #$10                                     ; otherwise subtract 16 frames for secondary hard mode
SetFrT:
	STA FrenzyEnemyTimer                         ; set timer accordingly
	LDA PseudoRandomBitReg,x
	AND #%00000011                               ; get 2 LSB from first part of LSFR
	STA BowserFlamePRandomOfs,x                  ; set here
	TAY                                          ; use as offset
	LDA FlameYPosData,y                          ; load vertical position based on pseudorandom offset

PutAtRightExtent:
	STA Enemy_Y_Position,x                       ; set vertical position
	LDA ScreenRight_X_Pos
	CLC
	ADC #$20                                     ; place enemy 32 pixels beyond right side of screen
	STA Enemy_X_Position,x
	LDA ScreenRight_PageLoc
	ADC #$00                                     ; add carry
	STA Enemy_PageLoc,x
	JMP FinishFlame                              ; skip this part to finish setting values

SpawnFromMouth:
	LDA Enemy_X_Position,y                       ; get bowser's horizontal position
	SEC
	SBC #$0e                                     ; subtract 14 pixels
	STA Enemy_X_Position,x                       ; save as flame's horizontal position
	LDA Enemy_PageLoc,y
	STA Enemy_PageLoc,x                          ; copy page location from bowser to flame
	LDA Enemy_Y_Position,y
	CLC                                          ; add 8 pixels to bowser's vertical position
	ADC #$08
	STA Enemy_Y_Position,x                       ; save as flame's vertical position
	LDA PseudoRandomBitReg,x
	AND #%00000011                               ; get 2 LSB from first part of LSFR
	STA Enemy_YMF_Dummy,x                        ; save here
	TAY                                          ; use as offset
	LDA FlameYPosData,y                          ; get value here using bits as offset
	LDY #$00                                     ; load default offset
	CMP Enemy_Y_Position,x                       ; compare value to flame's current vertical position
	BCC SetMF                                    ; if less, do not increment offset
	INY                                          ; otherwise increment now
SetMF:
	LDA FlameYMFAdderData,y                      ; get value here and save
	STA Enemy_Y_MoveForce,x                      ; to vertical movement force
	LDA #$00
	STA EnemyFrenzyBuffer                        ; clear enemy frenzy buffer

FinishFlame:
	LDA #$08                                     ; set $08 for bounding box control
	STA Enemy_BoundBoxCtrl,x
	LDA #$01                                     ; set high byte of vertical and
	STA Enemy_Y_HighPos,x                        ; enemy buffer flag
	STA Enemy_Flag,x
	LSR
	STA Enemy_X_MoveForce,x                      ; initialize horizontal movement force, and
	STA Enemy_State,x                            ; enemy state
	RTS

; --------------------------------

FireworksXPosData:
	.db $00, $30, $60, $60, $00, $20

FireworksYPosData:
	.db $60, $40, $70, $40, $60, $30

InitFireworks:
	LDA FrenzyEnemyTimer                         ; if timer not expired yet, branch to leave
	BNE ExitFWk
	LDA #$20                                     ; otherwise reset timer
	STA FrenzyEnemyTimer
	DEC FireworksCounter                         ; decrement for each explosion
	LDY #$06                                     ; start at last slot
StarFChk:
	DEY
	LDA Enemy_ID,y                               ; check for presence of star flag object
	CMP #StarFlagObject                          ; if there isn't a star flag object,
	BNE StarFChk                                 ; routine goes into infinite loop = crash
	LDA Enemy_X_Position,y
	SEC                                          ; get horizontal coordinate of star flag object, then
	SBC #$30                                     ; subtract 48 pixels from it and save to
	PHA                                          ; the stack
	LDA Enemy_PageLoc,y
	SBC #$00                                     ; subtract the carry from the page location
	STA $00                                      ; of the star flag object
	LDA FireworksCounter                         ; get fireworks counter
	CLC
	ADC Enemy_State,y                            ; add state of star flag object (possibly not necessary)
	TAY                                          ; use as offset
	PLA                                          ; get saved horizontal coordinate of star flag - 48 pixels
	CLC
	ADC FireworksXPosData,y                      ; add number based on offset of fireworks counter
	STA Enemy_X_Position,x                       ; store as the fireworks object horizontal coordinate
	LDA $00
	ADC #$00                                     ; add carry and store as page location for
	STA Enemy_PageLoc,x                          ; the fireworks object
	LDA FireworksYPosData,y                      ; get vertical position using same offset
	STA Enemy_Y_Position,x                       ; and store as vertical coordinate for fireworks object
	LDA #$01
	STA Enemy_Y_HighPos,x                        ; store in vertical high byte
	STA Enemy_Flag,x                             ; and activate enemy buffer flag
	LSR
	STA ExplosionGfxCounter,x                    ; initialize explosion counter
	LDA #$08
	STA ExplosionTimerCounter,x                  ; set explosion timing counter
ExitFWk:
	RTS

; --------------------------------

Bitmasks:
	.db %00000001, %00000010, %00000100, %00001000, %00010000, %00100000, %01000000, %10000000

Enemy17YPosData:
	.db $40, $30, $90, $50, $20, $60, $a0, $70

SwimCC_IDData:
	.db $0a, $0b

BulletBillCheepCheep:
	LDA FrenzyEnemyTimer                         ; if timer not expired yet, branch to leave
	BNE ExF17
	LDA AreaType                                 ; are we in a water-type level?
	BNE DoBulletBills                            ; if not, branch elsewhere
	CPX #$03                                     ; are we past third enemy slot?
	BCS ExF17                                    ; if so, branch to leave
	LDY #$00                                     ; load default offset
	LDA PseudoRandomBitReg,x
	CMP #$aa                                     ; check first part of LSFR against preset value
	BCC ChkW2                                    ; if less than preset, do not increment offset
	INY                                          ; otherwise increment
ChkW2:
	LDA WorldNumber                              ; check world number
	CMP #World2
	BEQ Get17ID                                  ; if we're on world 2, do not increment offset
	INY                                          ; otherwise increment
Get17ID:
	TYA
	AND #%00000001                               ; mask out all but last bit of offset
	TAY
	LDA SwimCC_IDData,y                          ; load identifier for cheep-cheeps
Set17ID:
	STA Enemy_ID,x                               ; store whatever's in A as enemy identifier
	LDA BitMFilter
	CMP #$ff                                     ; if not all bits set, skip init part and compare bits
	BNE GetRBit
	LDA #$00                                     ; initialize vertical position filter
	STA BitMFilter
GetRBit:
	LDA PseudoRandomBitReg,x                     ; get first part of LSFR
	AND #%00000111                               ; mask out all but 3 LSB
ChkRBit:
	TAY                                          ; use as offset
	LDA Bitmasks,y                               ; load bitmask
	BIT BitMFilter                               ; perform AND on filter without changing it
	BEQ AddFBit
	INY                                          ; increment offset
	TYA
	AND #%00000111                               ; mask out all but 3 LSB thus keeping it 0-7
	JMP ChkRBit                                  ; do another check
AddFBit:
	ORA BitMFilter                               ; add bit to already set bits in filter
	STA BitMFilter                               ; and store
	LDA Enemy17YPosData,y                        ; load vertical position using offset
	JSR PutAtRightExtent                         ; set vertical position and other values
	STA Enemy_YMF_Dummy,x                        ; initialize dummy variable
	LDA #$20                                     ; set timer
	STA FrenzyEnemyTimer
	JMP CheckpointEnemyID                        ; process our new enemy object

DoBulletBills:
	LDY #$ff                                     ; start at beginning of enemy slots
BB_SLoop:
	INY                                          ; move onto the next slot
	CPY #$05                                     ; branch to play sound if we've done all slots
	BCS FireBulletBill
	LDA Enemy_Flag,y                             ; if enemy buffer flag not set,
	BEQ BB_SLoop                                 ; loop back and check another slot
	LDA Enemy_ID,y
	CMP #BulletBill_FrenzyVar                    ; check enemy identifier for
	BNE BB_SLoop                                 ; bullet bill object (frenzy variant)
ExF17:
	RTS                                          ; if found, leave

FireBulletBill:
	LDA Square2SoundQueue
	ORA #Sfx_Blast                               ; play fireworks/gunfire sound
	STA Square2SoundQueue
	LDA #BulletBill_FrenzyVar                    ; load identifier for bullet bill object
	BNE Set17ID                                  ; unconditional branch

; --------------------------------
; $00 - used to store Y position of group enemies
; $01 - used to store enemy ID
; $02 - used to store page location of right side of screen
; $03 - used to store X position of right side of screen

HandleGroupEnemies:
	LDY #$00                                     ; load value for green koopa troopa
	SEC
	SBC #$37                                     ; subtract $37 from second byte read
	PHA                                          ; save result in stack for now
	CMP #$04                                     ; was byte in $3b-$3e range?
	BCS SnglID                                   ; if so, branch
	PHA                                          ; save another copy to stack
	LDY #Goomba                                  ; load value for goomba enemy
	LDA PrimaryHardMode                          ; if primary hard mode flag not set,
	BEQ PullID                                   ; branch, otherwise change to value
	LDY #BuzzyBeetle                             ; for buzzy beetle
PullID:
	PLA                                          ; get second copy from stack
SnglID:
	STY $01                                      ; save enemy id here
	LDY #$b0                                     ; load default y coordinate
	AND #$02                                     ; check to see if d1 was set
	BEQ SetYGp                                   ; if so, move y coordinate up,
	LDY #$70                                     ; otherwise branch and use default
SetYGp:
	STY $00                                      ; save y coordinate here
	LDA ScreenRight_PageLoc                      ; get page number of right edge of screen
	STA $02                                      ; save here
	LDA ScreenRight_X_Pos                        ; get pixel coordinate of right edge
	STA $03                                      ; save here
	LDY #$02                                     ; load two enemies by default
	PLA                                          ; get first copy from stack
	LSR                                          ; check to see if d0 was set
	BCC CntGrp                                   ; if not, use default value
	INY                                          ; otherwise increment to three enemies
CntGrp:
	STY NumberofGroupEnemies                     ; save number of enemies here
GrLoop:
	LDX #$ff                                     ; start at beginning of enemy buffers
GSltLp:
	INX                                          ; increment and branch if past
	CPX #$05                                     ; end of buffers
	BCS NextED
	LDA Enemy_Flag,x                             ; check to see if enemy is already
	BNE GSltLp                                   ; stored in buffer, and branch if so
	LDA $01
	STA Enemy_ID,x                               ; store enemy object identifier
	LDA $02
	STA Enemy_PageLoc,x                          ; store page location for enemy object
	LDA $03
	STA Enemy_X_Position,x                       ; store x coordinate for enemy object
	CLC
	ADC #$18                                     ; add 24 pixels for next enemy
	STA $03
	LDA $02                                      ; add carry to page location for
	ADC #$00                                     ; next enemy
	STA $02
	LDA $00                                      ; store y coordinate for enemy object
	STA Enemy_Y_Position,x
	LDA #$01                                     ; activate flag for buffer, and
	STA Enemy_Y_HighPos,x                        ; put enemy within the screen vertically
	STA Enemy_Flag,x
	JSR CheckpointEnemyID                        ; process each enemy object separately
	DEC NumberofGroupEnemies                     ; do this until we run out of enemy objects
	BNE GrLoop
NextED:
	JMP Inc2B                                    ; jump to increment data offset and leave

; --------------------------------

InitPiranhaPlant:
	LDA #$01                                     ; set initial speed
	STA PiranhaPlant_Y_Speed,x
	LSR
	STA Enemy_State,x                            ; initialize enemy state and what would normally
	STA PiranhaPlant_MoveFlag,x                  ; be used as vertical speed, but not in this case
	LDA Enemy_Y_Position,x
	STA PiranhaPlantDownYPos,x                   ; save original vertical coordinate here
	SEC
	SBC #$18
	STA PiranhaPlantUpYPos,x                     ; save original vertical coordinate - 24 pixels here
	LDA #$09
	JMP SetBBox2                                 ; set specific value for bounding box control

; --------------------------------

InitEnemyFrenzy:
	LDA Enemy_ID,x                               ; load enemy identifier
	STA EnemyFrenzyBuffer                        ; save in enemy frenzy buffer
	SEC
	SBC #$12                                     ; subtract 12 and use as offset for jump engine
	JSR JumpEngine

; frenzy object jump table
	.dw LakituAndSpinyHandler
	.dw NoFrenzyCode
	.dw InitFlyingCheepCheep
	.dw InitBowserFlame
	.dw InitFireworks
	.dw BulletBillCheepCheep

; --------------------------------

NoFrenzyCode:
	RTS

; --------------------------------

EndFrenzy:
	LDY #$05                                     ; start at last slot
LakituChk:
	LDA Enemy_ID,y                               ; check enemy identifiers
	CMP #Lakitu                                  ; for lakitu
	BNE NextFSlot
	LDA #$01                                     ; if found, set state
	STA Enemy_State,y
NextFSlot:
	DEY                                          ; move onto the next slot
	BPL LakituChk                                ; do this until all slots are checked
	LDA #$00
	STA EnemyFrenzyBuffer                        ; empty enemy frenzy buffer
	STA Enemy_Flag,x                             ; disable enemy buffer flag for this object
	RTS

; --------------------------------

InitJumpGPTroopa:
	LDA #$02                                     ; set for movement to the left
	STA Enemy_MovingDir,x
	LDA #$f8                                     ; set horizontal speed
	STA Enemy_X_Speed,x
TallBBox2:
	LDA #$03                                     ; set specific value for bounding box control
SetBBox2:
	STA Enemy_BoundBoxCtrl,x                     ; set bounding box control then leave
	RTS

; --------------------------------

InitBalPlatform:
	DEC Enemy_Y_Position,x                       ; raise vertical position by two pixels
	DEC Enemy_Y_Position,x
	LDY SecondaryHardMode                        ; if secondary hard mode flag not set,
	BNE AlignP                                   ; branch ahead
	LDY #$02                                     ; otherwise set value here
	JSR PosPlatform                              ; do a sub to add or subtract pixels
AlignP:
	LDY #$ff                                     ; set default value here for now
	LDA BalPlatformAlignment                     ; get current balance platform alignment
	STA Enemy_State,x                            ; set platform alignment to object state here
	BPL SetBPA                                   ; if old alignment $ff, put $ff as alignment for negative
	TXA                                          ; if old contents already $ff, put
	TAY                                          ; object offset as alignment to make next positive
SetBPA:
	STY BalPlatformAlignment                     ; store whatever value's in Y here
	LDA #$00
	STA Enemy_MovingDir,x                        ; init moving direction
	TAY                                          ; init Y
	JSR PosPlatform                              ; do a sub to add 8 pixels, then run shared code here

; --------------------------------

InitDropPlatform:
	LDA #$ff
	STA PlatformCollisionFlag,x                  ; set some value here
	JMP CommonPlatCode                           ; then jump ahead to execute more code

; --------------------------------

InitHoriPlatform:
	LDA #$00
	STA XMoveSecondaryCounter,x                  ; init one of the moving counters
	JMP CommonPlatCode                           ; jump ahead to execute more code

; --------------------------------

InitVertPlatform:
	LDY #$40                                     ; set default value here
	LDA Enemy_Y_Position,x                       ; check vertical position
	BPL SetYO                                    ; if above a certain point, skip this part
	EOR #$ff
	CLC                                          ; otherwise get two's compliment
	ADC #$01
	LDY #$c0                                     ; get alternate value to add to vertical position
SetYO:
	STA YPlatformTopYPos,x                       ; save as top vertical position
	TYA
	CLC                                          ; load value from earlier, add number of pixels
	ADC Enemy_Y_Position,x                       ; to vertical position
	STA YPlatformCenterYPos,x                    ; save result as central vertical position

; --------------------------------

CommonPlatCode:

	JSR InitVStf                                 ; do a sub to init certain other values
SPBBox:
	LDA #$05                                     ; set default bounding box size control
	LDY AreaType
	CPY #$03                                     ; check for castle-type level
	BEQ CasPBB                                   ; use default value if found
	LDY SecondaryHardMode                        ; otherwise check for secondary hard mode flag
	BNE CasPBB                                   ; if set, use default value
	LDA #$06                                     ; use alternate value if not castle or secondary not set
CasPBB:
	STA Enemy_BoundBoxCtrl,x                     ; set bounding box size control here and leave
	RTS

; --------------------------------

LargeLiftUp:
	JSR PlatLiftUp                               ; execute code for platforms going up
	JMP LargeLiftBBox                            ; overwrite bounding box for large platforms

LargeLiftDown:
	JSR PlatLiftDown                             ; execute code for platforms going down

LargeLiftBBox:
	JMP SPBBox                                   ; jump to overwrite bounding box size control

; --------------------------------

PlatLiftUp:
	LDA #$10                                     ; set movement amount here
	STA Enemy_Y_MoveForce,x
	LDA #$ff                                     ; set moving speed for platforms going up
	STA Enemy_Y_Speed,x
	JMP CommonSmallLift                          ; skip ahead to part we should be executing

; --------------------------------

PlatLiftDown:
	LDA #$f0                                     ; set movement amount here
	STA Enemy_Y_MoveForce,x
	LDA #$00                                     ; set moving speed for platforms going down
	STA Enemy_Y_Speed,x

; --------------------------------

CommonSmallLift:
	LDY #$01
	JSR PosPlatform                              ; do a sub to add 12 pixels due to preset value
	LDA #$04
	STA Enemy_BoundBoxCtrl,x                     ; set bounding box control for small platforms
	RTS

; --------------------------------

PlatPosDataLow:
	.db $08,$0c,$f8

PlatPosDataHigh:
	.db $00,$00,$ff

PosPlatform:
	LDA Enemy_X_Position,x                       ; get horizontal coordinate
	CLC
	ADC PlatPosDataLow,y                         ; add or subtract pixels depending on offset
	STA Enemy_X_Position,x                       ; store as new horizontal coordinate
	LDA Enemy_PageLoc,x
	ADC PlatPosDataHigh,y                        ; add or subtract page location depending on offset
	STA Enemy_PageLoc,x                          ; store as new page location
	RTS                                          ; and go back

; --------------------------------

EndOfEnemyInitCode:
	RTS

; -------------------------------------------------------------------------------------

RunEnemyObjectsCore:
	LDX ObjectOffset                             ; get offset for enemy object buffer
	LDA #$00                                     ; load value 0 for jump engine by default
	LDY Enemy_ID,x
	CPY #$15                                     ; if enemy object < $15, use default value
	BCC JmpEO
	TYA                                          ; otherwise subtract $14 from the value and use
	SBC #$14                                     ; as value for jump engine
JmpEO:
	JSR JumpEngine

	.dw RunNormalEnemies                         ; for objects $00-$14

	.dw RunBowserFlame                           ; for objects $15-$1f
	.dw RunFireworks
	.dw NoRunCode
	.dw NoRunCode
	.dw NoRunCode
	.dw NoRunCode
	.dw RunFirebarObj
	.dw RunFirebarObj
	.dw RunFirebarObj
	.dw RunFirebarObj
	.dw RunFirebarObj

	.dw RunFirebarObj                            ; for objects $20-$2f
	.dw RunFirebarObj
	.dw RunFirebarObj
	.dw NoRunCode
	.dw RunLargePlatform
	.dw RunLargePlatform
	.dw RunLargePlatform
	.dw RunLargePlatform
	.dw RunLargePlatform
	.dw RunLargePlatform
	.dw RunLargePlatform
	.dw RunSmallPlatform
	.dw RunSmallPlatform
	.dw RunBowser
	.dw PowerUpObjHandler
	.dw VineObjectHandler

	.dw NoRunCode                                ; for objects $30-$35
	.dw RunStarFlagObj
	.dw JumpspringHandler
	.dw NoRunCode
	.dw WarpZoneObject
	.dw RunRetainerObj

; --------------------------------

NoRunCode:
	RTS

; --------------------------------

RunRetainerObj:
	JSR GetEnemyOffscreenBits
	JSR RelativeEnemyPosition
	JMP EnemyGfxHandler

; --------------------------------

RunNormalEnemies:
	LDA #$00                                     ; init sprite attributes
	STA Enemy_SprAttrib,x
	JSR GetEnemyOffscreenBits
	JSR RelativeEnemyPosition
	JSR EnemyGfxHandler
	JSR GetEnemyBoundBox
	JSR EnemyToBGCollisionDet
	JSR EnemiesCollision
	JSR PlayerEnemyCollision
	LDY TimerControl                             ; if master timer control set, skip to last routine
	BNE SkipMove
	JSR EnemyMovementSubs
SkipMove:
	JMP OffscreenBoundsCheck

EnemyMovementSubs:
	LDA Enemy_ID,x
	JSR JumpEngine

	.dw MoveNormalEnemy                          ; only objects $00-$14 use this table
	.dw MoveNormalEnemy
	.dw MoveNormalEnemy
	.dw MoveNormalEnemy
	.dw MoveNormalEnemy
	.dw ProcHammerBro
	.dw MoveNormalEnemy
	.dw MoveBloober
	.dw MoveBulletBill
	.dw NoMoveCode
	.dw MoveSwimmingCheepCheep
	.dw MoveSwimmingCheepCheep
	.dw MovePodoboo
	.dw MovePiranhaPlant
	.dw MoveJumpingEnemy
	.dw ProcMoveRedPTroopa
	.dw MoveFlyGreenPTroopa
	.dw MoveLakitu
	.dw MoveNormalEnemy
	.dw NoMoveCode                               ; dummy
	.dw MoveFlyingCheepCheep

; --------------------------------

NoMoveCode:
	RTS

; --------------------------------

RunBowserFlame:
	JSR ProcBowserFlame
	JSR GetEnemyOffscreenBits
	JSR RelativeEnemyPosition
	JSR GetEnemyBoundBox
	JSR PlayerEnemyCollision
	JMP OffscreenBoundsCheck

; --------------------------------

RunFirebarObj:
	JSR ProcFirebar
	JMP OffscreenBoundsCheck

; --------------------------------

RunSmallPlatform:
	JSR GetEnemyOffscreenBits
	JSR RelativeEnemyPosition
	JSR SmallPlatformBoundBox
	JSR SmallPlatformCollision
	JSR RelativeEnemyPosition
	JSR DrawSmallPlatform
	JSR MoveSmallPlatform
	JMP OffscreenBoundsCheck

; --------------------------------

RunLargePlatform:
	JSR GetEnemyOffscreenBits
	JSR RelativeEnemyPosition
	JSR LargePlatformBoundBox
	JSR LargePlatformCollision
	LDA TimerControl                             ; if master timer control set,
	BNE SkipPT                                   ; skip subroutine tree
	JSR LargePlatformSubroutines
SkipPT:
	JSR RelativeEnemyPosition
	JSR DrawLargePlatform
	JMP OffscreenBoundsCheck

; --------------------------------

LargePlatformSubroutines:
	LDA Enemy_ID,x                               ; subtract $24 to get proper offset for jump table
	SEC
	SBC #$24
	JSR JumpEngine

	.dw BalancePlatform                          ; table used by objects $24-$2a
	.dw YMovingPlatform
	.dw MoveLargeLiftPlat
	.dw MoveLargeLiftPlat
	.dw XMovingPlatform
	.dw DropPlatform
	.dw RightPlatform

; -------------------------------------------------------------------------------------

EraseEnemyObject:
	LDA #$00                                     ; clear all enemy object variables
	STA Enemy_Flag,x
	STA Enemy_ID,x
	STA Enemy_State,x
	STA FloateyNum_Control,x
	STA EnemyIntervalTimer,x
	STA ShellChainCounter,x
	STA Enemy_SprAttrib,x
	STA EnemyFrameTimer,x
	RTS

; -------------------------------------------------------------------------------------

MovePodoboo:
	LDA EnemyIntervalTimer,x                     ; check enemy timer
	BNE PdbM                                     ; branch to move enemy if not expired
	JSR InitPodoboo                              ; otherwise set up podoboo again
	LDA PseudoRandomBitReg+1,x                   ; get part of LSFR
	ORA #%10000000                               ; set d7
	STA Enemy_Y_MoveForce,x                      ; store as movement force
	AND #%00001111                               ; mask out high nybble
	ORA #$06                                     ; set for at least six intervals
	STA EnemyIntervalTimer,x                     ; store as new enemy timer
	LDA #$f9
	STA Enemy_Y_Speed,x                          ; set vertical speed to move podoboo upwards
PdbM:
	JMP MoveJ_EnemyVertically                    ; branch to impose gravity on podoboo

; --------------------------------
; $00 - used in HammerBroJumpCode as bitmask

HammerThrowTmrData:
	.db $30, $1c

XSpeedAdderData:
	.db $00, $e8, $00, $18

RevivedXSpeed:
	.db $08, $f8, $0c, $f4

ProcHammerBro:
	LDA Enemy_State,x                            ; check hammer bro's enemy state for d5 set
	AND #%00100000
	BEQ ChkJH                                    ; if not set, go ahead with code
	JMP MoveDefeatedEnemy                        ; otherwise jump to something else
ChkJH:
	LDA HammerBroJumpTimer,x                     ; check jump timer
	BEQ HammerBroJumpCode                        ; if expired, branch to jump
	DEC HammerBroJumpTimer,x                     ; otherwise decrement jump timer
	LDA Enemy_OffscreenBits
	AND #%00001100                               ; check offscreen bits
	BNE MoveHammerBroXDir                        ; if hammer bro a little offscreen, skip to movement code
	LDA HammerThrowingTimer,x                    ; check hammer throwing timer
	BNE DecHT                                    ; if not expired, skip ahead, do not throw hammer
	LDY SecondaryHardMode                        ; otherwise get secondary hard mode flag
	LDA HammerThrowTmrData,y                     ; get timer data using flag as offset
	STA HammerThrowingTimer,x                    ; set as new timer
	JSR SpawnHammerObj                           ; do a sub here to spawn hammer object
	BCC DecHT                                    ; if carry clear, hammer not spawned, skip to decrement timer
	LDA Enemy_State,x
	ORA #%00001000                               ; set d3 in enemy state for hammer throw
	STA Enemy_State,x
	JMP MoveHammerBroXDir                        ; jump to move hammer bro
DecHT:
	DEC HammerThrowingTimer,x                    ; decrement timer
	JMP MoveHammerBroXDir                        ; jump to move hammer bro

HammerBroJumpLData:
	.db $20, $37

HammerBroJumpCode:
	LDA Enemy_State,x                            ; get hammer bro's enemy state
	AND #%00000111                               ; mask out all but 3 LSB
	CMP #$01                                     ; check for d0 set (for jumping)
	BEQ MoveHammerBroXDir                        ; if set, branch ahead to moving code
	LDA #$00                                     ; load default value here
	STA $00                                      ; save into temp variable for now
	LDY #$fa                                     ; set default vertical speed
	LDA Enemy_Y_Position,x                       ; check hammer bro's vertical coordinate
	BMI SetHJ                                    ; if on the bottom half of the screen, use current speed
	LDY #$fd                                     ; otherwise set alternate vertical speed
	CMP #$70                                     ; check to see if hammer bro is above the middle of screen
	INC $00                                      ; increment preset value to $01
	BCC SetHJ                                    ; if above the middle of the screen, use current speed and $01
	DEC $00                                      ; otherwise return value to $00
	LDA PseudoRandomBitReg+1,x                   ; get part of LSFR, mask out all but LSB
	AND #$01
	BNE SetHJ                                    ; if d0 of LSFR set, branch and use current speed and $00
	LDY #$fa                                     ; otherwise reset to default vertical speed
SetHJ:
	STY Enemy_Y_Speed,x                          ; set vertical speed for jumping
	LDA Enemy_State,x                            ; set d0 in enemy state for jumping
	ORA #$01
	STA Enemy_State,x
	LDA $00                                      ; load preset value here to use as bitmask
	AND PseudoRandomBitReg+2,x                   ; and do bit-wise comparison with part of LSFR
	TAY                                          ; then use as offset
	LDA SecondaryHardMode                        ; check secondary hard mode flag
	BNE HJump
	TAY                                          ; if secondary hard mode flag clear, set offset to 0
HJump:
	LDA HammerBroJumpLData,y                     ; get jump length timer data using offset from before
	STA EnemyFrameTimer,x                        ; save in enemy timer
	LDA PseudoRandomBitReg+1,x
	ORA #%11000000                               ; get contents of part of LSFR, set d7 and d6, then
	STA HammerBroJumpTimer,x                     ; store in jump timer

MoveHammerBroXDir:
	LDY #$fc                                     ; move hammer bro a little to the left
	LDA FrameCounter
	AND #%01000000                               ; change hammer bro's direction every 64 frames
	BNE Shimmy
	LDY #$04                                     ; if d6 set in counter, move him a little to the right
Shimmy:
	STY Enemy_X_Speed,x                          ; store horizontal speed
	LDY #$01                                     ; set to face right by default
	JSR PlayerEnemyDiff                          ; get horizontal difference between player and hammer bro
	BMI SetShim                                  ; if enemy to the left of player, skip this part
	INY                                          ; set to face left
	LDA EnemyIntervalTimer,x                     ; check walking timer
	BNE SetShim                                  ; if not yet expired, skip to set moving direction
	LDA #$f8
	STA Enemy_X_Speed,x                          ; otherwise, make the hammer bro walk left towards player
SetShim:
	STY Enemy_MovingDir,x                        ; set moving direction

MoveNormalEnemy:
	LDY #$00                                     ; init Y to leave horizontal movement as-is
	LDA Enemy_State,x
	AND #%01000000                               ; check enemy state for d6 set, if set skip
	BNE FallE                                    ; to move enemy vertically, then horizontally if necessary
	LDA Enemy_State,x
	ASL                                          ; check enemy state for d7 set
	BCS SteadM                                   ; if set, branch to move enemy horizontally
	LDA Enemy_State,x
	AND #%00100000                               ; check enemy state for d5 set
	BNE MoveDefeatedEnemy                        ; if set, branch to move defeated enemy object
	LDA Enemy_State,x
	AND #%00000111                               ; check d2-d0 of enemy state for any set bits
	BEQ SteadM                                   ; if enemy in normal state, branch to move enemy horizontally
	CMP #$05
	BEQ FallE                                    ; if enemy in state used by spiny's egg, go ahead here
	CMP #$03
	BCS ReviveStunned                            ; if enemy in states $03 or $04, skip ahead to yet another part
FallE:
	JSR MoveD_EnemyVertically                    ; do a sub here to move enemy downwards
	LDY #$00
	LDA Enemy_State,x                            ; check for enemy state $02
	CMP #$02
	BEQ MEHor                                    ; if found, branch to move enemy horizontally
	AND #%01000000                               ; check for d6 set
	BEQ SteadM                                   ; if not set, branch to something else
	LDA Enemy_ID,x
	CMP #PowerUpObject                           ; check for power-up object
	BEQ SteadM
	BNE SlowM                                    ; if any other object where d6 set, jump to set Y
MEHor:
	JMP MoveEnemyHorizontally                    ; jump here to move enemy horizontally for <> $2e and d6 set

SlowM:
	LDY #$01                                     ; if branched here, increment Y to slow horizontal movement
SteadM:
	LDA Enemy_X_Speed,x                          ; get current horizontal speed
	PHA                                          ; save to stack
	BPL AddHS                                    ; if not moving or moving right, skip, leave Y alone
	INY
	INY                                          ; otherwise increment Y to next data
AddHS:
	CLC
	ADC XSpeedAdderData,y                        ; add value here to slow enemy down if necessary
	STA Enemy_X_Speed,x                          ; save as horizontal speed temporarily
	JSR MoveEnemyHorizontally                    ; then do a sub to move horizontally
	PLA
	STA Enemy_X_Speed,x                          ; get old horizontal speed from stack and return to
	RTS                                          ; original memory location, then leave

ReviveStunned:
	LDA EnemyIntervalTimer,x                     ; if enemy timer not expired yet,
	BNE ChkKillGoomba                            ; skip ahead to something else
	STA Enemy_State,x                            ; otherwise initialize enemy state to normal
	LDA FrameCounter
	AND #$01                                     ; get d0 of frame counter
	TAY                                          ; use as Y and increment for movement direction
	INY
	STY Enemy_MovingDir,x                        ; store as pseudorandom movement direction
	DEY                                          ; decrement for use as pointer
	LDA PrimaryHardMode                          ; check primary hard mode flag
	BEQ SetRSpd                                  ; if not set, use pointer as-is
	INY
	INY                                          ; otherwise increment 2 bytes to next data
SetRSpd:
	LDA RevivedXSpeed,y                          ; load and store new horizontal speed
	STA Enemy_X_Speed,x                          ; and leave
	RTS

MoveDefeatedEnemy:
	JSR MoveD_EnemyVertically                    ; execute sub to move defeated enemy downwards
	JMP MoveEnemyHorizontally                    ; now move defeated enemy horizontally

ChkKillGoomba:
	CMP #$0e                                     ; check to see if enemy timer has reached
	BNE NKGmba                                   ; a certain point, and branch to leave if not
	LDA Enemy_ID,x
	CMP #Goomba                                  ; check for goomba object
	BNE NKGmba                                   ; branch if not found
	JSR EraseEnemyObject                         ; otherwise, kill this goomba object
NKGmba:
	RTS                                          ; leave!

; --------------------------------

MoveJumpingEnemy:
	JSR MoveJ_EnemyVertically                    ; do a sub to impose gravity on green paratroopa
	JMP MoveEnemyHorizontally                    ; jump to move enemy horizontally

; --------------------------------

ProcMoveRedPTroopa:
	LDA Enemy_Y_Speed,x
	ORA Enemy_Y_MoveForce,x                      ; check for any vertical force or speed
	BNE MoveRedPTUpOrDown                        ; branch if any found
	STA Enemy_YMF_Dummy,x                        ; initialize something here
	LDA Enemy_Y_Position,x                       ; check current vs. original vertical coordinate
	CMP RedPTroopaOrigXPos,x
	BCS MoveRedPTUpOrDown                        ; if current => original, skip ahead to more code
	LDA FrameCounter                             ; get frame counter
	AND #%00000111                               ; mask out all but 3 LSB
	BNE NoIncPT                                  ; if any bits set, branch to leave
	INC Enemy_Y_Position,x                       ; otherwise increment red paratroopa's vertical position
NoIncPT:
	RTS                                          ; leave

MoveRedPTUpOrDown:
	LDA Enemy_Y_Position,x                       ; check current vs. central vertical coordinate
	CMP RedPTroopaCenterYPos,x
	BCC MovPTDwn                                 ; if current < central, jump to move downwards
	JMP MoveRedPTroopaUp                         ; otherwise jump to move upwards
MovPTDwn:
	JMP MoveRedPTroopaDown                       ; move downwards

; --------------------------------
; $00 - used to store adder for movement, also used as adder for platform
; $01 - used to store maximum value for secondary counter

MoveFlyGreenPTroopa:
	JSR XMoveCntr_GreenPTroopa                   ; do sub to increment primary and secondary counters
	JSR MoveWithXMCntrs                          ; do sub to move green paratroopa accordingly, and horizontally
	LDY #$01                                     ; set Y to move green paratroopa down
	LDA FrameCounter
	AND #%00000011                               ; check frame counter 2 LSB for any bits set
	BNE NoMGPT                                   ; branch to leave if set to move up/down every fourth frame
	LDA FrameCounter
	AND #%01000000                               ; check frame counter for d6 set
	BNE YSway                                    ; branch to move green paratroopa down if set
	LDY #$ff                                     ; otherwise set Y to move green paratroopa up
YSway:
	STY $00                                      ; store adder here
	LDA Enemy_Y_Position,x
	CLC                                          ; add or subtract from vertical position
	ADC $00                                      ; to give green paratroopa a wavy flight
	STA Enemy_Y_Position,x
NoMGPT:
	RTS                                          ; leave!

XMoveCntr_GreenPTroopa:
	LDA #$13                                     ; load preset maximum value for secondary counter

XMoveCntr_Platform:
	STA $01                                      ; store value here
	LDA FrameCounter
	AND #%00000011                               ; branch to leave if not on
	BNE NoIncXM                                  ; every fourth frame
	LDY XMoveSecondaryCounter,x                  ; get secondary counter
	LDA XMovePrimaryCounter,x                    ; get primary counter
	LSR
	BCS DecSeXM                                  ; if d0 of primary counter set, branch elsewhere
	CPY $01                                      ; compare secondary counter to preset maximum value
	BEQ IncPXM                                   ; if equal, branch ahead of this part
	INC XMoveSecondaryCounter,x                  ; increment secondary counter and leave
NoIncXM:
	RTS
IncPXM:
	INC XMovePrimaryCounter,x                    ; increment primary counter and leave
	RTS
DecSeXM:
	TYA                                          ; put secondary counter in A
	BEQ IncPXM                                   ; if secondary counter at zero, branch back
	DEC XMoveSecondaryCounter,x                  ; otherwise decrement secondary counter and leave
	RTS

MoveWithXMCntrs:
	LDA XMoveSecondaryCounter,x                  ; save secondary counter to stack
	PHA
	LDY #$01                                     ; set value here by default
	LDA XMovePrimaryCounter,x
	AND #%00000010                               ; if d1 of primary counter is
	BNE XMRight                                  ; set, branch ahead of this part here
	LDA XMoveSecondaryCounter,x
	EOR #$ff                                     ; otherwise change secondary
	CLC                                          ; counter to two's compliment
	ADC #$01
	STA XMoveSecondaryCounter,x
	LDY #$02                                     ; load alternate value here
XMRight:
	STY Enemy_MovingDir,x                        ; store as moving direction
	JSR MoveEnemyHorizontally
	STA $00                                      ; save value obtained from sub here
	PLA                                          ; get secondary counter from stack
	STA XMoveSecondaryCounter,x                  ; and return to original place
	RTS

; --------------------------------

BlooberBitmasks:
	.db %00111111, %00000011

MoveBloober:
	LDA Enemy_State,x
	AND #%00100000                               ; check enemy state for d5 set
	BNE MoveDefeatedBloober                      ; branch if set to move defeated bloober
	LDY SecondaryHardMode                        ; use secondary hard mode flag as offset
	LDA PseudoRandomBitReg+1,x                   ; get LSFR
	AND BlooberBitmasks,y                        ; mask out bits in LSFR using bitmask loaded with offset
	BNE BlooberSwim                              ; if any bits set, skip ahead to make swim
	TXA
	LSR                                          ; check to see if on second or fourth slot (1 or 3)
	BCC FBLeft                                   ; if not, branch to figure out moving direction
	LDY Player_MovingDir                         ; otherwise, load player's moving direction and
	BCS SBMDir                                   ; do an unconditional branch to set
FBLeft:
	LDY #$02                                     ; set left moving direction by default
	JSR PlayerEnemyDiff                          ; get horizontal difference between player and bloober
	BPL SBMDir                                   ; if enemy to the right of player, keep left
	DEY                                          ; otherwise decrement to set right moving direction
SBMDir:
	STY Enemy_MovingDir,x                        ; set moving direction of bloober, then continue on here

BlooberSwim:
	JSR ProcSwimmingB                            ; execute sub to make bloober swim characteristically
	LDA Enemy_Y_Position,x                       ; get vertical coordinate
	SEC
	SBC Enemy_Y_MoveForce,x                      ; subtract movement force
	CMP #$20                                     ; check to see if position is above edge of status bar
	BCC SwimX                                    ; if so, don't do it
	STA Enemy_Y_Position,x                       ; otherwise, set new vertical position, make bloober swim
SwimX:
	LDY Enemy_MovingDir,x                        ; check moving direction
	DEY
	BNE LeftSwim                                 ; if moving to the left, branch to second part
	LDA Enemy_X_Position,x
	CLC                                          ; add movement speed to horizontal coordinate
	ADC BlooperMoveSpeed,x
	STA Enemy_X_Position,x                       ; store result as new horizontal coordinate
	LDA Enemy_PageLoc,x
	ADC #$00                                     ; add carry to page location
	STA Enemy_PageLoc,x                          ; store as new page location and leave
	RTS

LeftSwim:
	LDA Enemy_X_Position,x
	SEC                                          ; subtract movement speed from horizontal coordinate
	SBC BlooperMoveSpeed,x
	STA Enemy_X_Position,x                       ; store result as new horizontal coordinate
	LDA Enemy_PageLoc,x
	SBC #$00                                     ; subtract borrow from page location
	STA Enemy_PageLoc,x                          ; store as new page location and leave
	RTS

MoveDefeatedBloober:
	JMP MoveEnemySlowVert                        ; jump to move defeated bloober downwards

ProcSwimmingB:
	LDA BlooperMoveCounter,x                     ; get enemy's movement counter
	AND #%00000010                               ; check for d1 set
	BNE ChkForFloatdown                          ; branch if set
	LDA FrameCounter
	AND #%00000111                               ; get 3 LSB of frame counter
	PHA                                          ; and save it to the stack
	LDA BlooperMoveCounter,x                     ; get enemy's movement counter
	LSR                                          ; check for d0 set
	BCS SlowSwim                                 ; branch if set
	PLA                                          ; pull 3 LSB of frame counter from the stack
	BNE BSwimE                                   ; branch to leave, execute code only every eighth frame
	LDA Enemy_Y_MoveForce,x
	CLC                                          ; add to movement force to speed up swim
	ADC #$01
	STA Enemy_Y_MoveForce,x                      ; set movement force
	STA BlooperMoveSpeed,x                       ; set as movement speed
	CMP #$02
	BNE BSwimE                                   ; if certain horizontal speed, branch to leave
	INC BlooperMoveCounter,x                     ; otherwise increment movement counter
BSwimE:
	RTS

SlowSwim:
	PLA                                          ; pull 3 LSB of frame counter from the stack
	BNE NoSSw                                    ; branch to leave, execute code only every eighth frame
	LDA Enemy_Y_MoveForce,x
	SEC                                          ; subtract from movement force to slow swim
	SBC #$01
	STA Enemy_Y_MoveForce,x                      ; set movement force
	STA BlooperMoveSpeed,x                       ; set as movement speed
	BNE NoSSw                                    ; if any speed, branch to leave
	INC BlooperMoveCounter,x                     ; otherwise increment movement counter
	LDA #$02
	STA EnemyIntervalTimer,x                     ; set enemy's timer
NoSSw:
	RTS                                          ; leave

ChkForFloatdown:
	LDA EnemyIntervalTimer,x                     ; get enemy timer
	BEQ ChkNearPlayer                            ; branch if expired

Floatdown:
	LDA FrameCounter                             ; get frame counter
	LSR                                          ; check for d0 set
	BCS NoFD                                     ; branch to leave on every other frame
	INC Enemy_Y_Position,x                       ; otherwise increment vertical coordinate
NoFD:
	RTS                                          ; leave

ChkNearPlayer:
	LDA Enemy_Y_Position,x                       ; get vertical coordinate
	ADC #$10                                     ; add sixteen pixels
	CMP Player_Y_Position                        ; compare result with player's vertical coordinate
	BCC Floatdown                                ; if modified vertical less than player's, branch
	LDA #$00
	STA BlooperMoveCounter,x                     ; otherwise nullify movement counter
	RTS

; --------------------------------

MoveBulletBill:
	LDA Enemy_State,x                            ; check bullet bill's enemy object state for d5 set
	AND #%00100000
	BEQ NotDefB                                  ; if not set, continue with movement code
	JMP MoveJ_EnemyVertically                    ; otherwise jump to move defeated bullet bill downwards
NotDefB:
	LDA #$e8                                     ; set bullet bill's horizontal speed
	STA Enemy_X_Speed,x                          ; and move it accordingly (note: this bullet bill
	JMP MoveEnemyHorizontally                    ; object occurs in frenzy object $17, not from cannons)

; --------------------------------
; $02 - used to hold preset values
; $03 - used to hold enemy state

SwimCCXMoveData:
	.db $40, $80
	.db $04, $04                                 ; residual data, not used

MoveSwimmingCheepCheep:
	LDA Enemy_State,x                            ; check cheep-cheep's enemy object state
	AND #%00100000                               ; for d5 set
	BEQ CCSwim                                   ; if not set, continue with movement code
	JMP MoveEnemySlowVert                        ; otherwise jump to move defeated cheep-cheep downwards
CCSwim:
	STA $03                                      ; save enemy state in $03
	LDA Enemy_ID,x                               ; get enemy identifier
	SEC
	SBC #$0a                                     ; subtract ten for cheep-cheep identifiers
	TAY                                          ; use as offset
	LDA SwimCCXMoveData,y                        ; load value here
	STA $02
	LDA Enemy_X_MoveForce,x                      ; load horizontal force
	SEC
	SBC $02                                      ; subtract preset value from horizontal force
	STA Enemy_X_MoveForce,x                      ; store as new horizontal force
	LDA Enemy_X_Position,x                       ; get horizontal coordinate
	SBC #$00                                     ; subtract borrow (thus moving it slowly)
	STA Enemy_X_Position,x                       ; and save as new horizontal coordinate
	LDA Enemy_PageLoc,x
	SBC #$00                                     ; subtract borrow again, this time from the
	STA Enemy_PageLoc,x                          ; page location, then save
	LDA #$20
	STA $02                                      ; save new value here
	CPX #$02                                     ; check enemy object offset
	BCC ExSwCC                                   ; if in first or second slot, branch to leave
	LDA CheepCheepMoveMFlag,x                    ; check movement flag
	CMP #$10                                     ; if movement speed set to $00,
	BCC CCSwimUpwards                            ; branch to move upwards
	LDA Enemy_YMF_Dummy,x
	CLC
	ADC $02                                      ; add preset value to dummy variable to get carry
	STA Enemy_YMF_Dummy,x                        ; and save dummy
	LDA Enemy_Y_Position,x                       ; get vertical coordinate
	ADC $03                                      ; add carry to it plus enemy state to slowly move it downwards
	STA Enemy_Y_Position,x                       ; save as new vertical coordinate
	LDA Enemy_Y_HighPos,x
	ADC #$00                                     ; add carry to page location and
	JMP ChkSwimYPos                              ; jump to end of movement code

CCSwimUpwards:
	LDA Enemy_YMF_Dummy,x
	SEC
	SBC $02                                      ; subtract preset value to dummy variable to get borrow
	STA Enemy_YMF_Dummy,x                        ; and save dummy
	LDA Enemy_Y_Position,x                       ; get vertical coordinate
	SBC $03                                      ; subtract borrow to it plus enemy state to slowly move it upwards
	STA Enemy_Y_Position,x                       ; save as new vertical coordinate
	LDA Enemy_Y_HighPos,x
	SBC #$00                                     ; subtract borrow from page location

ChkSwimYPos:
	STA Enemy_Y_HighPos,x                        ; save new page location here
	LDY #$00                                     ; load movement speed to upwards by default
	LDA Enemy_Y_Position,x                       ; get vertical coordinate
	SEC
	SBC CheepCheepOrigYPos,x                     ; subtract original coordinate from current
	BPL YPDiff                                   ; if result positive, skip to next part
	LDY #$10                                     ; otherwise load movement speed to downwards
	EOR #$ff
	CLC                                          ; get two's compliment of result
	ADC #$01                                     ; to obtain total difference of original vs. current
YPDiff:
	CMP #$0f                                     ; if difference between original vs. current vertical
	BCC ExSwCC                                   ; coordinates < 15 pixels, leave movement speed alone
	TYA
	STA CheepCheepMoveMFlag,x                    ; otherwise change movement speed
ExSwCC:
	RTS                                          ; leave

; --------------------------------
; $00 - used as counter for firebar parts
; $01 - used for oscillated high byte of spin state or to hold horizontal adder
; $02 - used for oscillated high byte of spin state or to hold vertical adder
; $03 - used for mirror data
; $04 - used to store player's sprite 1 X coordinate
; $05 - used to evaluate mirror data
; $06 - used to store either screen X coordinate or sprite data offset
; $07 - used to store screen Y coordinate
; $ed - used to hold maximum length of firebar
; $ef - used to hold high byte of spinstate

; horizontal adder is at first byte + high byte of spinstate,
; vertical adder is same + 8 bytes, two's compliment
; if greater than $08 for proper oscillation
FirebarPosLookupTbl:
	.db $00, $01, $03, $04, $05, $06, $07, $07, $08
	.db $00, $03, $06, $09, $0b, $0d, $0e, $0f, $10
	.db $00, $04, $09, $0d, $10, $13, $16, $17, $18
	.db $00, $06, $0c, $12, $16, $1a, $1d, $1f, $20
	.db $00, $07, $0f, $16, $1c, $21, $25, $27, $28
	.db $00, $09, $12, $1b, $21, $27, $2c, $2f, $30
	.db $00, $0b, $15, $1f, $27, $2e, $33, $37, $38
	.db $00, $0c, $18, $24, $2d, $35, $3b, $3e, $40
	.db $00, $0e, $1b, $28, $32, $3b, $42, $46, $48
	.db $00, $0f, $1f, $2d, $38, $42, $4a, $4e, $50
	.db $00, $11, $22, $31, $3e, $49, $51, $56, $58

FirebarMirrorData:
	.db $01, $03, $02, $00

FirebarTblOffsets:
	.db $00, $09, $12, $1b, $24, $2d
	.db $36, $3f, $48, $51, $5a, $63

FirebarYPos:
	.db $0c, $18

ProcFirebar:
	JSR GetEnemyOffscreenBits                    ; get offscreen information
	LDA Enemy_OffscreenBits                      ; check for d3 set
	AND #%00001000                               ; if so, branch to leave
	BNE SkipFBar
	LDA TimerControl                             ; if master timer control set, branch
	BNE SusFbar                                  ; ahead of this part
	LDA FirebarSpinSpeed,x                       ; load spinning speed of firebar
	JSR FirebarSpin                              ; modify current spinstate
	AND #%00011111                               ; mask out all but 5 LSB
	STA FirebarSpinState_High,x                  ; and store as new high byte of spinstate
SusFbar:
	LDA FirebarSpinState_High,x                  ; get high byte of spinstate
	LDY Enemy_ID,x                               ; check enemy identifier
	CPY #$1f
	BCC SetupGFB                                 ; if < $1f (long firebar), branch
	CMP #$08                                     ; check high byte of spinstate
	BEQ SkpFSte                                  ; if eight, branch to change
	CMP #$18
	BNE SetupGFB                                 ; if not at twenty-four branch to not change
SkpFSte:
	CLC
	ADC #$01                                     ; add one to spinning thing to avoid horizontal state
	STA FirebarSpinState_High,x
SetupGFB:
	STA $ef                                      ; save high byte of spinning thing, modified or otherwise
	JSR RelativeEnemyPosition                    ; get relative coordinates to screen
	JSR GetFirebarPosition                       ; do a sub here (residual, too early to be used now)
	LDY Enemy_SprDataOffset,x                    ; get OAM data offset
	LDA Enemy_Rel_YPos                           ; get relative vertical coordinate
	STA Sprite_Y_Position,y                      ; store as Y in OAM data
	STA $07                                      ; also save here
	LDA Enemy_Rel_XPos                           ; get relative horizontal coordinate
	STA Sprite_X_Position,y                      ; store as X in OAM data
	STA $06                                      ; also save here
	LDA #$01
	STA $00                                      ; set $01 value here (not necessary)
	JSR FirebarCollision                         ; draw fireball part and do collision detection
	LDY #$05                                     ; load value for short firebars by default
	LDA Enemy_ID,x
	CMP #$1f                                     ; are we doing a long firebar?
	BCC SetMFbar                                 ; no, branch then
	LDY #$0b                                     ; otherwise load value for long firebars
SetMFbar:
	STY $ed                                      ; store maximum value for length of firebars
	LDA #$00
	STA $00                                      ; initialize counter here
DrawFbar:
	LDA $ef                                      ; load high byte of spinstate
	JSR GetFirebarPosition                       ; get fireball position data depending on firebar part
	JSR DrawFirebar_Collision                    ; position it properly, draw it and do collision detection
	LDA $00                                      ; check which firebar part
	CMP #$04
	BNE NextFbar
	LDY DuplicateObj_Offset                      ; if we arrive at fifth firebar part,
	LDA Enemy_SprDataOffset,y                    ; get offset from long firebar and load OAM data offset
	STA $06                                      ; using long firebar offset, then store as new one here
NextFbar:
	INC $00                                      ; move onto the next firebar part
	LDA $00
	CMP $ed                                      ; if we end up at the maximum part, go on and leave
	BCC DrawFbar                                 ; otherwise go back and do another
SkipFBar:
	RTS

DrawFirebar_Collision:
	LDA $03                                      ; store mirror data elsewhere
	STA $05
	LDY $06                                      ; load OAM data offset for firebar
	LDA $01                                      ; load horizontal adder we got from position loader
	LSR $05                                      ; shift LSB of mirror data
	BCS AddHA                                    ; if carry was set, skip this part
	EOR #$ff
	ADC #$01                                     ; otherwise get two's compliment of horizontal adder
AddHA:
	CLC                                          ; add horizontal coordinate relative to screen to
	ADC Enemy_Rel_XPos                           ; horizontal adder, modified or otherwise
	STA Sprite_X_Position,y                      ; store as X coordinate here
	STA $06                                      ; store here for now, note offset is saved in Y still
	CMP Enemy_Rel_XPos                           ; compare X coordinate of sprite to original X of firebar
	BCS SubtR1                                   ; if sprite coordinate => original coordinate, branch
	LDA Enemy_Rel_XPos
	SEC                                          ; otherwise subtract sprite X from the
	SBC $06                                      ; original one and skip this part
	JMP ChkFOfs
SubtR1:
	SEC                                          ; subtract original X from the
	SBC Enemy_Rel_XPos                           ; current sprite X
ChkFOfs:
	CMP #$59                                     ; if difference of coordinates within a certain range,
	BCC VAHandl                                  ; continue by handling vertical adder
	LDA #$f8                                     ; otherwise, load offscreen Y coordinate
	BNE SetVFbr                                  ; and unconditionally branch to move sprite offscreen
VAHandl:
	LDA Enemy_Rel_YPos                           ; if vertical relative coordinate offscreen,
	CMP #$f8                                     ; skip ahead of this part and write into sprite Y coordinate
	BEQ SetVFbr
	LDA $02                                      ; load vertical adder we got from position loader
	LSR $05                                      ; shift LSB of mirror data one more time
	BCS AddVA                                    ; if carry was set, skip this part
	EOR #$ff
	ADC #$01                                     ; otherwise get two's compliment of second part
AddVA:
	CLC                                          ; add vertical coordinate relative to screen to
	ADC Enemy_Rel_YPos                           ; the second data, modified or otherwise
SetVFbr:
	STA Sprite_Y_Position,y                      ; store as Y coordinate here
	STA $07                                      ; also store here for now

FirebarCollision:
	JSR DrawFirebar                              ; run sub here to draw current tile of firebar
	TYA                                          ; return OAM data offset and save
	PHA                                          ; to the stack for now
	LDA StarInvincibleTimer                      ; if star mario invincibility timer
	ORA TimerControl                             ; or master timer controls set
	BNE NoColFB                                  ; then skip all of this
	STA $05                                      ; otherwise initialize counter
	LDY Player_Y_HighPos
	DEY                                          ; if player's vertical high byte offscreen,
	BNE NoColFB                                  ; skip all of this
	LDY Player_Y_Position                        ; get player's vertical position
	LDA PlayerSize                               ; get player's size
	BNE AdjSm                                    ; if player small, branch to alter variables
	LDA CrouchingFlag
	BEQ BigJp                                    ; if player big and not crouching, jump ahead
AdjSm:
	INC $05                                      ; if small or big but crouching, execute this part
	INC $05                                      ; first increment our counter twice (setting $02 as flag)
	TYA
	CLC                                          ; then add 24 pixels to the player's
	ADC #$18                                     ; vertical coordinate
	TAY
BigJp:
	TYA                                          ; get vertical coordinate, altered or otherwise, from Y
FBCLoop:
	SEC                                          ; subtract vertical position of firebar
	SBC $07                                      ; from the vertical coordinate of the player
	BPL ChkVFBD                                  ; if player lower on the screen than firebar,
	EOR #$ff                                     ; skip two's compliment part
	CLC                                          ; otherwise get two's compliment
	ADC #$01
ChkVFBD:
	CMP #$08                                     ; if difference => 8 pixels, skip ahead of this part
	BCS Chk2Ofs
	LDA $06                                      ; if firebar on far right on the screen, skip this,
	CMP #$f0                                     ; because, really, what's the point?
	BCS Chk2Ofs
	LDA Sprite_X_Position+4                      ; get OAM X coordinate for sprite #1
	CLC
	ADC #$04                                     ; add four pixels
	STA $04                                      ; store here
	SEC                                          ; subtract horizontal coordinate of firebar
	SBC $06                                      ; from the X coordinate of player's sprite 1
	BPL ChkFBCl                                  ; if modded X coordinate to the right of firebar
	EOR #$ff                                     ; skip two's compliment part
	CLC                                          ; otherwise get two's compliment
	ADC #$01
ChkFBCl:
	CMP #$08                                     ; if difference < 8 pixels, collision, thus branch
	BCC ChgSDir                                  ; to process
Chk2Ofs:
	LDA $05                                      ; if value of $02 was set earlier for whatever reason,
	CMP #$02                                     ; branch to increment OAM offset and leave, no collision
	BEQ NoColFB
	LDY $05                                      ; otherwise get temp here and use as offset
	LDA Player_Y_Position
	CLC
	ADC FirebarYPos,y                            ; add value loaded with offset to player's vertical coordinate
	INC $05                                      ; then increment temp and jump back
	JMP FBCLoop
ChgSDir:
	LDX #$01                                     ; set movement direction by default
	LDA $04                                      ; if OAM X coordinate of player's sprite 1
	CMP $06                                      ; is greater than horizontal coordinate of firebar
	BCS SetSDir                                  ; then do not alter movement direction
	INX                                          ; otherwise increment it
SetSDir:
	STX Enemy_MovingDir                          ; store movement direction here
	LDX #$00
	LDA $00                                      ; save value written to $00 to stack
	PHA
	JSR InjurePlayer                             ; perform sub to hurt or kill player
	PLA
	STA $00                                      ; get value of $00 from stack
NoColFB:
	PLA                                          ; get OAM data offset
	CLC                                          ; add four to it and save
	ADC #$04
	STA $06
	LDX ObjectOffset                             ; get enemy object buffer offset and leave
	RTS

GetFirebarPosition:
	PHA                                          ; save high byte of spinstate to the stack
	AND #%00001111                               ; mask out low nybble
	CMP #$09
	BCC GetHAdder                                ; if lower than $09, branch ahead
	EOR #%00001111                               ; otherwise get two's compliment to oscillate
	CLC
	ADC #$01
GetHAdder:
	STA $01                                      ; store result, modified or not, here
	LDY $00                                      ; load number of firebar ball where we're at
	LDA FirebarTblOffsets,y                      ; load offset to firebar position data
	CLC
	ADC $01                                      ; add oscillated high byte of spinstate
	TAY                                          ; to offset here and use as new offset
	LDA FirebarPosLookupTbl,y                    ; get data here and store as horizontal adder
	STA $01
	PLA                                          ; pull whatever was in A from the stack
	PHA                                          ; save it again because we still need it
	CLC
	ADC #$08                                     ; add eight this time, to get vertical adder
	AND #%00001111                               ; mask out high nybble
	CMP #$09                                     ; if lower than $09, branch ahead
	BCC GetVAdder
	EOR #%00001111                               ; otherwise get two's compliment
	CLC
	ADC #$01
GetVAdder:
	STA $02                                      ; store result here
	LDY $00
	LDA FirebarTblOffsets,y                      ; load offset to firebar position data again
	CLC
	ADC $02                                      ; this time add value in $02 to offset here and use as offset
	TAY
	LDA FirebarPosLookupTbl,y                    ; get data here and store as vertica adder
	STA $02
	PLA                                          ; pull out whatever was in A one last time
	LSR                                          ; divide by eight or shift three to the right
	LSR
	LSR
	TAY                                          ; use as offset
	LDA FirebarMirrorData,y                      ; load mirroring data here
	STA $03                                      ; store
	RTS

; --------------------------------

PRandomSubtracter:
	.db $f8, $a0, $70, $bd, $00

FlyCCBPriority:
	.db $20, $20, $20, $00, $00

MoveFlyingCheepCheep:
	LDA Enemy_State,x                            ; check cheep-cheep's enemy state
	AND #%00100000                               ; for d5 set
	BEQ FlyCC                                    ; branch to continue code if not set
	LDA #$00
	STA Enemy_SprAttrib,x                        ; otherwise clear sprite attributes
	JMP MoveJ_EnemyVertically                    ; and jump to move defeated cheep-cheep downwards
FlyCC:
	JSR MoveEnemyHorizontally                    ; move cheep-cheep horizontally based on speed and force
	LDY #$0d                                     ; set vertical movement amount
	LDA #$05                                     ; set maximum speed
	JSR SetXMoveAmt                              ; branch to impose gravity on flying cheep-cheep
	LDA Enemy_Y_MoveForce,x
	LSR                                          ; get vertical movement force and
	LSR                                          ; move high nybble to low
	LSR
	LSR
	TAY                                          ; save as offset (note this tends to go into reach of code)
	LDA Enemy_Y_Position,x                       ; get vertical position
	SEC                                          ; subtract pseudorandom value based on offset from position
	SBC PRandomSubtracter,y
	BPL AddCCF                                   ; if result within top half of screen, skip this part
	EOR #$ff
	CLC                                          ; otherwise get two's compliment
	ADC #$01
AddCCF:
	CMP #$08                                     ; if result or two's compliment greater than eight,
	BCS BPGet                                    ; skip to the end without changing movement force
	LDA Enemy_Y_MoveForce,x
	CLC
	ADC #$10                                     ; otherwise add to it
	STA Enemy_Y_MoveForce,x
	LSR                                          ; move high nybble to low again
	LSR
	LSR
	LSR
	TAY
BPGet:
	LDA FlyCCBPriority,y                         ; load bg priority data and store (this is very likely
	STA Enemy_SprAttrib,x                        ; broken or residual code, value is overwritten before
	RTS                                          ; drawing it next frame), then leave

; --------------------------------
; $00 - used to hold horizontal difference
; $01-$03 - used to hold difference adjusters

LakituDiffAdj:
	.db $15, $30, $40

MoveLakitu:
	LDA Enemy_State,x                            ; check lakitu's enemy state
	AND #%00100000                               ; for d5 set
	BEQ ChkLS                                    ; if not set, continue with code
	JMP MoveD_EnemyVertically                    ; otherwise jump to move defeated lakitu downwards
ChkLS:
	LDA Enemy_State,x                            ; if lakitu's enemy state not set at all,
	BEQ Fr12S                                    ; go ahead and continue with code
	LDA #$00
	STA LakituMoveDirection,x                    ; otherwise initialize moving direction to move to left
	STA EnemyFrenzyBuffer                        ; initialize frenzy buffer
	LDA #$10
	BNE SetLSpd                                  ; load horizontal speed and do unconditional branch
Fr12S:
	LDA #Spiny
	STA EnemyFrenzyBuffer                        ; set spiny identifier in frenzy buffer
	LDY #$02
LdLDa:
	LDA LakituDiffAdj,y                          ; load values
	STA $0001,y                                  ; store in zero page
	DEY
	BPL LdLDa                                    ; do this until all values are stired
	JSR PlayerLakituDiff                         ; execute sub to set speed and create spinys
SetLSpd:
	STA LakituMoveSpeed,x                        ; set movement speed returned from sub
	LDY #$01                                     ; set moving direction to right by default
	LDA LakituMoveDirection,x
	AND #$01                                     ; get LSB of moving direction
	BNE SetLMov                                  ; if set, branch to the end to use moving direction
	LDA LakituMoveSpeed,x
	EOR #$ff                                     ; get two's compliment of moving speed
	CLC
	ADC #$01
	STA LakituMoveSpeed,x                        ; store as new moving speed
	INY                                          ; increment moving direction to left
SetLMov:
	STY Enemy_MovingDir,x                        ; store moving direction
	JMP MoveEnemyHorizontally                    ; move lakitu horizontally

PlayerLakituDiff:
	LDY #$00                                     ; set Y for default value
	JSR PlayerEnemyDiff                          ; get horizontal difference between enemy and player
	BPL ChkLakDif                                ; branch if enemy is to the right of the player
	INY                                          ; increment Y for left of player
	LDA $00
	EOR #$ff                                     ; get two's compliment of low byte of horizontal difference
	CLC
	ADC #$01                                     ; store two's compliment as horizontal difference
	STA $00
ChkLakDif:
	LDA $00                                      ; get low byte of horizontal difference
	CMP #$3c                                     ; if within a certain distance of player, branch
	BCC ChkPSpeed
	LDA #$3c                                     ; otherwise set maximum distance
	STA $00
	LDA Enemy_ID,x                               ; check if lakitu is in our current enemy slot
	CMP #Lakitu
	BNE ChkPSpeed                                ; if not, branch elsewhere
	TYA                                          ; compare contents of Y, now in A
	CMP LakituMoveDirection,x                    ; to what is being used as horizontal movement direction
	BEQ ChkPSpeed                                ; if moving toward the player, branch, do not alter
	LDA LakituMoveDirection,x                    ; if moving to the left beyond maximum distance,
	BEQ SetLMovD                                 ; branch and alter without delay
	DEC LakituMoveSpeed,x                        ; decrement horizontal speed
	LDA LakituMoveSpeed,x                        ; if horizontal speed not yet at zero, branch to leave
	BNE ExMoveLak
SetLMovD:
	TYA                                          ; set horizontal direction depending on horizontal
	STA LakituMoveDirection,x                    ; difference between enemy and player if necessary
ChkPSpeed:
	LDA $00
	AND #%00111100                               ; mask out all but four bits in the middle
	LSR                                          ; divide masked difference by four
	LSR
	STA $00                                      ; store as new value
	LDY #$00                                     ; init offset
	LDA Player_X_Speed
	BEQ SubDifAdj                                ; if player not moving horizontally, branch
	LDA ScrollAmount
	BEQ SubDifAdj                                ; if scroll speed not set, branch to same place
	INY                                          ; otherwise increment offset
	LDA Player_X_Speed
	CMP #$19                                     ; if player not running, branch
	BCC ChkSpinyO
	LDA ScrollAmount
	CMP #$02                                     ; if scroll speed below a certain amount, branch
	BCC ChkSpinyO                                ; to same place
	INY                                          ; otherwise increment once more
ChkSpinyO:
	LDA Enemy_ID,x                               ; check for spiny object
	CMP #Spiny
	BNE ChkEmySpd                                ; branch if not found
	LDA Player_X_Speed                           ; if player not moving, skip this part
	BNE SubDifAdj
ChkEmySpd:
	LDA Enemy_Y_Speed,x                          ; check vertical speed
	BNE SubDifAdj                                ; branch if nonzero
	LDY #$00                                     ; otherwise reinit offset
SubDifAdj:
	LDA $0001,y                                  ; get one of three saved values from earlier
	LDY $00                                      ; get saved horizontal difference
SPixelLak:
	SEC                                          ; subtract one for each pixel of horizontal difference
	SBC #$01                                     ; from one of three saved values
	DEY
	BPL SPixelLak                                ; branch until all pixels are subtracted, to adjust difference
ExMoveLak:
	RTS                                          ; leave!!!

; -------------------------------------------------------------------------------------
; $04-$05 - used to store name table address in little endian order

BridgeCollapseData:
	.db $1a                                      ; axe
	.db $58                                      ; chain
	.db $98, $96, $94, $92, $90, $8e, $8c        ; bridge
	.db $8a, $88, $86, $84, $82, $80

BridgeCollapse:
	LDX BowserFront_Offset                       ; get enemy offset for bowser
	LDA Enemy_ID,x                               ; check enemy object identifier for bowser
	CMP #Bowser                                  ; if not found, branch ahead,
	BNE SetM2                                    ; metatile removal not necessary
	STX ObjectOffset                             ; store as enemy offset here
	LDA Enemy_State,x                            ; if bowser in normal state, skip all of this
	BEQ RemoveBridge
	AND #%01000000                               ; if bowser's state has d6 clear, skip to silence music
	BEQ SetM2
	LDA Enemy_Y_Position,x                       ; check bowser's vertical coordinate
	CMP #$e0                                     ; if bowser not yet low enough, skip this part ahead
	BCC MoveD_Bowser
SetM2:
	LDA #Silence                                 ; silence music
	STA EventMusicQueue
	INC OperMode_Task                            ; move onto next secondary mode in autoctrl mode
	JMP KillAllEnemies                           ; jump to empty all enemy slots and then leave

MoveD_Bowser:
	JSR MoveEnemySlowVert                        ; do a sub to move bowser downwards
	JMP BowserGfxHandler                         ; jump to draw bowser's front and rear, then leave

RemoveBridge:
	DEC BowserFeetCounter                        ; decrement timer to control bowser's feet
	BNE NoBFall                                  ; if not expired, skip all of this
	LDA #$04
	STA BowserFeetCounter                        ; otherwise, set timer now
	LDA BowserBodyControls
	EOR #$01                                     ; invert bit to control bowser's feet
	STA BowserBodyControls
	LDA #$22                                     ; put high byte of name table address here for now
	STA $05
	LDY BridgeCollapseOffset                     ; get bridge collapse offset here
	LDA BridgeCollapseData,y                     ; load low byte of name table address and store here
	STA $04
	LDY VRAM_Buffer1_Offset                      ; increment vram buffer offset
	INY
	LDX #$0c                                     ; set offset for tile data for sub to draw blank metatile
	JSR RemBridge                                ; do sub here to remove bowser's bridge metatiles
	LDX ObjectOffset                             ; get enemy offset
	JSR MoveVOffset                              ; set new vram buffer offset
	LDA #Sfx_Blast                               ; load the fireworks/gunfire sound into the square 2 sfx
	STA Square2SoundQueue                        ; queue while at the same time loading the brick
	LDA #Sfx_BrickShatter                        ; shatter sound into the noise sfx queue thus
	STA NoiseSoundQueue                          ; producing the unique sound of the bridge collapsing
	INC BridgeCollapseOffset                     ; increment bridge collapse offset
	LDA BridgeCollapseOffset
	CMP #$0f                                     ; if bridge collapse offset has not yet reached
	BNE NoBFall                                  ; the end, go ahead and skip this part
	JSR InitVStf                                 ; initialize whatever vertical speed bowser has
	LDA #%01000000
	STA Enemy_State,x                            ; set bowser's state to one of defeated states (d6 set)
	LDA #Sfx_BowserFall
	STA Square2SoundQueue                        ; play bowser defeat sound
NoBFall:
	JMP BowserGfxHandler                         ; jump to code that draws bowser

; --------------------------------

PRandomRange:
	.db $21, $41, $11, $31

RunBowser:
	LDA Enemy_State,x                            ; if d5 in enemy state is not set
	AND #%00100000                               ; then branch elsewhere to run bowser
	BEQ BowserControl
	LDA Enemy_Y_Position,x                       ; otherwise check vertical position
	CMP #$e0                                     ; if above a certain point, branch to move defeated bowser
	BCC MoveD_Bowser                             ; otherwise proceed to KillAllEnemies

KillAllEnemies:
	LDX #$04                                     ; start with last enemy slot
KillLoop:
	JSR EraseEnemyObject                         ; branch to kill enemy objects
	DEX                                          ; move onto next enemy slot
	BPL KillLoop                                 ; do this until all slots are emptied
	STA EnemyFrenzyBuffer                        ; empty frenzy buffer
	LDX ObjectOffset                             ; get enemy object offset and leave
	RTS

BowserControl:
	LDA #$00
	STA EnemyFrenzyBuffer                        ; empty frenzy buffer
	LDA TimerControl                             ; if master timer control not set,
	BEQ ChkMouth                                 ; skip jump and execute code here
	JMP SkipToFB                                 ; otherwise, jump over a bunch of code
ChkMouth:
	LDA BowserBodyControls                       ; check bowser's mouth
	BPL FeetTmr                                  ; if bit clear, go ahead with code here
	JMP HammerChk                                ; otherwise skip a whole section starting here
FeetTmr:
	DEC BowserFeetCounter                        ; decrement timer to control bowser's feet
	BNE ResetMDr                                 ; if not expired, skip this part
	LDA #$20                                     ; otherwise, reset timer
	STA BowserFeetCounter
	LDA BowserBodyControls                       ; and invert bit used
	EOR #%00000001                               ; to control bowser's feet
	STA BowserBodyControls
ResetMDr:
	LDA FrameCounter                             ; check frame counter
	AND #%00001111                               ; if not on every sixteenth frame, skip
	BNE B_FaceP                                  ; ahead to continue code
	LDA #$02                                     ; otherwise reset moving/facing direction every
	STA Enemy_MovingDir,x                        ; sixteen frames
B_FaceP:
	LDA EnemyFrameTimer,x                        ; if timer set here expired,
	BEQ GetPRCmp                                 ; branch to next section
	JSR PlayerEnemyDiff                          ; get horizontal difference between player and bowser,
	BPL GetPRCmp                                 ; and branch if bowser to the right of the player
	LDA #$01
	STA Enemy_MovingDir,x                        ; set bowser to move and face to the right
	LDA #$02
	STA BowserMovementSpeed                      ; set movement speed
	LDA #$20
	STA EnemyFrameTimer,x                        ; set timer here
	STA BowserFireBreathTimer                    ; set timer used for bowser's flame
	LDA Enemy_X_Position,x
	CMP #$c8                                     ; if bowser to the right past a certain point,
	BCS HammerChk                                ; skip ahead to some other section
GetPRCmp:
	LDA FrameCounter                             ; get frame counter
	AND #%00000011
	BNE HammerChk                                ; execute this code every fourth frame, otherwise branch
	LDA Enemy_X_Position,x
	CMP BowserOrigXPos                           ; if bowser not at original horizontal position,
	BNE GetDToO                                  ; branch to skip this part
	LDA PseudoRandomBitReg,x
	AND #%00000011                               ; get pseudorandom offset
	TAY
	LDA PRandomRange,y                           ; load value using pseudorandom offset
	STA MaxRangeFromOrigin                       ; and store here
GetDToO:
	LDA Enemy_X_Position,x
	CLC                                          ; add movement speed to bowser's horizontal
	ADC BowserMovementSpeed                      ; coordinate and save as new horizontal position
	STA Enemy_X_Position,x
	LDY Enemy_MovingDir,x
	CPY #$01                                     ; if bowser moving and facing to the right, skip ahead
	BEQ HammerChk
	LDY #$ff                                     ; set default movement speed here (move left)
	SEC                                          ; get difference of current vs. original
	SBC BowserOrigXPos                           ; horizontal position
	BPL CompDToO                                 ; if current position to the right of original, skip ahead
	EOR #$ff
	CLC                                          ; get two's compliment
	ADC #$01
	LDY #$01                                     ; set alternate movement speed here (move right)
CompDToO:
	CMP MaxRangeFromOrigin                       ; compare difference with pseudorandom value
	BCC HammerChk                                ; if difference < pseudorandom value, leave speed alone
	STY BowserMovementSpeed                      ; otherwise change bowser's movement speed
HammerChk:
	LDA EnemyFrameTimer,x                        ; if timer set here not expired yet, skip ahead to
	BNE MakeBJump                                ; some other section of code
	JSR MoveEnemySlowVert                        ; otherwise start by moving bowser downwards
	LDA WorldNumber                              ; check world number
	CMP #World6
	BCC SetHmrTmr                                ; if world 1-5, skip this part (not time to throw hammers yet)
	LDA FrameCounter
	AND #%00000011                               ; check to see if it's time to execute sub
	BNE SetHmrTmr                                ; if not, skip sub, otherwise
	JSR SpawnHammerObj                           ; execute sub on every fourth frame to spawn misc object (hammer)
SetHmrTmr:
	LDA Enemy_Y_Position,x                       ; get current vertical position
	CMP #$80                                     ; if still above a certain point
	BCC ChkFireB                                 ; then skip to world number check for flames
	LDA PseudoRandomBitReg,x
	AND #%00000011                               ; get pseudorandom offset
	TAY
	LDA PRandomRange,y                           ; get value using pseudorandom offset
	STA EnemyFrameTimer,x                        ; set for timer here
SkipToFB:
	JMP ChkFireB                                 ; jump to execute flames code
MakeBJump:
	CMP #$01                                     ; if timer not yet about to expire,
	BNE ChkFireB                                 ; skip ahead to next part
	DEC Enemy_Y_Position,x                       ; otherwise decrement vertical coordinate
	JSR InitVStf                                 ; initialize movement amount
	LDA #$fe
	STA Enemy_Y_Speed,x                          ; set vertical speed to move bowser upwards
ChkFireB:
	LDA WorldNumber                              ; check world number here
	CMP #World8                                  ; world 8?
	BEQ SpawnFBr                                 ; if so, execute this part here
	CMP #World6                                  ; world 6-7?
	BCS BowserGfxHandler                         ; if so, skip this part here
SpawnFBr:
	LDA BowserFireBreathTimer                    ; check timer here
	BNE BowserGfxHandler                         ; if not expired yet, skip all of this
	LDA #$20
	STA BowserFireBreathTimer                    ; set timer here
	LDA BowserBodyControls
	EOR #%10000000                               ; invert bowser's mouth bit to open
	STA BowserBodyControls                       ; and close bowser's mouth
	BMI ChkFireB                                 ; if bowser's mouth open, loop back
	JSR SetFlameTimer                            ; get timing for bowser's flame
	LDY SecondaryHardMode
	BEQ SetFBTmr                                 ; if secondary hard mode flag not set, skip this
	SEC
	SBC #$10                                     ; otherwise subtract from value in A
SetFBTmr:
	STA BowserFireBreathTimer                    ; set value as timer here
	LDA #BowserFlame                             ; put bowser's flame identifier
	STA EnemyFrenzyBuffer                        ; in enemy frenzy buffer

; --------------------------------

BowserGfxHandler:
	JSR ProcessBowserHalf                        ; do a sub here to process bowser's front
	LDY #$10                                     ; load default value here to position bowser's rear
	LDA Enemy_MovingDir,x                        ; check moving direction
	LSR
	BCC CopyFToR                                 ; if moving left, use default
	LDY #$f0                                     ; otherwise load alternate positioning value here
CopyFToR:
	TYA                                          ; move bowser's rear object position value to A
	CLC
	ADC Enemy_X_Position,x                       ; add to bowser's front object horizontal coordinate
	LDY DuplicateObj_Offset                      ; get bowser's rear object offset
	STA Enemy_X_Position,y                       ; store A as bowser's rear horizontal coordinate
	LDA Enemy_Y_Position,x
	CLC                                          ; add eight pixels to bowser's front object
	ADC #$08                                     ; vertical coordinate and store as vertical coordinate
	STA Enemy_Y_Position,y                       ; for bowser's rear
	LDA Enemy_State,x
	STA Enemy_State,y                            ; copy enemy state directly from front to rear
	LDA Enemy_MovingDir,x
	STA Enemy_MovingDir,y                        ; copy moving direction also
	LDA ObjectOffset                             ; save enemy object offset of front to stack
	PHA
	LDX DuplicateObj_Offset                      ; put enemy object offset of rear as current
	STX ObjectOffset
	LDA #Bowser                                  ; set bowser's enemy identifier
	STA Enemy_ID,x                               ; store in bowser's rear object
	JSR ProcessBowserHalf                        ; do a sub here to process bowser's rear
	PLA
	STA ObjectOffset                             ; get original enemy object offset
	TAX
	LDA #$00                                     ; nullify bowser's front/rear graphics flag
	STA BowserGfxFlag
ExBGfxH:
	RTS                                          ; leave!

ProcessBowserHalf:
	INC BowserGfxFlag                            ; increment bowser's graphics flag, then run subroutines
	JSR RunRetainerObj                           ; to get offscreen bits, relative position and draw bowser (finally!)
	LDA Enemy_State,x
	BNE ExBGfxH                                  ; if either enemy object not in normal state, branch to leave
	LDA #$0a
	STA Enemy_BoundBoxCtrl,x                     ; set bounding box size control
	JSR GetEnemyBoundBox                         ; get bounding box coordinates
	JMP PlayerEnemyCollision                     ; do player-to-enemy collision detection

; -------------------------------------------------------------------------------------
; $00 - used to hold movement force and tile number
; $01 - used to hold sprite attribute data

FlameTimerData:
	.db $bf, $40, $bf, $bf, $bf, $40, $40, $bf

SetFlameTimer:
	LDY BowserFlameTimerCtrl                     ; load counter as offset
	INC BowserFlameTimerCtrl                     ; increment
	LDA BowserFlameTimerCtrl                     ; mask out all but 3 LSB
	AND #%00000111                               ; to keep in range of 0-7
	STA BowserFlameTimerCtrl
	LDA FlameTimerData,y                         ; load value to be used then leave
ExFl:
	RTS

ProcBowserFlame:
	LDA TimerControl                             ; if master timer control flag set,
	BNE SetGfxF                                  ; skip all of this
	LDA #$40                                     ; load default movement force
	LDY SecondaryHardMode
	BEQ SFlmX                                    ; if secondary hard mode flag not set, use default
	LDA #$60                                     ; otherwise load alternate movement force to go faster
SFlmX:
	STA $00                                      ; store value here
	LDA Enemy_X_MoveForce,x
	SEC                                          ; subtract value from movement force
	SBC $00
	STA Enemy_X_MoveForce,x                      ; save new value
	LDA Enemy_X_Position,x
	SBC #$01                                     ; subtract one from horizontal position to move
	STA Enemy_X_Position,x                       ; to the left
	LDA Enemy_PageLoc,x
	SBC #$00                                     ; subtract borrow from page location
	STA Enemy_PageLoc,x
	LDY BowserFlamePRandomOfs,x                  ; get some value here and use as offset
	LDA Enemy_Y_Position,x                       ; load vertical coordinate
	CMP FlameYPosData,y                          ; compare against coordinate data using $0417,x as offset
	BEQ SetGfxF                                  ; if equal, branch and do not modify coordinate
	CLC
	ADC Enemy_Y_MoveForce,x                      ; otherwise add value here to coordinate and store
	STA Enemy_Y_Position,x                       ; as new vertical coordinate
SetGfxF:
	JSR RelativeEnemyPosition                    ; get new relative coordinates
	LDA Enemy_State,x                            ; if bowser's flame not in normal state,
	BNE ExFl                                     ; branch to leave
	LDA #$51                                     ; otherwise, continue
	STA $00                                      ; write first tile number
	LDY #$02                                     ; load attributes without vertical flip by default
	LDA FrameCounter
	AND #%00000010                               ; invert vertical flip bit every 2 frames
	BEQ FlmeAt                                   ; if d1 not set, write default value
	LDY #$82                                     ; otherwise write value with vertical flip bit set
FlmeAt:
	STY $01                                      ; set bowser's flame sprite attributes here
	LDY Enemy_SprDataOffset,x                    ; get OAM data offset
	LDX #$00

DrawFlameLoop:
	LDA Enemy_Rel_YPos                           ; get Y relative coordinate of current enemy object
	STA Sprite_Y_Position,y                      ; write into Y coordinate of OAM data
	LDA $00
	STA Sprite_Tilenumber,y                      ; write current tile number into OAM data
	INC $00                                      ; increment tile number to draw more bowser's flame
	LDA $01
	STA Sprite_Attributes,y                      ; write saved attributes into OAM data
	LDA Enemy_Rel_XPos
	STA Sprite_X_Position,y                      ; write X relative coordinate of current enemy object
	CLC
	ADC #$08
	STA Enemy_Rel_XPos                           ; then add eight to it and store
	INY
	INY
	INY
	INY                                          ; increment Y four times to move onto the next OAM
	INX                                          ; move onto the next OAM, and branch if three
	CPX #$03                                     ; have not yet been done
	BCC DrawFlameLoop
	LDX ObjectOffset                             ; reload original enemy offset
	JSR GetEnemyOffscreenBits                    ; get offscreen information
	LDY Enemy_SprDataOffset,x                    ; get OAM data offset
	LDA Enemy_OffscreenBits                      ; get enemy object offscreen bits
	LSR                                          ; move d0 to carry and result to stack
	PHA
	BCC M3FOfs                                   ; branch if carry not set
	LDA #$f8                                     ; otherwise move sprite offscreen, this part likely
	STA Sprite_Y_Position+12,y                   ; residual since flame is only made of three sprites
M3FOfs:
	PLA                                          ; get bits from stack
	LSR                                          ; move d1 to carry and move bits back to stack
	PHA
	BCC M2FOfs                                   ; branch if carry not set again
	LDA #$f8                                     ; otherwise move third sprite offscreen
	STA Sprite_Y_Position+8,y
M2FOfs:
	PLA                                          ; get bits from stack again
	LSR                                          ; move d2 to carry and move bits back to stack again
	PHA
	BCC M1FOfs                                   ; branch if carry not set yet again
	LDA #$f8                                     ; otherwise move second sprite offscreen
	STA Sprite_Y_Position+4,y
M1FOfs:
	PLA                                          ; get bits from stack one last time
	LSR                                          ; move d3 to carry
	BCC ExFlmeD                                  ; branch if carry not set one last time
	LDA #$f8
	STA Sprite_Y_Position,y                      ; otherwise move first sprite offscreen
ExFlmeD:
	RTS                                          ; leave

; --------------------------------

RunFireworks:
	DEC ExplosionTimerCounter,x                  ; decrement explosion timing counter here
	BNE SetupExpl                                ; if not expired, skip this part
	LDA #$08
	STA ExplosionTimerCounter,x                  ; reset counter
	INC ExplosionGfxCounter,x                    ; increment explosion graphics counter
	LDA ExplosionGfxCounter,x
	CMP #$03                                     ; check explosion graphics counter
	BCS FireworksSoundScore                      ; if at a certain point, branch to kill this object
SetupExpl:
	JSR RelativeEnemyPosition                    ; get relative coordinates of explosion
	LDA Enemy_Rel_YPos                           ; copy relative coordinates
	STA Fireball_Rel_YPos                        ; from the enemy object to the fireball object
	LDA Enemy_Rel_XPos                           ; first vertical, then horizontal
	STA Fireball_Rel_XPos
	LDY Enemy_SprDataOffset,x                    ; get OAM data offset
	LDA ExplosionGfxCounter,x                    ; get explosion graphics counter
	JSR DrawExplosion_Fireworks                  ; do a sub to draw the explosion then leave
	RTS

FireworksSoundScore:
	LDA #$00                                     ; disable enemy buffer flag
	STA Enemy_Flag,x
	LDA #Sfx_Blast                               ; play fireworks/gunfire sound
	STA Square2SoundQueue
	LDA #$05                                     ; set part of score modifier for 500 points
	STA DigitModifier+4
	JMP EndAreaPoints                            ; jump to award points accordingly then leave

; --------------------------------

StarFlagYPosAdder:
	.db $00, $00, $08, $08

StarFlagXPosAdder:
	.db $00, $08, $00, $08

StarFlagTileData:
	.db $54, $55, $56, $57

RunStarFlagObj:
	LDA #$00                                     ; initialize enemy frenzy buffer
	STA EnemyFrenzyBuffer
	LDA StarFlagTaskControl                      ; check star flag object task number here
	CMP #$05                                     ; if greater than 5, branch to exit
	BCS StarFlagExit
	JSR JumpEngine                               ; otherwise jump to appropriate sub

	.dw StarFlagExit
	.dw GameTimerFireworks
	.dw AwardGameTimerPoints
	.dw RaiseFlagSetoffFWorks
	.dw DelayToAreaEnd

GameTimerFireworks:
	LDY #$05                                     ; set default state for star flag object
	LDA GameTimerDisplay+2                       ; get game timer's last digit
	CMP #$01
	BEQ SetFWC                                   ; if last digit of game timer set to 1, skip ahead
	LDY #$03                                     ; otherwise load new value for state
	CMP #$03
	BEQ SetFWC                                   ; if last digit of game timer set to 3, skip ahead
	LDY #$00                                     ; otherwise load one more potential value for state
	CMP #$06
	BEQ SetFWC                                   ; if last digit of game timer set to 6, skip ahead
	LDA #$ff                                     ; otherwise set value for no fireworks
SetFWC:
	STA FireworksCounter                         ; set fireworks counter here
	STY Enemy_State,x                            ; set whatever state we have in star flag object

IncrementSFTask1:
	INC StarFlagTaskControl                      ; increment star flag object task number

StarFlagExit:
	RTS                                          ; leave

AwardGameTimerPoints:
	LDA GameTimerDisplay                         ; check all game timer digits for any intervals left
	ORA GameTimerDisplay+1
	ORA GameTimerDisplay+2
	BEQ IncrementSFTask1                         ; if no time left on game timer at all, branch to next task
	LDA FrameCounter
	AND #%00000100                               ; check frame counter for d2 set (skip ahead
	BEQ NoTTick                                  ; for four frames every four frames) branch if not set
	LDA #Sfx_TimerTick
	STA Square2SoundQueue                        ; load timer tick sound
NoTTick:
	LDY #$23                                     ; set offset here to subtract from game timer's last digit
	LDA #$ff                                     ; set adder here to $ff, or -1, to subtract one
	STA DigitModifier+5                          ; from the last digit of the game timer
	JSR DigitsMathRoutine                        ; subtract digit
	LDA #$05                                     ; set now to add 50 points
	STA DigitModifier+5                          ; per game timer interval subtracted

EndAreaPoints:
	LDY #$0b                                     ; load offset for mario's score by default
	LDA CurrentPlayer                            ; check player on the screen
	BEQ ELPGive                                  ; if mario, do not change
	LDY #$11                                     ; otherwise load offset for luigi's score
ELPGive:
	JSR DigitsMathRoutine                        ; award 50 points per game timer interval
	LDA CurrentPlayer                            ; get player on the screen (or 500 points per
	ASL                                          ; fireworks explosion if branched here from there)
	ASL                                          ; shift to high nybble
	ASL
	ASL
	ORA #%00000100                               ; add four to set nybble for game timer
	JMP UpdateNumber                             ; jump to print the new score and game timer

RaiseFlagSetoffFWorks:
	LDA Enemy_Y_Position,x                       ; check star flag's vertical position
	CMP #$72                                     ; against preset value
	BCC SetoffF                                  ; if star flag higher vertically, branch to other code
	DEC Enemy_Y_Position,x                       ; otherwise, raise star flag by one pixel
	JMP DrawStarFlag                             ; and skip this part here
SetoffF:
	LDA FireworksCounter                         ; check fireworks counter
	BEQ DrawFlagSetTimer                         ; if no fireworks left to go off, skip this part
	BMI DrawFlagSetTimer                         ; if no fireworks set to go off, skip this part
	LDA #Fireworks
	STA EnemyFrenzyBuffer                        ; otherwise set fireworks object in frenzy queue

DrawStarFlag:
	JSR RelativeEnemyPosition                    ; get relative coordinates of star flag
	LDY Enemy_SprDataOffset,x                    ; get OAM data offset
	LDX #$03                                     ; do four sprites
DSFLoop:
	LDA Enemy_Rel_YPos                           ; get relative vertical coordinate
	CLC
	ADC StarFlagYPosAdder,x                      ; add Y coordinate adder data
	STA Sprite_Y_Position,y                      ; store as Y coordinate
	LDA StarFlagTileData,x                       ; get tile number
	STA Sprite_Tilenumber,y                      ; store as tile number
	LDA #$22                                     ; set palette and background priority bits
	STA Sprite_Attributes,y                      ; store as attributes
	LDA Enemy_Rel_XPos                           ; get relative horizontal coordinate
	CLC
	ADC StarFlagXPosAdder,x                      ; add X coordinate adder data
	STA Sprite_X_Position,y                      ; store as X coordinate
	INY
	INY                                          ; increment OAM data offset four bytes
	INY                                          ; for next sprite
	INY
	DEX                                          ; move onto next sprite
	BPL DSFLoop                                  ; do this until all sprites are done
	LDX ObjectOffset                             ; get enemy object offset and leave
	RTS

DrawFlagSetTimer:
	JSR DrawStarFlag                             ; do sub to draw star flag
	LDA #$06
	STA EnemyIntervalTimer,x                     ; set interval timer here

IncrementSFTask2:
	INC StarFlagTaskControl                      ; move onto next task
	RTS

DelayToAreaEnd:
	JSR DrawStarFlag                             ; do sub to draw star flag
	LDA EnemyIntervalTimer,x                     ; if interval timer set in previous task
	BNE StarFlagExit2                            ; not yet expired, branch to leave
	LDA EventMusicBuffer                         ; if event music buffer empty,
	BEQ IncrementSFTask2                         ; branch to increment task

StarFlagExit2:
	RTS                                          ; otherwise leave

; --------------------------------
; $00 - used to store horizontal difference between player and piranha plant

MovePiranhaPlant:
	LDA Enemy_State,x                            ; check enemy state
	BNE PutinPipe                                ; if set at all, branch to leave
	LDA EnemyFrameTimer,x                        ; check enemy's timer here
	BNE PutinPipe                                ; branch to end if not yet expired
	LDA PiranhaPlant_MoveFlag,x                  ; check movement flag
	BNE SetupToMovePPlant                        ; if moving, skip to part ahead
	LDA PiranhaPlant_Y_Speed,x                   ; if currently rising, branch
	BMI ReversePlantSpeed                        ; to move enemy upwards out of pipe
	JSR PlayerEnemyDiff                          ; get horizontal difference between player and
	BPL ChkPlayerNearPipe                        ; piranha plant, and branch if enemy to right of player
	LDA $00                                      ; otherwise get saved horizontal difference
	EOR #$ff
	CLC                                          ; and change to two's compliment
	ADC #$01
	STA $00                                      ; save as new horizontal difference

ChkPlayerNearPipe:
	LDA $00                                      ; get saved horizontal difference
	CMP #$21
	BCC PutinPipe                                ; if player within a certain distance, branch to leave

ReversePlantSpeed:
	LDA PiranhaPlant_Y_Speed,x                   ; get vertical speed
	EOR #$ff
	CLC                                          ; change to two's compliment
	ADC #$01
	STA PiranhaPlant_Y_Speed,x                   ; save as new vertical speed
	INC PiranhaPlant_MoveFlag,x                  ; increment to set movement flag

SetupToMovePPlant:
	LDA PiranhaPlantDownYPos,x                   ; get original vertical coordinate (lowest point)
	LDY PiranhaPlant_Y_Speed,x                   ; get vertical speed
	BPL RiseFallPiranhaPlant                     ; branch if moving downwards
	LDA PiranhaPlantUpYPos,x                     ; otherwise get other vertical coordinate (highest point)

RiseFallPiranhaPlant:
	STA $00                                      ; save vertical coordinate here
	LDA FrameCounter                             ; get frame counter
	LSR
	BCC PutinPipe                                ; branch to leave if d0 set (execute code every other frame)
	LDA TimerControl                             ; get master timer control
	BNE PutinPipe                                ; branch to leave if set (likely not necessary)
	LDA Enemy_Y_Position,x                       ; get current vertical coordinate
	CLC
	ADC PiranhaPlant_Y_Speed,x                   ; add vertical speed to move up or down
	STA Enemy_Y_Position,x                       ; save as new vertical coordinate
	CMP $00                                      ; compare against low or high coordinate
	BNE PutinPipe                                ; branch to leave if not yet reached
	LDA #$00
	STA PiranhaPlant_MoveFlag,x                  ; otherwise clear movement flag
	LDA #$40
	STA EnemyFrameTimer,x                        ; set timer to delay piranha plant movement

PutinPipe:
	LDA #%00100000                               ; set background priority bit in sprite
	STA Enemy_SprAttrib,x                        ; attributes to give illusion of being inside pipe
	RTS                                          ; then leave

; -------------------------------------------------------------------------------------
; $07 - spinning speed

FirebarSpin:
	STA $07                                      ; save spinning speed here
	LDA FirebarSpinDirection,x                   ; check spinning direction
	BNE SpinCounterClockwise                     ; if moving counter-clockwise, branch to other part
	LDY #$18                                     ; possibly residual ldy
	LDA FirebarSpinState_Low,x
	CLC                                          ; add spinning speed to what would normally be
	ADC $07                                      ; the horizontal speed
	STA FirebarSpinState_Low,x
	LDA FirebarSpinState_High,x                  ; add carry to what would normally be the vertical speed
	ADC #$00
	RTS

SpinCounterClockwise:
	LDY #$08                                     ; possibly residual ldy
	LDA FirebarSpinState_Low,x
	SEC                                          ; subtract spinning speed to what would normally be
	SBC $07                                      ; the horizontal speed
	STA FirebarSpinState_Low,x
	LDA FirebarSpinState_High,x                  ; add carry to what would normally be the vertical speed
	SBC #$00
	RTS

; -------------------------------------------------------------------------------------
; $00 - used to hold collision flag, Y movement force + 5 or low byte of name table for rope
; $01 - used to hold high byte of name table for rope
; $02 - used to hold page location of rope

BalancePlatform:
	LDA Enemy_Y_HighPos,x                        ; check high byte of vertical position
	CMP #$03
	BNE DoBPl
	JMP EraseEnemyObject                         ; if far below screen, kill the object
DoBPl:
	LDA Enemy_State,x                            ; get object's state (set to $ff or other platform offset)
	BPL CheckBalPlatform                         ; if doing other balance platform, branch to leave
	RTS

CheckBalPlatform:
	TAY                                          ; save offset from state as Y
	LDA PlatformCollisionFlag,x                  ; get collision flag of platform
	STA $00                                      ; store here
	LDA Enemy_MovingDir,x                        ; get moving direction
	BEQ ChkForFall
	JMP PlatformFall                             ; if set, jump here

ChkForFall:
	LDA #$2d                                     ; check if platform is above a certain point
	CMP Enemy_Y_Position,x
	BCC ChkOtherForFall                          ; if not, branch elsewhere
	CPY $00                                      ; if collision flag is set to same value as
	BEQ MakePlatformFall                         ; enemy state, branch to make platforms fall
	CLC
	ADC #$02                                     ; otherwise add 2 pixels to vertical position
	STA Enemy_Y_Position,x                       ; of current platform and branch elsewhere
	JMP StopPlatforms                            ; to make platforms stop

MakePlatformFall:
	JMP InitPlatformFall                         ; make platforms fall

ChkOtherForFall:
	CMP Enemy_Y_Position,y                       ; check if other platform is above a certain point
	BCC ChkToMoveBalPlat                         ; if not, branch elsewhere
	CPX $00                                      ; if collision flag is set to same value as
	BEQ MakePlatformFall                         ; enemy state, branch to make platforms fall
	CLC
	ADC #$02                                     ; otherwise add 2 pixels to vertical position
	STA Enemy_Y_Position,y                       ; of other platform and branch elsewhere
	JMP StopPlatforms                            ; jump to stop movement and do not return

ChkToMoveBalPlat:
	LDA Enemy_Y_Position,x                       ; save vertical position to stack
	PHA
	LDA PlatformCollisionFlag,x                  ; get collision flag
	BPL ColFlg                                   ; branch if collision
	LDA Enemy_Y_MoveForce,x
	CLC                                          ; add $05 to contents of moveforce, whatever they be
	ADC #$05
	STA $00                                      ; store here
	LDA Enemy_Y_Speed,x
	ADC #$00                                     ; add carry to vertical speed
	BMI PlatDn                                   ; branch if moving downwards
	BNE PlatUp                                   ; branch elsewhere if moving upwards
	LDA $00
	CMP #$0b                                     ; check if there's still a little force left
	BCC PlatSt                                   ; if not enough, branch to stop movement
	BCS PlatUp                                   ; otherwise keep branch to move upwards
ColFlg:
	CMP ObjectOffset                             ; if collision flag matches
	BEQ PlatDn                                   ; current enemy object offset, branch
PlatUp:
	JSR MovePlatformUp                           ; do a sub to move upwards
	JMP DoOtherPlatform                          ; jump ahead to remaining code
PlatSt:
	JSR StopPlatforms                            ; do a sub to stop movement
	JMP DoOtherPlatform                          ; jump ahead to remaining code
PlatDn:
	JSR MovePlatformDown                         ; do a sub to move downwards

DoOtherPlatform:
	LDY Enemy_State,x                            ; get offset of other platform
	PLA                                          ; get old vertical coordinate from stack
	SEC
	SBC Enemy_Y_Position,x                       ; get difference of old vs. new coordinate
	CLC
	ADC Enemy_Y_Position,y                       ; add difference to vertical coordinate of other
	STA Enemy_Y_Position,y                       ; platform to move it in the opposite direction
	LDA PlatformCollisionFlag,x                  ; if no collision, skip this part here
	BMI DrawEraseRope
	TAX                                          ; put offset which collision occurred here
	JSR PositionPlayerOnVPlat                    ; and use it to position player accordingly

DrawEraseRope:
	LDY ObjectOffset                             ; get enemy object offset
	LDA Enemy_Y_Speed,y                          ; check to see if current platform is
	ORA Enemy_Y_MoveForce,y                      ; moving at all
	BEQ ExitRp                                   ; if not, skip all of this and branch to leave
	LDX VRAM_Buffer1_Offset                      ; get vram buffer offset
	CPX #$20                                     ; if offset beyond a certain point, go ahead
	BCS ExitRp                                   ; and skip this, branch to leave
	LDA Enemy_Y_Speed,y
	PHA                                          ; save two copies of vertical speed to stack
	PHA
	JSR SetupPlatformRope                        ; do a sub to figure out where to put new bg tiles
	LDA $01                                      ; write name table address to vram buffer
	STA VRAM_Buffer1,x                           ; first the high byte, then the low
	LDA $00
	STA VRAM_Buffer1+1,x
	LDA #$02                                     ; set length for 2 bytes
	STA VRAM_Buffer1+2,x
	LDA Enemy_Y_Speed,y                          ; if platform moving upwards, branch
	BMI EraseR1                                  ; to do something else
	LDA #$a2
	STA VRAM_Buffer1+3,x                         ; otherwise put tile numbers for left
	LDA #$a3                                     ; and right sides of rope in vram buffer
	STA VRAM_Buffer1+4,x
	JMP OtherRope                                ; jump to skip this part
EraseR1:
	LDA #$24                                     ; put blank tiles in vram buffer
	STA VRAM_Buffer1+3,x                         ; to erase rope
	STA VRAM_Buffer1+4,x

OtherRope:
	LDA Enemy_State,y                            ; get offset of other platform from state
	TAY                                          ; use as Y here
	PLA                                          ; pull second copy of vertical speed from stack
	EOR #$ff                                     ; invert bits to reverse speed
	JSR SetupPlatformRope                        ; do sub again to figure out where to put bg tiles
	LDA $01                                      ; write name table address to vram buffer
	STA VRAM_Buffer1+5,x                         ; this time we're doing putting tiles for
	LDA $00                                      ; the other platform
	STA VRAM_Buffer1+6,x
	LDA #$02
	STA VRAM_Buffer1+7,x                         ; set length again for 2 bytes
	PLA                                          ; pull first copy of vertical speed from stack
	BPL EraseR2                                  ; if moving upwards (note inversion earlier), skip this
	LDA #$a2
	STA VRAM_Buffer1+8,x                         ; otherwise put tile numbers for left
	LDA #$a3                                     ; and right sides of rope in vram
	STA VRAM_Buffer1+9,x                         ; transfer buffer
	JMP EndRp                                    ; jump to skip this part
EraseR2:
	LDA #$24                                     ; put blank tiles in vram buffer
	STA VRAM_Buffer1+8,x                         ; to erase rope
	STA VRAM_Buffer1+9,x
EndRp:
	LDA #$00                                     ; put null terminator at the end
	STA VRAM_Buffer1+10,x
	LDA VRAM_Buffer1_Offset                      ; add ten bytes to the vram buffer offset
	CLC                                          ; and store
	ADC #10
	STA VRAM_Buffer1_Offset
ExitRp:
	LDX ObjectOffset                             ; get enemy object buffer offset and leave
	RTS

SetupPlatformRope:
	PHA                                          ; save second/third copy to stack
	LDA Enemy_X_Position,y                       ; get horizontal coordinate
	CLC
	ADC #$08                                     ; add eight pixels
	LDX SecondaryHardMode                        ; if secondary hard mode flag set,
	BNE GetLRp                                   ; use coordinate as-is
	CLC
	ADC #$10                                     ; otherwise add sixteen more pixels
GetLRp:
	PHA                                          ; save modified horizontal coordinate to stack
	LDA Enemy_PageLoc,y
	ADC #$00                                     ; add carry to page location
	STA $02                                      ; and save here
	PLA                                          ; pull modified horizontal coordinate
	AND #%11110000                               ; from the stack, mask out low nybble
	LSR                                          ; and shift three bits to the right
	LSR
	LSR
	STA $00                                      ; store result here as part of name table low byte
	LDX Enemy_Y_Position,y                       ; get vertical coordinate
	PLA                                          ; get second/third copy of vertical speed from stack
	BPL GetHRp                                   ; skip this part if moving downwards or not at all
	TXA
	CLC
	ADC #$08                                     ; add eight to vertical coordinate and
	TAX                                          ; save as X
GetHRp:
	TXA                                          ; move vertical coordinate to A
	LDX VRAM_Buffer1_Offset                      ; get vram buffer offset
	ASL
	ROL                                          ; rotate d7 to d0 and d6 into carry
	PHA                                          ; save modified vertical coordinate to stack
	ROL                                          ; rotate carry to d0, thus d7 and d6 are at 2 LSB
	AND #%00000011                               ; mask out all bits but d7 and d6, then set
	ORA #%00100000                               ; d5 to get appropriate high byte of name table
	STA $01                                      ; address, then store
	LDA $02                                      ; get saved page location from earlier
	AND #$01                                     ; mask out all but LSB
	ASL
	ASL                                          ; shift twice to the left and save with the
	ORA $01                                      ; rest of the bits of the high byte, to get
	STA $01                                      ; the proper name table and the right place on it
	PLA                                          ; get modified vertical coordinate from stack
	AND #%11100000                               ; mask out low nybble and LSB of high nybble
	CLC
	ADC $00                                      ; add to horizontal part saved here
	STA $00                                      ; save as name table low byte
	LDA Enemy_Y_Position,y
	CMP #$e8                                     ; if vertical position not below the
	BCC ExPRp                                    ; bottom of the screen, we're done, branch to leave
	LDA $00
	AND #%10111111                               ; mask out d6 of low byte of name table address
	STA $00
ExPRp:
	RTS                                          ; leave!

InitPlatformFall:
	TYA                                          ; move offset of other platform from Y to X
	TAX
	JSR GetEnemyOffscreenBits                    ; get offscreen bits
	LDA #$06
	JSR SetupFloateyNumber                       ; award 1000 points to player
	LDA Player_Rel_XPos
	STA FloateyNum_X_Pos,x                       ; put floatey number coordinates where player is
	LDA Player_Y_Position
	STA FloateyNum_Y_Pos,x
	LDA #$01                                     ; set moving direction as flag for
	STA Enemy_MovingDir,x                        ; falling platforms

StopPlatforms:
	JSR InitVStf                                 ; initialize vertical speed and low byte
	STA Enemy_Y_Speed,y                          ; for both platforms and leave
	STA Enemy_Y_MoveForce,y
	RTS

PlatformFall:
	TYA                                          ; save offset for other platform to stack
	PHA
	JSR MoveFallingPlatform                      ; make current platform fall
	PLA
	TAX                                          ; pull offset from stack and save to X
	JSR MoveFallingPlatform                      ; make other platform fall
	LDX ObjectOffset
	LDA PlatformCollisionFlag,x                  ; if player not standing on either platform,
	BMI ExPF                                     ; skip this part
	TAX                                          ; transfer collision flag offset as offset to X
	JSR PositionPlayerOnVPlat                    ; and position player appropriately
ExPF:
	LDX ObjectOffset                             ; get enemy object buffer offset and leave
	RTS

; --------------------------------

YMovingPlatform:
	LDA Enemy_Y_Speed,x                          ; if platform moving up or down, skip ahead to
	ORA Enemy_Y_MoveForce,x                      ; check on other position
	BNE ChkYCenterPos
	STA Enemy_YMF_Dummy,x                        ; initialize dummy variable
	LDA Enemy_Y_Position,x
	CMP YPlatformTopYPos,x                       ; if current vertical position => top position, branch
	BCS ChkYCenterPos                            ; ahead of all this
	LDA FrameCounter
	AND #%00000111                               ; check for every eighth frame
	BNE SkipIY
	INC Enemy_Y_Position,x                       ; increase vertical position every eighth frame
SkipIY:
	JMP ChkYPCollision                           ; skip ahead to last part

ChkYCenterPos:
	LDA Enemy_Y_Position,x                       ; if current vertical position < central position, branch
	CMP YPlatformCenterYPos,x                    ; to slow ascent/move downwards
	BCC YMDown
	JSR MovePlatformUp                           ; otherwise start slowing descent/moving upwards
	JMP ChkYPCollision
YMDown:
	JSR MovePlatformDown                         ; start slowing ascent/moving downwards

ChkYPCollision:
	LDA PlatformCollisionFlag,x                  ; if collision flag not set here, branch
	BMI ExYPl                                    ; to leave
	JSR PositionPlayerOnVPlat                    ; otherwise position player appropriately
ExYPl:
	RTS                                          ; leave

; --------------------------------
; $00 - used as adder to position player hotizontally

XMovingPlatform:
	LDA #$0e                                     ; load preset maximum value for secondary counter
	JSR XMoveCntr_Platform                       ; do a sub to increment counters for movement
	JSR MoveWithXMCntrs                          ; do a sub to move platform accordingly, and return value
	LDA PlatformCollisionFlag,x                  ; if no collision with player,
	BMI ExXMP                                    ; branch ahead to leave

PositionPlayerOnHPlat:
	LDA Player_X_Position
	CLC                                          ; add saved value from second subroutine to
	ADC $00                                      ; current player's position to position
	STA Player_X_Position                        ; player accordingly in horizontal position
	LDA Player_PageLoc                           ; get player's page location
	LDY $00                                      ; check to see if saved value here is positive or negative
	BMI PPHSubt                                  ; if negative, branch to subtract
	ADC #$00                                     ; otherwise add carry to page location
	JMP SetPVar                                  ; jump to skip subtraction
PPHSubt:
	SBC #$00                                     ; subtract borrow from page location
SetPVar:
	STA Player_PageLoc                           ; save result to player's page location
	STY Platform_X_Scroll                        ; put saved value from second sub here to be used later
	JSR PositionPlayerOnVPlat                    ; position player vertically and appropriately
ExXMP:
	RTS                                          ; and we are done here

; --------------------------------

DropPlatform:
	LDA PlatformCollisionFlag,x                  ; if no collision between platform and player
	BMI ExDPl                                    ; occurred, just leave without moving anything
	JSR MoveDropPlatform                         ; otherwise do a sub to move platform down very quickly
	JSR PositionPlayerOnVPlat                    ; do a sub to position player appropriately
ExDPl:
	RTS                                          ; leave

; --------------------------------
; $00 - residual value from sub

RightPlatform:
	JSR MoveEnemyHorizontally                    ; move platform with current horizontal speed, if any
	STA $00                                      ; store saved value here (residual code)
	LDA PlatformCollisionFlag,x                  ; check collision flag, if no collision between player
	BMI ExRPl                                    ; and platform, branch ahead, leave speed unaltered
	LDA #$10
	STA Enemy_X_Speed,x                          ; otherwise set new speed (gets moving if motionless)
	JSR PositionPlayerOnHPlat                    ; use saved value from earlier sub to position player
ExRPl:
	RTS                                          ; then leave

; --------------------------------

MoveLargeLiftPlat:
	JSR MoveLiftPlatforms                        ; execute common to all large and small lift platforms
	JMP ChkYPCollision                           ; branch to position player correctly

MoveSmallPlatform:
	JSR MoveLiftPlatforms                        ; execute common to all large and small lift platforms
	JMP ChkSmallPlatCollision                    ; branch to position player correctly

MoveLiftPlatforms:
	LDA TimerControl                             ; if master timer control set, skip all of this
	BNE ExLiftP                                  ; and branch to leave
	LDA Enemy_YMF_Dummy,x
	CLC                                          ; add contents of movement amount to whatever's here
	ADC Enemy_Y_MoveForce,x
	STA Enemy_YMF_Dummy,x
	LDA Enemy_Y_Position,x                       ; add whatever vertical speed is set to current
	ADC Enemy_Y_Speed,x                          ; vertical position plus carry to move up or down
	STA Enemy_Y_Position,x                       ; and then leave
	RTS

ChkSmallPlatCollision:
	LDA PlatformCollisionFlag,x                  ; get bounding box counter saved in collision flag
	BEQ ExLiftP                                  ; if none found, leave player position alone
	JSR PositionPlayerOnS_Plat                   ; use to position player correctly
ExLiftP:
	RTS                                          ; then leave

; -------------------------------------------------------------------------------------
; $00 - page location of extended left boundary
; $01 - extended left boundary position
; $02 - page location of extended right boundary
; $03 - extended right boundary position

OffscreenBoundsCheck:
	LDA Enemy_ID,x                               ; check for cheep-cheep object
	CMP #FlyingCheepCheep                        ; branch to leave if found
	BEQ ExScrnBd
	LDA ScreenLeft_X_Pos                         ; get horizontal coordinate for left side of screen
	LDY Enemy_ID,x
	CPY #HammerBro                               ; check for hammer bro object
	BEQ LimitB
	CPY #PiranhaPlant                            ; check for piranha plant object
	BNE ExtendLB                                 ; these two will be erased sooner than others if too far left
LimitB:
	ADC #$38                                     ; add 56 pixels to coordinate if hammer bro or piranha plant
ExtendLB:
	SBC #$48                                     ; subtract 72 pixels regardless of enemy object
	STA $01                                      ; store result here
	LDA ScreenLeft_PageLoc
	SBC #$00                                     ; subtract borrow from page location of left side
	STA $00                                      ; store result here
	LDA ScreenRight_X_Pos                        ; add 72 pixels to the right side horizontal coordinate
	ADC #$48
	STA $03                                      ; store result here
	LDA ScreenRight_PageLoc
	ADC #$00                                     ; then add the carry to the page location
	STA $02                                      ; and store result here
	LDA Enemy_X_Position,x                       ; compare horizontal coordinate of the enemy object
	CMP $01                                      ; to modified horizontal left edge coordinate to get carry
	LDA Enemy_PageLoc,x
	SBC $00                                      ; then subtract it from the page coordinate of the enemy object
	BMI TooFar                                   ; if enemy object is too far left, branch to erase it
	LDA Enemy_X_Position,x                       ; compare horizontal coordinate of the enemy object
	CMP $03                                      ; to modified horizontal right edge coordinate to get carry
	LDA Enemy_PageLoc,x
	SBC $02                                      ; then subtract it from the page coordinate of the enemy object
	BMI ExScrnBd                                 ; if enemy object is on the screen, leave, do not erase enemy
	LDA Enemy_State,x                            ; if at this point, enemy is offscreen to the right, so check
	CMP #HammerBro                               ; if in state used by spiny's egg, do not erase
	BEQ ExScrnBd
	CPY #PiranhaPlant                            ; if piranha plant, do not erase
	BEQ ExScrnBd
	CPY #FlagpoleFlagObject                      ; if flagpole flag, do not erase
	BEQ ExScrnBd
	CPY #StarFlagObject                          ; if star flag, do not erase
	BEQ ExScrnBd
	CPY #JumpspringObject                        ; if jumpspring, do not erase
	BEQ ExScrnBd                                 ; erase all others too far to the right
TooFar:
	JSR EraseEnemyObject                         ; erase object if necessary
ExScrnBd:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------

; -------------------------------------------------------------------------------------
; $01 - enemy buffer offset

FireballEnemyCollision:
	LDA Fireball_State,x                         ; check to see if fireball state is set at all
	BEQ ExitFBallEnemy                           ; branch to leave if not
	ASL
	BCS ExitFBallEnemy                           ; branch to leave also if d7 in state is set
	LDA FrameCounter
	LSR                                          ; get LSB of frame counter
	BCS ExitFBallEnemy                           ; branch to leave if set (do routine every other frame)
	TXA
	ASL                                          ; multiply fireball offset by four
	ASL
	CLC
	ADC #$1c                                     ; then add $1c or 28 bytes to it
	TAY                                          ; to use fireball's bounding box coordinates
	LDX #$04

FireballEnemyCDLoop:
	STX $01                                      ; store enemy object offset here
	TYA
	PHA                                          ; push fireball offset to the stack
	LDA Enemy_State,x
	AND #%00100000                               ; check to see if d5 is set in enemy state
	BNE NoFToECol                                ; if so, skip to next enemy slot
	LDA Enemy_Flag,x                             ; check to see if buffer flag is set
	BEQ NoFToECol                                ; if not, skip to next enemy slot
	LDA Enemy_ID,x                               ; check enemy identifier
	CMP #$24
	BCC GoombaDie                                ; if < $24, branch to check further
	CMP #$2b
	BCC NoFToECol                                ; if in range $24-$2a, skip to next enemy slot
GoombaDie:
	CMP #Goomba                                  ; check for goomba identifier
	BNE NotGoomba                                ; if not found, continue with code
	LDA Enemy_State,x                            ; otherwise check for defeated state
	CMP #$02                                     ; if stomped or otherwise defeated,
	BCS NoFToECol                                ; skip to next enemy slot
NotGoomba:
	LDA EnemyOffscrBitsMasked,x                  ; if any masked offscreen bits set,
	BNE NoFToECol                                ; skip to next enemy slot
	TXA
	ASL                                          ; otherwise multiply enemy offset by four
	ASL
	CLC
	ADC #$04                                     ; add 4 bytes to it
	TAX                                          ; to use enemy's bounding box coordinates
	JSR SprObjectCollisionCore                   ; do fireball-to-enemy collision detection
	LDX ObjectOffset                             ; return fireball's original offset
	BCC NoFToECol                                ; if carry clear, no collision, thus do next enemy slot
	LDA #%10000000
	STA Fireball_State,x                         ; set d7 in enemy state
	LDX $01                                      ; get enemy offset
	JSR HandleEnemyFBallCol                      ; jump to handle fireball to enemy collision
NoFToECol:
	PLA                                          ; pull fireball offset from stack
	TAY                                          ; put it in Y
	LDX $01                                      ; get enemy object offset
	DEX                                          ; decrement it
	BPL FireballEnemyCDLoop                      ; loop back until collision detection done on all enemies

ExitFBallEnemy:
	LDX ObjectOffset                             ; get original fireball offset and leave
	RTS

BowserIdentities:
	.db Goomba, GreenKoopa, BuzzyBeetle, Spiny, Lakitu, Bloober, HammerBro, Bowser

HandleEnemyFBallCol:
	JSR RelativeEnemyPosition                    ; get relative coordinate of enemy
	LDX $01                                      ; get current enemy object offset
	LDA Enemy_Flag,x                             ; check buffer flag for d7 set
	BPL ChkBuzzyBeetle                           ; branch if not set to continue
	AND #%00001111                               ; otherwise mask out high nybble and
	TAX                                          ; use low nybble as enemy offset
	LDA Enemy_ID,x
	CMP #Bowser                                  ; check enemy identifier for bowser
	BEQ HurtBowser                               ; branch if found
	LDX $01                                      ; otherwise retrieve current enemy offset

ChkBuzzyBeetle:
	LDA Enemy_ID,x
	CMP #BuzzyBeetle                             ; check for buzzy beetle
	BEQ ExHCF                                    ; branch if found to leave (buzzy beetles fireproof)
	CMP #Bowser                                  ; check for bowser one more time (necessary if d7 of flag was clear)
	BNE ChkOtherEnemies                          ; if not found, branch to check other enemies

HurtBowser:
	DEC BowserHitPoints                          ; decrement bowser's hit points
	BNE ExHCF                                    ; if bowser still has hit points, branch to leave
	JSR InitVStf                                 ; otherwise do sub to init vertical speed and movement force
	STA Enemy_X_Speed,x                          ; initialize horizontal speed
	STA EnemyFrenzyBuffer                        ; init enemy frenzy buffer
	LDA #$fe
	STA Enemy_Y_Speed,x                          ; set vertical speed to make defeated bowser jump a little
	LDY WorldNumber                              ; use world number as offset
	LDA BowserIdentities,y                       ; get enemy identifier to replace bowser with
	STA Enemy_ID,x                               ; set as new enemy identifier
	LDA #$20                                     ; set A to use starting value for state
	CPY #$03                                     ; check to see if using offset of 3 or more
	BCS SetDBSte                                 ; branch if so
	ORA #$03                                     ; otherwise add 3 to enemy state
SetDBSte:
	STA Enemy_State,x                            ; set defeated enemy state
	LDA #Sfx_BowserFall
	STA Square2SoundQueue                        ; load bowser defeat sound
	LDX $01                                      ; get enemy offset
	LDA #$09                                     ; award 5000 points to player for defeating bowser
	BNE EnemySmackScore                          ; unconditional branch to award points

ChkOtherEnemies:
	CMP #BulletBill_FrenzyVar
	BEQ ExHCF                                    ; branch to leave if bullet bill (frenzy variant)
	CMP #Podoboo
	BEQ ExHCF                                    ; branch to leave if podoboo
	CMP #$15
	BCS ExHCF                                    ; branch to leave if identifier => $15

ShellOrBlockDefeat:
	LDA Enemy_ID,x                               ; check for piranha plant
	CMP #PiranhaPlant
	BNE StnE                                     ; branch if not found
	LDA Enemy_Y_Position,x
	ADC #$18                                     ; add 24 pixels to enemy object's vertical position
	STA Enemy_Y_Position,x
StnE:
	JSR ChkToStunEnemies                         ; do yet another sub
	LDA Enemy_State,x
	AND #%00011111                               ; mask out 2 MSB of enemy object's state
	ORA #%00100000                               ; set d5 to defeat enemy and save as new state
	STA Enemy_State,x
	LDA #$02                                     ; award 200 points by default
	LDY Enemy_ID,x                               ; check for hammer bro
	CPY #HammerBro
	BNE GoombaPoints                             ; branch if not found
	LDA #$06                                     ; award 1000 points for hammer bro

GoombaPoints:
	CPY #Goomba                                  ; check for goomba
	BNE EnemySmackScore                          ; branch if not found
	LDA #$01                                     ; award 100 points for goomba

EnemySmackScore:
	JSR SetupFloateyNumber                       ; update necessary score variables
	LDA #Sfx_EnemySmack                          ; play smack enemy sound
	STA Square1SoundQueue
ExHCF:
	RTS                                          ; and now let's leave

; -------------------------------------------------------------------------------------

PlayerHammerCollision:
	LDA FrameCounter                             ; get frame counter
	LSR                                          ; shift d0 into carry
	BCC ExPHC                                    ; branch to leave if d0 not set to execute every other frame
	LDA TimerControl                             ; if either master timer control
	ORA Misc_OffscreenBits                       ; or any offscreen bits for hammer are set,
	BNE ExPHC                                    ; branch to leave
	TXA
	ASL                                          ; multiply misc object offset by four
	ASL
	CLC
	ADC #$24                                     ; add 36 or $24 bytes to get proper offset
	TAY                                          ; for misc object bounding box coordinates
	JSR PlayerCollisionCore                      ; do player-to-hammer collision detection
	LDX ObjectOffset                             ; get misc object offset
	BCC ClHCol                                   ; if no collision, then branch
	LDA Misc_Collision_Flag,x                    ; otherwise read collision flag
	BNE ExPHC                                    ; if collision flag already set, branch to leave
	LDA #$01
	STA Misc_Collision_Flag,x                    ; otherwise set collision flag now
	LDA Misc_X_Speed,x
	EOR #$ff                                     ; get two's compliment of
	CLC                                          ; hammer's horizontal speed
	ADC #$01
	STA Misc_X_Speed,x                           ; set to send hammer flying the opposite direction
	LDA StarInvincibleTimer                      ; if star mario invincibility timer set,
	BNE ExPHC                                    ; branch to leave
	JMP InjurePlayer                             ; otherwise jump to hurt player, do not return
ClHCol:
	LDA #$00                                     ; clear collision flag
	STA Misc_Collision_Flag,x
ExPHC:
	RTS

; -------------------------------------------------------------------------------------

HandlePowerUpCollision:
	JSR EraseEnemyObject                         ; erase the power-up object
	LDA #$06
	JSR SetupFloateyNumber                       ; award 1000 points to player by default
	LDA #Sfx_PowerUpGrab
	STA Square2SoundQueue                        ; play the power-up sound
	LDA PowerUpType                              ; check power-up type
	CMP #$02
	BCC Shroom_Flower_PUp                        ; if mushroom or fire flower, branch
	CMP #$03
	BEQ SetFor1Up                                ; if 1-up mushroom, branch
	LDA #$23                                     ; otherwise set star mario invincibility
	STA StarInvincibleTimer                      ; timer, and load the star mario music
	LDA #StarPowerMusic                          ; into the area music queue, then leave
	STA AreaMusicQueue
	RTS

Shroom_Flower_PUp:
	LDA PlayerStatus                             ; if player status = small, branch
	BEQ UpToSuper
	CMP #$01                                     ; if player status not super, leave
	BNE NoPUp
	LDX ObjectOffset                             ; get enemy offset, not necessary
	LDA #$02                                     ; set player status to fiery
	STA PlayerStatus
	JSR GetPlayerColors                          ; run sub to change colors of player
	LDX ObjectOffset                             ; get enemy offset again, and again not necessary
	LDA #$0c                                     ; set value to be used by subroutine tree (fiery)
	JMP UpToFiery                                ; jump to set values accordingly

SetFor1Up:
	LDA #$0b                                     ; change 1000 points into 1-up instead
	STA FloateyNum_Control,x                     ; and then leave
	RTS

UpToSuper:
	LDA #$01                                     ; set player status to super
	STA PlayerStatus
	LDA #$09                                     ; set value to be used by subroutine tree (super)

UpToFiery:
	LDY #$00                                     ; set value to be used as new player state
	JSR SetPRout                                 ; set values to stop certain things in motion
NoPUp:
	RTS

; --------------------------------

ResidualXSpdData:
	.db $18, $e8

KickedShellXSpdData:
	.db $30, $d0

DemotedKoopaXSpdData:
	.db $08, $f8

PlayerEnemyCollision:
	LDA FrameCounter                             ; check counter for d0 set
	LSR
	BCS NoPUp                                    ; if set, branch to leave
	JSR CheckPlayerVertical                      ; if player object is completely offscreen or
	BCS NoPECol                                  ; if down past 224th pixel row, branch to leave
	LDA EnemyOffscrBitsMasked,x                  ; if current enemy is offscreen by any amount,
	BNE NoPECol                                  ; go ahead and branch to leave
	LDA GameEngineSubroutine
	CMP #$08                                     ; if not set to run player control routine
	BNE NoPECol                                  ; on next frame, branch to leave
	LDA Enemy_State,x
	AND #%00100000                               ; if enemy state has d5 set, branch to leave
	BNE NoPECol
	JSR GetEnemyBoundBoxOfs                      ; get bounding box offset for current enemy object
	JSR PlayerCollisionCore                      ; do collision detection on player vs. enemy
	LDX ObjectOffset                             ; get enemy object buffer offset
	BCS CheckForPUpCollision                     ; if collision, branch past this part here
	LDA Enemy_CollisionBits,x
	AND #%11111110                               ; otherwise, clear d0 of current enemy object's
	STA Enemy_CollisionBits,x                    ; collision bit
NoPECol:
	RTS

CheckForPUpCollision:
	LDY Enemy_ID,x
	CPY #PowerUpObject                           ; check for power-up object
	BNE EColl                                    ; if not found, branch to next part
	JMP HandlePowerUpCollision                   ; otherwise, unconditional jump backwards
EColl:
	LDA StarInvincibleTimer                      ; if star mario invincibility timer expired,
	BEQ HandlePECollisions                       ; perform task here, otherwise kill enemy like
	JMP ShellOrBlockDefeat                       ; hit with a shell, or from beneath

KickedShellPtsData:
	.db $0a, $06, $04

HandlePECollisions:
	LDA Enemy_CollisionBits,x                    ; check enemy collision bits for d0 set
	AND #%00000001                               ; or for being offscreen at all
	ORA EnemyOffscrBitsMasked,x
	BNE ExPEC                                    ; branch to leave if either is true
	LDA #$01
	ORA Enemy_CollisionBits,x                    ; otherwise set d0 now
	STA Enemy_CollisionBits,x
	CPY #Spiny                                   ; branch if spiny
	BEQ ChkForPlayerInjury
	CPY #PiranhaPlant                            ; branch if piranha plant
	BEQ InjurePlayer
	CPY #Podoboo                                 ; branch if podoboo
	BEQ InjurePlayer
	CPY #BulletBill_CannonVar                    ; branch if bullet bill
	BEQ ChkForPlayerInjury
	CPY #$15                                     ; branch if object => $15
	BCS InjurePlayer
	LDA AreaType                                 ; branch if water type level
	BEQ InjurePlayer
	LDA Enemy_State,x                            ; branch if d7 of enemy state was set
	ASL
	BCS ChkForPlayerInjury
	LDA Enemy_State,x                            ; mask out all but 3 LSB of enemy state
	AND #%00000111
	CMP #$02                                     ; branch if enemy is in normal or falling state
	BCC ChkForPlayerInjury
	LDA Enemy_ID,x                               ; branch to leave if goomba in defeated state
	CMP #Goomba
	BEQ ExPEC
	LDA #Sfx_EnemySmack                          ; play smack enemy sound
	STA Square1SoundQueue
	LDA Enemy_State,x                            ; set d7 in enemy state, thus become moving shell
	ORA #%10000000
	STA Enemy_State,x
	JSR EnemyFacePlayer                          ; set moving direction and get offset
	LDA KickedShellXSpdData,y                    ; load and set horizontal speed data with offset
	STA Enemy_X_Speed,x
	LDA #$03                                     ; add three to whatever the stomp counter contains
	CLC                                          ; to give points for kicking the shell
	ADC StompChainCounter
	LDY EnemyIntervalTimer,x                     ; check shell enemy's timer
	CPY #$03                                     ; if above a certain point, branch using the points
	BCS KSPts                                    ; data obtained from the stomp counter + 3
	LDA KickedShellPtsData,y                     ; otherwise, set points based on proximity to timer expiration
KSPts:
	JSR SetupFloateyNumber                       ; set values for floatey number now
ExPEC:
	RTS                                          ; leave!!!

ChkForPlayerInjury:
	LDA Player_Y_Speed                           ; check player's vertical speed
	BMI ChkInj                                   ; perform procedure below if player moving upwards
	BNE EnemyStomped                             ; or not at all, and branch elsewhere if moving downwards
ChkInj:
	LDA Enemy_ID,x                               ; branch if enemy object < $07
	CMP #Bloober
	BCC ChkETmrs
	LDA Player_Y_Position                        ; add 12 pixels to player's vertical position
	CLC
	ADC #$0c
	CMP Enemy_Y_Position,x                       ; compare modified player's position to enemy's position
	BCC EnemyStomped                             ; branch if this player's position above (less than) enemy's
ChkETmrs:
	LDA StompTimer                               ; check stomp timer
	BNE EnemyStomped                             ; branch if set
	LDA InjuryTimer                              ; check to see if injured invincibility timer still
	BNE ExInjColRoutines                         ; counting down, and branch elsewhere to leave if so
	LDA Player_Rel_XPos
	CMP Enemy_Rel_XPos                           ; if player's relative position to the left of enemy's
	BCC TInjE                                    ; relative position, branch here
	JMP ChkEnemyFaceRight                        ; otherwise do a jump here
TInjE:
	LDA Enemy_MovingDir,x                        ; if enemy moving towards the left,
	CMP #$01                                     ; branch, otherwise do a jump here
	BNE InjurePlayer                             ; to turn the enemy around
	JMP LInj

InjurePlayer:
	LDA InjuryTimer                              ; check again to see if injured invincibility timer is
	BNE ExInjColRoutines                         ; at zero, and branch to leave if so

ForceInjury:
	LDX PlayerStatus                             ; check player's status
	BEQ KillPlayer                               ; branch if small
	STA PlayerStatus                             ; otherwise set player's status to small
	LDA #$08
	STA InjuryTimer                              ; set injured invincibility timer
	ASL
	STA Square1SoundQueue                        ; play pipedown/injury sound
	JSR GetPlayerColors                          ; change player's palette if necessary
	LDA #$0a                                     ; set subroutine to run on next frame
SetKRout:
	LDY #$01                                     ; set new player state
SetPRout:
	STA GameEngineSubroutine                     ; load new value to run subroutine on next frame
	STY Player_State                             ; store new player state
	LDY #$ff
	STY TimerControl                             ; set master timer control flag to halt timers
	INY
	STY ScrollAmount                             ; initialize scroll speed

ExInjColRoutines:
	LDX ObjectOffset                             ; get enemy offset and leave
	RTS

KillPlayer:
	STX Player_X_Speed                           ; halt player's horizontal movement by initializing speed
	INX
	STX EventMusicQueue                          ; set event music queue to death music
	LDA #$fc
	STA Player_Y_Speed                           ; set new vertical speed
	LDA #$0b                                     ; set subroutine to run on next frame
	BNE SetKRout                                 ; branch to set player's state and other things

StompedEnemyPtsData:
	.db $02, $06, $05, $06

EnemyStomped:
	LDA Enemy_ID,x                               ; check for spiny, branch to hurt player
	CMP #Spiny                                   ; if found
	BEQ InjurePlayer
	LDA #Sfx_EnemyStomp                          ; otherwise play stomp/swim sound
	STA Square1SoundQueue
	LDA Enemy_ID,x
	LDY #$00                                     ; initialize points data offset for stomped enemies
	CMP #FlyingCheepCheep                        ; branch for cheep-cheep
	BEQ EnemyStompedPts
	CMP #BulletBill_FrenzyVar                    ; branch for either bullet bill object
	BEQ EnemyStompedPts
	CMP #BulletBill_CannonVar
	BEQ EnemyStompedPts
	CMP #Podoboo                                 ; branch for podoboo (this branch is logically impossible
	BEQ EnemyStompedPts                          ; for cpu to take due to earlier checking of podoboo)
	INY                                          ; increment points data offset
	CMP #HammerBro                               ; branch for hammer bro
	BEQ EnemyStompedPts
	INY                                          ; increment points data offset
	CMP #Lakitu                                  ; branch for lakitu
	BEQ EnemyStompedPts
	INY                                          ; increment points data offset
	CMP #Bloober                                 ; branch if NOT bloober
	BNE ChkForDemoteKoopa

EnemyStompedPts:
	LDA StompedEnemyPtsData,y                    ; load points data using offset in Y
	JSR SetupFloateyNumber                       ; run sub to set floatey number controls
	LDA Enemy_MovingDir,x
	PHA                                          ; save enemy movement direction to stack
	JSR SetStun                                  ; run sub to kill enemy
	PLA
	STA Enemy_MovingDir,x                        ; return enemy movement direction from stack
	LDA #%00100000
	STA Enemy_State,x                            ; set d5 in enemy state
	JSR InitVStf                                 ; nullify vertical speed, physics-related thing,
	STA Enemy_X_Speed,x                          ; and horizontal speed
	LDA #$fd                                     ; set player's vertical speed, to give bounce
	STA Player_Y_Speed
	RTS

ChkForDemoteKoopa:
	CMP #$09                                     ; branch elsewhere if enemy object < $09
	BCC HandleStompedShellE
	AND #%00000001                               ; demote koopa paratroopas to ordinary troopas
	STA Enemy_ID,x
	LDY #$00                                     ; return enemy to normal state
	STY Enemy_State,x
	LDA #$03                                     ; award 400 points to the player
	JSR SetupFloateyNumber
	JSR InitVStf                                 ; nullify physics-related thing and vertical speed
	JSR EnemyFacePlayer                          ; turn enemy around if necessary
	LDA DemotedKoopaXSpdData,y
	STA Enemy_X_Speed,x                          ; set appropriate moving speed based on direction
	JMP SBnce                                    ; then move onto something else

RevivalRateData:
	.db $10, $0b

HandleStompedShellE:
	LDA #$04                                     ; set defeated state for enemy
	STA Enemy_State,x
	INC StompChainCounter                        ; increment the stomp counter
	LDA StompChainCounter                        ; add whatever is in the stomp counter
	CLC                                          ; to whatever is in the stomp timer
	ADC StompTimer
	JSR SetupFloateyNumber                       ; award points accordingly
	INC StompTimer                               ; increment stomp timer of some sort
	LDY PrimaryHardMode                          ; check primary hard mode flag
	LDA RevivalRateData,y                        ; load timer setting according to flag
	STA EnemyIntervalTimer,x                     ; set as enemy timer to revive stomped enemy
SBnce:
	LDA #$fc                                     ; set player's vertical speed for bounce
	STA Player_Y_Speed                           ; and then leave!!!
	RTS

ChkEnemyFaceRight:
	LDA Enemy_MovingDir,x                        ; check to see if enemy is moving to the right
	CMP #$01
	BNE LInj                                     ; if not, branch
	JMP InjurePlayer                             ; otherwise go back to hurt player
LInj:
	JSR EnemyTurnAround                          ; turn the enemy around, if necessary
	JMP InjurePlayer                             ; go back to hurt player


EnemyFacePlayer:
	LDY #$01                                     ; set to move right by default
	JSR PlayerEnemyDiff                          ; get horizontal difference between player and enemy
	BPL SFcRt                                    ; if enemy is to the right of player, do not increment
	INY                                          ; otherwise, increment to set to move to the left
SFcRt:
	STY Enemy_MovingDir,x                        ; set moving direction here
	DEY                                          ; then decrement to use as a proper offset
	RTS

SetupFloateyNumber:
	STA FloateyNum_Control,x                     ; set number of points control for floatey numbers
	LDA #$30
	STA FloateyNum_Timer,x                       ; set timer for floatey numbers
	LDA Enemy_Y_Position,x
	STA FloateyNum_Y_Pos,x                       ; set vertical coordinate
	LDA Enemy_Rel_XPos
	STA FloateyNum_X_Pos,x                       ; set horizontal coordinate and leave
ExSFN:
	RTS

; -------------------------------------------------------------------------------------
; $01 - used to hold enemy offset for second enemy

SetBitsMask:
	.db %10000000, %01000000, %00100000, %00010000, %00001000, %00000100, %00000010

ClearBitsMask:
	.db %01111111, %10111111, %11011111, %11101111, %11110111, %11111011, %11111101

EnemiesCollision:
	LDA FrameCounter                             ; check counter for d0 set
	LSR
	BCC ExSFN                                    ; if d0 not set, leave
	LDA AreaType
	BEQ ExSFN                                    ; if water area type, leave
	LDA Enemy_ID,x
	CMP #$15                                     ; if enemy object => $15, branch to leave
	BCS ExitECRoutine
	CMP #Lakitu                                  ; if lakitu, branch to leave
	BEQ ExitECRoutine
	CMP #PiranhaPlant                            ; if piranha plant, branch to leave
	BEQ ExitECRoutine
	LDA EnemyOffscrBitsMasked,x                  ; if masked offscreen bits nonzero, branch to leave
	BNE ExitECRoutine
	JSR GetEnemyBoundBoxOfs                      ; otherwise, do sub, get appropriate bounding box offset for
	DEX                                          ; first enemy we're going to compare, then decrement for second
	BMI ExitECRoutine                            ; branch to leave if there are no other enemies
ECLoop:
	STX $01                                      ; save enemy object buffer offset for second enemy here
	TYA                                          ; save first enemy's bounding box offset to stack
	PHA
	LDA Enemy_Flag,x                             ; check enemy object enable flag
	BEQ ReadyNextEnemy                           ; branch if flag not set
	LDA Enemy_ID,x
	CMP #$15                                     ; check for enemy object => $15
	BCS ReadyNextEnemy                           ; branch if true
	CMP #Lakitu
	BEQ ReadyNextEnemy                           ; branch if enemy object is lakitu
	CMP #PiranhaPlant
	BEQ ReadyNextEnemy                           ; branch if enemy object is piranha plant
	LDA EnemyOffscrBitsMasked,x
	BNE ReadyNextEnemy                           ; branch if masked offscreen bits set
	TXA                                          ; get second enemy object's bounding box offset
	ASL                                          ; multiply by four, then add four
	ASL
	CLC
	ADC #$04
	TAX                                          ; use as new contents of X
	JSR SprObjectCollisionCore                   ; do collision detection using the two enemies here
	LDX ObjectOffset                             ; use first enemy offset for X
	LDY $01                                      ; use second enemy offset for Y
	BCC NoEnemyCollision                         ; if carry clear, no collision, branch ahead of this
	LDA Enemy_State,x
	ORA Enemy_State,y                            ; check both enemy states for d7 set
	AND #%10000000
	BNE YesEC                                    ; branch if at least one of them is set
	LDA Enemy_CollisionBits,y                    ; load first enemy's collision-related bits
	AND SetBitsMask,x                            ; check to see if bit connected to second enemy is
	BNE ReadyNextEnemy                           ; already set, and move onto next enemy slot if set
	LDA Enemy_CollisionBits,y
	ORA SetBitsMask,x                            ; if the bit is not set, set it now
	STA Enemy_CollisionBits,y
YesEC:
	JSR ProcEnemyCollisions                      ; react according to the nature of collision
	JMP ReadyNextEnemy                           ; move onto next enemy slot

NoEnemyCollision:
	LDA Enemy_CollisionBits,y                    ; load first enemy's collision-related bits
	AND ClearBitsMask,x                          ; clear bit connected to second enemy
	STA Enemy_CollisionBits,y                    ; then move onto next enemy slot

ReadyNextEnemy:
	PLA                                          ; get first enemy's bounding box offset from the stack
	TAY                                          ; use as Y again
	LDX $01                                      ; get and decrement second enemy's object buffer offset
	DEX
	BPL ECLoop                                   ; loop until all enemy slots have been checked

ExitECRoutine:
	LDX ObjectOffset                             ; get enemy object buffer offset
	RTS                                          ; leave

ProcEnemyCollisions:
	LDA Enemy_State,y                            ; check both enemy states for d5 set
	ORA Enemy_State,x
	AND #%00100000                               ; if d5 is set in either state, or both, branch
	BNE ExitProcessEColl                         ; to leave and do nothing else at this point
	LDA Enemy_State,x
	CMP #$06                                     ; if second enemy state < $06, branch elsewhere
	BCC ProcSecondEnemyColl
	LDA Enemy_ID,x                               ; check second enemy identifier for hammer bro
	CMP #HammerBro                               ; if hammer bro found in alt state, branch to leave
	BEQ ExitProcessEColl
	LDA Enemy_State,y                            ; check first enemy state for d7 set
	ASL
	BCC ShellCollisions                          ; branch if d7 is clear
	LDA #$06
	JSR SetupFloateyNumber                       ; award 1000 points for killing enemy
	JSR ShellOrBlockDefeat                       ; then kill enemy, then load
	LDY $01                                      ; original offset of second enemy

ShellCollisions:
	TYA                                          ; move Y to X
	TAX
	JSR ShellOrBlockDefeat                       ; kill second enemy
	LDX ObjectOffset
	LDA ShellChainCounter,x                      ; get chain counter for shell
	CLC
	ADC #$04                                     ; add four to get appropriate point offset
	LDX $01
	JSR SetupFloateyNumber                       ; award appropriate number of points for second enemy
	LDX ObjectOffset                             ; load original offset of first enemy
	INC ShellChainCounter,x                      ; increment chain counter for additional enemies

ExitProcessEColl:
	RTS                                          ; leave!!!

ProcSecondEnemyColl:
	LDA Enemy_State,y                            ; if first enemy state < $06, branch elsewhere
	CMP #$06
	BCC MoveEOfs
	LDA Enemy_ID,y                               ; check first enemy identifier for hammer bro
	CMP #HammerBro                               ; if hammer bro found in alt state, branch to leave
	BEQ ExitProcessEColl
	JSR ShellOrBlockDefeat                       ; otherwise, kill first enemy
	LDY $01
	LDA ShellChainCounter,y                      ; get chain counter for shell
	CLC
	ADC #$04                                     ; add four to get appropriate point offset
	LDX ObjectOffset
	JSR SetupFloateyNumber                       ; award appropriate number of points for first enemy
	LDX $01                                      ; load original offset of second enemy
	INC ShellChainCounter,x                      ; increment chain counter for additional enemies
	RTS                                          ; leave!!!

MoveEOfs:
	TYA                                          ; move Y ($01) to X
	TAX
	JSR EnemyTurnAround                          ; do the sub here using value from $01
	LDX ObjectOffset                             ; then do it again using value from $08

EnemyTurnAround:
	LDA Enemy_ID,x                               ; check for specific enemies
	CMP #PiranhaPlant
	BEQ ExTA                                     ; if piranha plant, leave
	CMP #Lakitu
	BEQ ExTA                                     ; if lakitu, leave
	CMP #HammerBro
	BEQ ExTA                                     ; if hammer bro, leave
	CMP #Spiny
	BEQ RXSpd                                    ; if spiny, turn it around
	CMP #GreenParatroopaJump
	BEQ RXSpd                                    ; if green paratroopa, turn it around
	CMP #$07
	BCS ExTA                                     ; if any OTHER enemy object => $07, leave
RXSpd:
	LDA Enemy_X_Speed,x                          ; load horizontal speed
	EOR #$ff                                     ; get two's compliment for horizontal speed
	TAY
	INY
	STY Enemy_X_Speed,x                          ; store as new horizontal speed
	LDA Enemy_MovingDir,x
	EOR #%00000011                               ; invert moving direction and store, then leave
	STA Enemy_MovingDir,x                        ; thus effectively turning the enemy around
ExTA:
	RTS                                          ; leave!!!

; -------------------------------------------------------------------------------------
; $00 - vertical position of platform

LargePlatformCollision:
	LDA #$ff                                     ; save value here
	STA PlatformCollisionFlag,x
	LDA TimerControl                             ; check master timer control
	BNE ExLPC                                    ; if set, branch to leave
	LDA Enemy_State,x                            ; if d7 set in object state,
	BMI ExLPC                                    ; branch to leave
	LDA Enemy_ID,x
	CMP #$24                                     ; check enemy object identifier for
	BNE ChkForPlayerC_LargeP                     ; balance platform, branch if not found
	LDA Enemy_State,x
	TAX                                          ; set state as enemy offset here
	JSR ChkForPlayerC_LargeP                     ; perform code with state offset, then original offset, in X

ChkForPlayerC_LargeP:
	JSR CheckPlayerVertical                      ; figure out if player is below a certain point
	BCS ExLPC                                    ; or offscreen, branch to leave if true
	TXA
	JSR GetEnemyBoundBoxOfsArg                   ; get bounding box offset in Y
	LDA Enemy_Y_Position,x                       ; store vertical coordinate in
	STA $00                                      ; temp variable for now
	TXA                                          ; send offset we're on to the stack
	PHA
	JSR PlayerCollisionCore                      ; do player-to-platform collision detection
	PLA                                          ; retrieve offset from the stack
	TAX
	BCC ExLPC                                    ; if no collision, branch to leave
	JSR ProcLPlatCollisions                      ; otherwise collision, perform sub
ExLPC:
	LDX ObjectOffset                             ; get enemy object buffer offset and leave
	RTS

; --------------------------------
; $00 - counter for bounding boxes

SmallPlatformCollision:
	LDA TimerControl                             ; if master timer control set,
	BNE ExSPC                                    ; branch to leave
	STA PlatformCollisionFlag,x                  ; otherwise initialize collision flag
	JSR CheckPlayerVertical                      ; do a sub to see if player is below a certain point
	BCS ExSPC                                    ; or entirely offscreen, and branch to leave if true
	LDA #$02
	STA $00                                      ; load counter here for 2 bounding boxes

ChkSmallPlatLoop:
	LDX ObjectOffset                             ; get enemy object offset
	JSR GetEnemyBoundBoxOfs                      ; get bounding box offset in Y
	AND #%00000010                               ; if d1 of offscreen lower nybble bits was set
	BNE ExSPC                                    ; then branch to leave
	LDA BoundingBox_UL_YPos,y                    ; check top of platform's bounding box for being
	CMP #$20                                     ; above a specific point
	BCC MoveBoundBox                             ; if so, branch, don't do collision detection
	JSR PlayerCollisionCore                      ; otherwise, perform player-to-platform collision detection
	BCS ProcSPlatCollisions                      ; skip ahead if collision

MoveBoundBox:
	LDA BoundingBox_UL_YPos,y                    ; move bounding box vertical coordinates
	CLC                                          ; 128 pixels downwards
	ADC #$80
	STA BoundingBox_UL_YPos,y
	LDA BoundingBox_DR_YPos,y
	CLC
	ADC #$80
	STA BoundingBox_DR_YPos,y
	DEC $00                                      ; decrement counter we set earlier
	BNE ChkSmallPlatLoop                         ; loop back until both bounding boxes are checked
ExSPC:
	LDX ObjectOffset                             ; get enemy object buffer offset, then leave
	RTS

; --------------------------------

ProcSPlatCollisions:
	LDX ObjectOffset                             ; return enemy object buffer offset to X, then continue

ProcLPlatCollisions:
	LDA BoundingBox_DR_YPos,y                    ; get difference by subtracting the top
	SEC                                          ; of the player's bounding box from the bottom
	SBC BoundingBox_UL_YPos                      ; of the platform's bounding box
	CMP #$04                                     ; if difference too large or negative,
	BCS ChkForTopCollision                       ; branch, do not alter vertical speed of player
	LDA Player_Y_Speed                           ; check to see if player's vertical speed is moving down
	BPL ChkForTopCollision                       ; if so, don't mess with it
	LDA #$01                                     ; otherwise, set vertical
	STA Player_Y_Speed                           ; speed of player to kill jump

ChkForTopCollision:
	LDA BoundingBox_DR_YPos                      ; get difference by subtracting the top
	SEC                                          ; of the platform's bounding box from the bottom
	SBC BoundingBox_UL_YPos,y                    ; of the player's bounding box
	CMP #$06
	BCS PlatformSideCollisions                   ; if difference not close enough, skip all of this
	LDA Player_Y_Speed
	BMI PlatformSideCollisions                   ; if player's vertical speed moving upwards, skip this
	LDA $00                                      ; get saved bounding box counter from earlier
	LDY Enemy_ID,x
	CPY #$2b                                     ; if either of the two small platform objects are found,
	BEQ SetCollisionFlag                         ; regardless of which one, branch to use bounding box counter
	CPY #$2c                                     ; as contents of collision flag
	BEQ SetCollisionFlag
	TXA                                          ; otherwise use enemy object buffer offset

SetCollisionFlag:
	LDX ObjectOffset                             ; get enemy object buffer offset
	STA PlatformCollisionFlag,x                  ; save either bounding box counter or enemy offset here
	LDA #$00
	STA Player_State                             ; set player state to normal then leave
	RTS

PlatformSideCollisions:
	LDA #$01                                     ; set value here to indicate possible horizontal
	STA $00                                      ; collision on left side of platform
	LDA BoundingBox_DR_XPos                      ; get difference by subtracting platform's left edge
	SEC                                          ; from player's right edge
	SBC BoundingBox_UL_XPos,y
	CMP #$08                                     ; if difference close enough, skip all of this
	BCC SideC
	INC $00                                      ; otherwise increment value set here for right side collision
	LDA BoundingBox_DR_XPos,y                    ; get difference by subtracting player's left edge
	CLC                                          ; from platform's right edge
	SBC BoundingBox_UL_XPos
	CMP #$09                                     ; if difference not close enough, skip subroutine
	BCS NoSideC                                  ; and instead branch to leave (no collision)
SideC:
	JSR ImpedePlayerMove                         ; deal with horizontal collision
NoSideC:
	LDX ObjectOffset                             ; return with enemy object buffer offset
	RTS

; -------------------------------------------------------------------------------------

PlayerPosSPlatData:
	.db $80, $00

PositionPlayerOnS_Plat:
	TAY                                          ; use bounding box counter saved in collision flag
	LDA Enemy_Y_Position,x                       ; for offset
	CLC                                          ; add positioning data using offset to the vertical
	ADC PlayerPosSPlatData-1,y                   ; coordinate
	.db $2c                                      ; BIT instruction opcode

PositionPlayerOnVPlat:
	LDA Enemy_Y_Position,x                       ; get vertical coordinate
	LDY GameEngineSubroutine
	CPY #$0b                                     ; if certain routine being executed on this frame,
	BEQ ExPlPos                                  ; skip all of this
	LDY Enemy_Y_HighPos,x
	CPY #$01                                     ; if vertical high byte offscreen, skip this
	BNE ExPlPos
	SEC                                          ; subtract 32 pixels from vertical coordinate
	SBC #$20                                     ; for the player object's height
	STA Player_Y_Position                        ; save as player's new vertical coordinate
	TYA
	SBC #$00                                     ; subtract borrow and store as player's
	STA Player_Y_HighPos                         ; new vertical high byte
	LDA #$00
	STA Player_Y_Speed                           ; initialize vertical speed and low byte of force
	STA Player_Y_MoveForce                       ; and then leave
ExPlPos:
	RTS

; -------------------------------------------------------------------------------------

CheckPlayerVertical:
	LDA Player_OffscreenBits                     ; if player object is completely offscreen
	CMP #$f0                                     ; vertically, leave this routine
	BCS ExCPV
	LDY Player_Y_HighPos                         ; if player high vertical byte is not
	DEY                                          ; within the screen, leave this routine
	BNE ExCPV
	LDA Player_Y_Position                        ; if on the screen, check to see how far down
	CMP #$d0                                     ; the player is vertically
ExCPV:
	RTS

; -------------------------------------------------------------------------------------

GetEnemyBoundBoxOfs:
	LDA ObjectOffset                             ; get enemy object buffer offset

GetEnemyBoundBoxOfsArg:
	ASL                                          ; multiply A by four, then add four
	ASL                                          ; to skip player's bounding box
	CLC
	ADC #$04
	TAY                                          ; send to Y
	LDA Enemy_OffscreenBits                      ; get offscreen bits for enemy object
	AND #%00001111                               ; save low nybble
	CMP #%00001111                               ; check for all bits set
	RTS

; -------------------------------------------------------------------------------------
; $00-$01 - used to hold many values, essentially temp variables
; $04 - holds lower nybble of vertical coordinate from block buffer routine
; $eb - used to hold block buffer adder

PlayerBGUpperExtent:
	.db $20, $10

PlayerBGCollision:
	LDA DisableCollisionDet                      ; if collision detection disabled flag set,
	BNE ExPBGCol                                 ; branch to leave
	LDA GameEngineSubroutine
	CMP #$0b                                     ; if running routine #11 or $0b
	BEQ ExPBGCol                                 ; branch to leave
	CMP #$04
	BCC ExPBGCol                                 ; if running routines $00-$03 branch to leave
	LDA #$01                                     ; load default player state for swimming
	LDY SwimmingFlag                             ; if swimming flag set,
	BNE SetPSte                                  ; branch ahead to set default state
	LDA Player_State                             ; if player in normal state,
	BEQ SetFallS                                 ; branch to set default state for falling
	CMP #$03
	BNE ChkOnScr                                 ; if in any other state besides climbing, skip to next part
SetFallS:
	LDA #$02                                     ; load default player state for falling
SetPSte:
	STA Player_State                             ; set whatever player state is appropriate
ChkOnScr:
	LDA Player_Y_HighPos
	CMP #$01                                     ; check player's vertical high byte for still on the screen
	BNE ExPBGCol                                 ; branch to leave if not
	LDA #$ff
	STA Player_CollisionBits                     ; initialize player's collision flag
	LDA Player_Y_Position
	CMP #$cf                                     ; check player's vertical coordinate
	BCC ChkCollSize                              ; if not too close to the bottom of screen, continue
ExPBGCol:
	RTS                                          ; otherwise leave

ChkCollSize:
	LDY #$02                                     ; load default offset
	LDA CrouchingFlag
	BNE GBBAdr                                   ; if player crouching, skip ahead
	LDA PlayerSize
	BNE GBBAdr                                   ; if player small, skip ahead
	DEY                                          ; otherwise decrement offset for big player not crouching
	LDA SwimmingFlag
	BNE GBBAdr                                   ; if swimming flag set, skip ahead
	DEY                                          ; otherwise decrement offset
GBBAdr:
	LDA BlockBufferAdderData,y                   ; get value using offset
	STA $eb                                      ; store value here
	TAY                                          ; put value into Y, as offset for block buffer routine
	LDX PlayerSize                               ; get player's size as offset
	LDA CrouchingFlag
	BEQ HeadChk                                  ; if player not crouching, branch ahead
	INX                                          ; otherwise increment size as offset
HeadChk:
	LDA Player_Y_Position                        ; get player's vertical coordinate
	CMP PlayerBGUpperExtent,x                    ; compare with upper extent value based on offset
	BCC DoFootCheck                              ; if player is too high, skip this part
	JSR BlockBufferColli_Head                    ; do player-to-bg collision detection on top of
	BEQ DoFootCheck                              ; player, and branch if nothing above player's head
	JSR CheckForCoinMTiles                       ; check to see if player touched coin with their head
	BCS AwardTouchedCoin                         ; if so, branch to some other part of code
	LDY Player_Y_Speed                           ; check player's vertical speed
	BPL DoFootCheck                              ; if player not moving upwards, branch elsewhere
	LDY $04                                      ; check lower nybble of vertical coordinate returned
	CPY #$04                                     ; from collision detection routine
	BCC DoFootCheck                              ; if low nybble < 4, branch
	JSR CheckForSolidMTiles                      ; check to see what player's head bumped on
	BCS SolidOrClimb                             ; if player collided with solid metatile, branch
	LDY AreaType                                 ; otherwise check area type
	BEQ NYSpd                                    ; if water level, branch ahead
	LDY BlockBounceTimer                         ; if block bounce timer not expired,
	BNE NYSpd                                    ; branch ahead, do not process collision
	JSR PlayerHeadCollision                      ; otherwise do a sub to process collision
	JMP DoFootCheck                              ; jump ahead to skip these other parts here

SolidOrClimb:
	CMP #$26                                     ; if climbing metatile,
	BEQ NYSpd                                    ; branch ahead and do not play sound
	LDA #Sfx_Bump
	STA Square1SoundQueue                        ; otherwise load bump sound
NYSpd:
	LDA #$01                                     ; set player's vertical speed to nullify
	STA Player_Y_Speed                           ; jump or swim

DoFootCheck:
	LDY $eb                                      ; get block buffer adder offset
	LDA Player_Y_Position
	CMP #$cf                                     ; check to see how low player is
	BCS DoPlayerSideCheck                        ; if player is too far down on screen, skip all of this
	JSR BlockBufferColli_Feet                    ; do player-to-bg collision detection on bottom left of player
	JSR CheckForCoinMTiles                       ; check to see if player touched coin with their left foot
	BCS AwardTouchedCoin                         ; if so, branch to some other part of code
	PHA                                          ; save bottom left metatile to stack
	JSR BlockBufferColli_Feet                    ; do player-to-bg collision detection on bottom right of player
	STA $00                                      ; save bottom right metatile here
	PLA
	STA $01                                      ; pull bottom left metatile and save here
	BNE ChkFootMTile                             ; if anything here, skip this part
	LDA $00                                      ; otherwise check for anything in bottom right metatile
	BEQ DoPlayerSideCheck                        ; and skip ahead if not
	JSR CheckForCoinMTiles                       ; check to see if player touched coin with their right foot
	BCC ChkFootMTile                             ; if not, skip unconditional jump and continue code

AwardTouchedCoin:
	JMP HandleCoinMetatile                       ; follow the code to erase coin and award to player 1 coin

ChkFootMTile:
	JSR CheckForClimbMTiles                      ; check to see if player landed on climbable metatiles
	BCS DoPlayerSideCheck                        ; if so, branch
	LDY Player_Y_Speed                           ; check player's vertical speed
	BMI DoPlayerSideCheck                        ; if player moving upwards, branch
	CMP #$c5
	BNE ContChk                                  ; if player did not touch axe, skip ahead
	JMP HandleAxeMetatile                        ; otherwise jump to set modes of operation
ContChk:
	JSR ChkInvisibleMTiles                       ; do sub to check for hidden coin or 1-up blocks
	BEQ DoPlayerSideCheck                        ; if either found, branch
	LDY JumpspringAnimCtrl                       ; if jumpspring animating right now,
	BNE InitSteP                                 ; branch ahead
	LDY $04                                      ; check lower nybble of vertical coordinate returned
	CPY #$05                                     ; from collision detection routine
	BCC LandPlyr                                 ; if lower nybble < 5, branch
	LDA Player_MovingDir
	STA $00                                      ; use player's moving direction as temp variable
	JMP ImpedePlayerMove                         ; jump to impede player's movement in that direction
LandPlyr:
	JSR ChkForLandJumpSpring                     ; do sub to check for jumpspring metatiles and deal with it
	LDA #$f0
	AND Player_Y_Position                        ; mask out lower nybble of player's vertical position
	STA Player_Y_Position                        ; and store as new vertical position to land player properly
	JSR HandlePipeEntry                          ; do sub to process potential pipe entry
	LDA #$00
	STA Player_Y_Speed                           ; initialize vertical speed and fractional
	STA Player_Y_MoveForce                       ; movement force to stop player's vertical movement
	STA StompChainCounter                        ; initialize enemy stomp counter
InitSteP:
	LDA #$00
	STA Player_State                             ; set player's state to normal

DoPlayerSideCheck:
	LDY $eb                                      ; get block buffer adder offset
	INY
	INY                                          ; increment offset 2 bytes to use adders for side collisions
	LDA #$02                                     ; set value here to be used as counter
	STA $00

SideCheckLoop:
	INY                                          ; move onto the next one
	STY $eb                                      ; store it
	LDA Player_Y_Position
	CMP #$20                                     ; check player's vertical position
	BCC BHalf                                    ; if player is in status bar area, branch ahead to skip this part
	CMP #$e4
	BCS ExSCH                                    ; branch to leave if player is too far down
	JSR BlockBufferColli_Side                    ; do player-to-bg collision detection on one half of player
	BEQ BHalf                                    ; branch ahead if nothing found
	CMP #$1c                                     ; otherwise check for pipe metatiles
	BEQ BHalf                                    ; if collided with sideways pipe (top), branch ahead
	CMP #$6b
	BEQ BHalf                                    ; if collided with water pipe (top), branch ahead
	JSR CheckForClimbMTiles                      ; do sub to see if player bumped into anything climbable
	BCC CheckSideMTiles                          ; if not, branch to alternate section of code
BHalf:
	LDY $eb                                      ; load block adder offset
	INY                                          ; increment it
	LDA Player_Y_Position                        ; get player's vertical position
	CMP #$08
	BCC ExSCH                                    ; if too high, branch to leave
	CMP #$d0
	BCS ExSCH                                    ; if too low, branch to leave
	JSR BlockBufferColli_Side                    ; do player-to-bg collision detection on other half of player
	BNE CheckSideMTiles                          ; if something found, branch
	DEC $00                                      ; otherwise decrement counter
	BNE SideCheckLoop                            ; run code until both sides of player are checked
ExSCH:
	RTS                                          ; leave

CheckSideMTiles:
	JSR ChkInvisibleMTiles                       ; check for hidden or coin 1-up blocks
	BEQ ExCSM                                    ; branch to leave if either found
	JSR CheckForClimbMTiles                      ; check for climbable metatiles
	BCC ContSChk                                 ; if not found, skip and continue with code
	JMP HandleClimbing                           ; otherwise jump to handle climbing
ContSChk:
	JSR CheckForCoinMTiles                       ; check to see if player touched coin
	BCS HandleCoinMetatile                       ; if so, execute code to erase coin and award to player 1 coin
	JSR ChkJumpspringMetatiles                   ; check for jumpspring metatiles
	BCC ChkPBtm                                  ; if not found, branch ahead to continue cude
	LDA JumpspringAnimCtrl                       ; otherwise check jumpspring animation control
	BNE ExCSM                                    ; branch to leave if set
	JMP StopPlayerMove                           ; otherwise jump to impede player's movement
ChkPBtm:
	LDY Player_State                             ; get player's state
	CPY #$00                                     ; check for player's state set to normal
	BNE StopPlayerMove                           ; if not, branch to impede player's movement
	LDY PlayerFacingDir                          ; get player's facing direction
	DEY
	BNE StopPlayerMove                           ; if facing left, branch to impede movement
	CMP #$6c                                     ; otherwise check for pipe metatiles
	BEQ PipeDwnS                                 ; if collided with sideways pipe (bottom), branch
	CMP #$1f                                     ; if collided with water pipe (bottom), continue
	BNE StopPlayerMove                           ; otherwise branch to impede player's movement
PipeDwnS:
	LDA Player_SprAttrib                         ; check player's attributes
	BNE PlyrPipe                                 ; if already set, branch, do not play sound again
	LDY #Sfx_PipeDown_Injury
	STY Square1SoundQueue                        ; otherwise load pipedown/injury sound
PlyrPipe:
	ORA #%00100000
	STA Player_SprAttrib                         ; set background priority bit in player attributes
	LDA Player_X_Position
	AND #%00001111                               ; get lower nybble of player's horizontal coordinate
	BEQ ChkGERtn                                 ; if at zero, branch ahead to skip this part
	LDY #$00                                     ; set default offset for timer setting data
	LDA ScreenLeft_PageLoc                       ; load page location for left side of screen
	BEQ SetCATmr                                 ; if at page zero, use default offset
	INY                                          ; otherwise increment offset
SetCATmr:
	LDA AreaChangeTimerData,y                    ; set timer for change of area as appropriate
	STA ChangeAreaTimer
ChkGERtn:
	LDA GameEngineSubroutine                     ; get number of game engine routine running
	CMP #$07
	BEQ ExCSM                                    ; if running player entrance routine or
	CMP #$08                                     ; player control routine, go ahead and branch to leave
	BNE ExCSM
	LDA #$02
	STA GameEngineSubroutine                     ; otherwise set sideways pipe entry routine to run
	RTS                                          ; and leave

; --------------------------------
; $02 - high nybble of vertical coordinate from block buffer
; $04 - low nybble of horizontal coordinate from block buffer
; $06-$07 - block buffer address

StopPlayerMove:
	JSR ImpedePlayerMove                         ; stop player's movement
ExCSM:
	RTS                                          ; leave

AreaChangeTimerData:
	.db $a0, $34

HandleCoinMetatile:
	JSR ErACM                                    ; do sub to erase coin metatile from block buffer
	INC CoinTallyFor1Ups                         ; increment coin tally used for 1-up blocks
	JMP GiveOneCoin                              ; update coin amount and tally on the screen

HandleAxeMetatile:
	LDA #$00
	STA OperMode_Task                            ; reset secondary mode
	LDA #$02
	STA OperMode                                 ; set primary mode to autoctrl mode
	LDA #$18
	STA Player_X_Speed                           ; set horizontal speed and continue to erase axe metatile
ErACM:
	LDY $02                                      ; load vertical high nybble offset for block buffer
	LDA #$00                                     ; load blank metatile
	STA ($06),y                                  ; store to remove old contents from block buffer
	JMP RemoveCoin_Axe                           ; update the screen accordingly

; --------------------------------
; $02 - high nybble of vertical coordinate from block buffer
; $04 - low nybble of horizontal coordinate from block buffer
; $06-$07 - block buffer address

ClimbXPosAdder:
	.db $f9, $07

ClimbPLocAdder:
	.db $ff, $00

FlagpoleYPosData:
	.db $18, $22, $50, $68, $90

HandleClimbing:
	LDY $04                                      ; check low nybble of horizontal coordinate returned from
	CPY #$06                                     ; collision detection routine against certain values, this
	BCC ExHC                                     ; makes actual physical part of vine or flagpole thinner
	CPY #$0a                                     ; than 16 pixels
	BCC ChkForFlagpole
ExHC:
	RTS                                          ; leave if too far left or too far right

ChkForFlagpole:
	CMP #$24                                     ; check climbing metatiles
	BEQ FlagpoleCollision                        ; branch if flagpole ball found
	CMP #$25
	BNE VineCollision                            ; branch to alternate code if flagpole shaft not found

FlagpoleCollision:
	LDA GameEngineSubroutine
	CMP #$05                                     ; check for end-of-level routine running
	BEQ PutPlayerOnVine                          ; if running, branch to end of climbing code
	LDA #$01
	STA PlayerFacingDir                          ; set player's facing direction to right
	INC ScrollLock                               ; set scroll lock flag
	LDA GameEngineSubroutine
	CMP #$04                                     ; check for flagpole slide routine running
	BEQ RunFR                                    ; if running, branch to end of flagpole code here
	LDA #BulletBill_CannonVar                    ; load identifier for bullet bills (cannon variant)
	JSR KillEnemies                              ; get rid of them
	LDA #Silence
	STA EventMusicQueue                          ; silence music
	LSR
	STA FlagpoleSoundQueue                       ; load flagpole sound into flagpole sound queue
	LDX #$04                                     ; start at end of vertical coordinate data
	LDA Player_Y_Position
	STA FlagpoleCollisionYPos                    ; store player's vertical coordinate here to be used later

ChkFlagpoleYPosLoop:
	CMP FlagpoleYPosData,x                       ; compare with current vertical coordinate data
	BCS MtchF                                    ; if player's => current, branch to use current offset
	DEX                                          ; otherwise decrement offset to use
	BNE ChkFlagpoleYPosLoop                      ; do this until all data is checked (use last one if all checked)
MtchF:
	STX FlagpoleScore                            ; store offset here to be used later
RunFR:
	LDA #$04
	STA GameEngineSubroutine                     ; set value to run flagpole slide routine
	JMP PutPlayerOnVine                          ; jump to end of climbing code

VineCollision:
	CMP #$26                                     ; check for climbing metatile used on vines
	BNE PutPlayerOnVine
	LDA Player_Y_Position                        ; check player's vertical coordinate
	CMP #$20                                     ; for being in status bar area
	BCS PutPlayerOnVine                          ; branch if not that far up
	LDA #$01
	STA GameEngineSubroutine                     ; otherwise set to run autoclimb routine next frame

PutPlayerOnVine:
	LDA #$03                                     ; set player state to climbing
	STA Player_State
	LDA #$00                                     ; nullify player's horizontal speed
	STA Player_X_Speed                           ; and fractional horizontal movement force
	STA Player_X_MoveForce
	LDA Player_X_Position                        ; get player's horizontal coordinate
	SEC
	SBC ScreenLeft_X_Pos                         ; subtract from left side horizontal coordinate
	CMP #$10
	BCS SetVXPl                                  ; if 16 or more pixels difference, do not alter facing direction
	LDA #$02
	STA PlayerFacingDir                          ; otherwise force player to face left
SetVXPl:
	LDY PlayerFacingDir                          ; get current facing direction, use as offset
	LDA $06                                      ; get low byte of block buffer address
	ASL
	ASL                                          ; move low nybble to high
	ASL
	ASL
	CLC
	ADC ClimbXPosAdder-1,y                       ; add pixels depending on facing direction
	STA Player_X_Position                        ; store as player's horizontal coordinate
	LDA $06                                      ; get low byte of block buffer address again
	BNE ExPVne                                   ; if not zero, branch
	LDA ScreenRight_PageLoc                      ; load page location of right side of screen
	CLC
	ADC ClimbPLocAdder-1,y                       ; add depending on facing location
	STA Player_PageLoc                           ; store as player's page location
ExPVne:
	RTS                                          ; finally, we're done!

; --------------------------------

ChkInvisibleMTiles:
	CMP #$5f                                     ; check for hidden coin block
	BEQ ExCInvT                                  ; branch to leave if found
	CMP #$60                                     ; check for hidden 1-up block
ExCInvT:
	RTS                                          ; leave with zero flag set if either found

; --------------------------------
; $00-$01 - used to hold bottom right and bottom left metatiles (in that order)
; $00 - used as flag by ImpedePlayerMove to restrict specific movement

ChkForLandJumpSpring:
	JSR ChkJumpspringMetatiles                   ; do sub to check if player landed on jumpspring
	BCC ExCJSp                                   ; if carry not set, jumpspring not found, therefore leave
	LDA #$70
	STA VerticalForce                            ; otherwise set vertical movement force for player
	LDA #$f9
	STA JumpspringForce                          ; set default jumpspring force
	LDA #$03
	STA JumpspringTimer                          ; set jumpspring timer to be used later
	LSR
	STA JumpspringAnimCtrl                       ; set jumpspring animation control to start animating
ExCJSp:
	RTS                                          ; and leave

ChkJumpspringMetatiles:
	CMP #$67                                     ; check for top jumpspring metatile
	BEQ JSFnd                                    ; branch to set carry if found
	CMP #$68                                     ; check for bottom jumpspring metatile
	CLC                                          ; clear carry flag
	BNE NoJSFnd                                  ; branch to use cleared carry if not found
JSFnd:
	SEC                                          ; set carry if found
NoJSFnd:
	RTS                                          ; leave

HandlePipeEntry:
	LDA Up_Down_Buttons                          ; check saved controller bits from earlier
	AND #%00000100                               ; for pressing down
	BEQ ExPipeE                                  ; if not pressing down, branch to leave
	LDA $00
	CMP #$11                                     ; check right foot metatile for warp pipe right metatile
	BNE ExPipeE                                  ; branch to leave if not found
	LDA $01
	CMP #$10                                     ; check left foot metatile for warp pipe left metatile
	BNE ExPipeE                                  ; branch to leave if not found
	LDA #$30
	STA ChangeAreaTimer                          ; set timer for change of area
	LDA #$03
	STA GameEngineSubroutine                     ; set to run vertical pipe entry routine on next frame
	LDA #Sfx_PipeDown_Injury
	STA Square1SoundQueue                        ; load pipedown/injury sound
	LDA #%00100000
	STA Player_SprAttrib                         ; set background priority bit in player's attributes
	LDA WarpZoneControl                          ; check warp zone control
	BEQ ExPipeE                                  ; branch to leave if none found
	AND #%00000011                               ; mask out all but 2 LSB
	ASL
	ASL                                          ; multiply by four
	TAX                                          ; save as offset to warp zone numbers (starts at left pipe)
	LDA Player_X_Position                        ; get player's horizontal position
	CMP #$60
	BCC GetWNum                                  ; if player at left, not near middle, use offset and skip ahead
	INX                                          ; otherwise increment for middle pipe
	CMP #$a0
	BCC GetWNum                                  ; if player at middle, but not too far right, use offset and skip
	INX                                          ; otherwise increment for last pipe
GetWNum:
	LDY WarpZoneNumbers,x                        ; get warp zone numbers
	DEY                                          ; decrement for use as world number
	STY WorldNumber                              ; store as world number and offset
	LDX WorldAddrOffsets,y                       ; get offset to where this world's area offsets are
	LDA AreaAddrOffsets,x                        ; get area offset based on world offset
	STA AreaPointer                              ; store area offset here to be used to change areas
	LDA #Silence
	STA EventMusicQueue                          ; silence music
	LDA #$00
	STA EntrancePage                             ; initialize starting page number
	STA AreaNumber                               ; initialize area number used for area address offset
	STA LevelNumber                              ; initialize level number used for world display
	STA AltEntranceControl                       ; initialize mode of entry
	INC Hidden1UpFlag                            ; set flag for hidden 1-up blocks
	INC FetchNewGameTimerFlag                    ; set flag to load new game timer
ExPipeE:
	RTS                                          ; leave!!!

ImpedePlayerMove:
	LDA #$00                                     ; initialize value here
	LDY Player_X_Speed                           ; get player's horizontal speed
	LDX $00                                      ; check value set earlier for
	DEX                                          ; left side collision
	BNE RImpd                                    ; if right side collision, skip this part
	INX                                          ; return value to X
	CPY #$00                                     ; if player moving to the left,
	BMI ExIPM                                    ; branch to invert bit and leave
	LDA #$ff                                     ; otherwise load A with value to be used later
	JMP NXSpd                                    ; and jump to affect movement
RImpd:
	LDX #$02                                     ; return $02 to X
	CPY #$01                                     ; if player moving to the right,
	BPL ExIPM                                    ; branch to invert bit and leave
	LDA #$01                                     ; otherwise load A with value to be used here
NXSpd:
	LDY #$10
	STY SideCollisionTimer                       ; set timer of some sort
	LDY #$00
	STY Player_X_Speed                           ; nullify player's horizontal speed
	CMP #$00                                     ; if value set in A not set to $ff,
	BPL PlatF                                    ; branch ahead, do not decrement Y
	DEY                                          ; otherwise decrement Y now
PlatF:
	STY $00                                      ; store Y as high bits of horizontal adder
	CLC
	ADC Player_X_Position                        ; add contents of A to player's horizontal
	STA Player_X_Position                        ; position to move player left or right
	LDA Player_PageLoc
	ADC $00                                      ; add high bits and carry to
	STA Player_PageLoc                           ; page location if necessary
ExIPM:
	TXA                                          ; invert contents of X
	EOR #$ff
	AND Player_CollisionBits                     ; mask out bit that was set here
	STA Player_CollisionBits                     ; store to clear bit
	RTS

; --------------------------------

SolidMTileUpperExt:
	.db $10, $61, $88, $c4

CheckForSolidMTiles:
	JSR GetMTileAttrib                           ; find appropriate offset based on metatile's 2 MSB
	CMP SolidMTileUpperExt,x                     ; compare current metatile with solid metatiles
	RTS

ClimbMTileUpperExt:
	.db $24, $6d, $8a, $c6

CheckForClimbMTiles:
	JSR GetMTileAttrib                           ; find appropriate offset based on metatile's 2 MSB
	CMP ClimbMTileUpperExt,x                     ; compare current metatile with climbable metatiles
	RTS

CheckForCoinMTiles:
	CMP #$c2                                     ; check for regular coin
	BEQ CoinSd                                   ; branch if found
	CMP #$c3                                     ; check for underwater coin
	BEQ CoinSd                                   ; branch if found
	CLC                                          ; otherwise clear carry and leave
	RTS
CoinSd:
	LDA #Sfx_CoinGrab
	STA Square2SoundQueue                        ; load coin grab sound and leave
	RTS

GetMTileAttrib:
	TAY                                          ; save metatile value into Y
	AND #%11000000                               ; mask out all but 2 MSB
	ASL
	ROL                                          ; shift and rotate d7-d6 to d1-d0
	ROL
	TAX                                          ; use as offset for metatile data
	TYA                                          ; get original metatile value back
ExEBG:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------
; $06-$07 - address from block buffer routine

EnemyBGCStateData:
	.db $01, $01, $02, $02, $02, $05

EnemyBGCXSpdData:
	.db $10, $f0

EnemyToBGCollisionDet:
	LDA Enemy_State,x                            ; check enemy state for d6 set
	AND #%00100000
	BNE ExEBG                                    ; if set, branch to leave
	JSR SubtEnemyYPos                            ; otherwise, do a subroutine here
	BCC ExEBG                                    ; if enemy vertical coord + 62 < 68, branch to leave
	LDY Enemy_ID,x
	CPY #Spiny                                   ; if enemy object is not spiny, branch elsewhere
	BNE DoIDCheckBGColl
	LDA Enemy_Y_Position,x
	CMP #$25                                     ; if enemy vertical coordinate < 36 branch to leave
	BCC ExEBG

DoIDCheckBGColl:
	CPY #GreenParatroopaJump                     ; check for some other enemy object
	BNE HBChk                                    ; branch if not found
	JMP EnemyJump                                ; otherwise jump elsewhere
HBChk:
	CPY #HammerBro                               ; check for hammer bro
	BNE CInvu                                    ; branch if not found
	JMP HammerBroBGColl                          ; otherwise jump elsewhere
CInvu:
	CPY #Spiny                                   ; if enemy object is spiny, branch
	BEQ YesIn
	CPY #PowerUpObject                           ; if special power-up object, branch
	BEQ YesIn
	CPY #$07                                     ; if enemy object =>$07, branch to leave
	BCS ExEBGChk
YesIn:
	JSR ChkUnderEnemy                            ; if enemy object < $07, or = $12 or $2e, do this sub
	BNE HandleEToBGCollision                     ; if block underneath enemy, branch

NoEToBGCollision:
	JMP ChkForRedKoopa                           ; otherwise skip and do something else

; --------------------------------
; $02 - vertical coordinate from block buffer routine

HandleEToBGCollision:
	JSR ChkForNonSolids                          ; if something is underneath enemy, find out what
	BEQ NoEToBGCollision                         ; if blank $26, coins, or hidden blocks, jump, enemy falls through
	CMP #$23
	BNE LandEnemyProperly                        ; check for blank metatile $23 and branch if not found
	LDY $02                                      ; get vertical coordinate used to find block
	LDA #$00                                     ; store default blank metatile in that spot so we won't
	STA ($06),y                                  ; trigger this routine accidentally again
	LDA Enemy_ID,x
	CMP #$15                                     ; if enemy object => $15, branch ahead
	BCS ChkToStunEnemies
	CMP #Goomba                                  ; if enemy object not goomba, branch ahead of this routine
	BNE GiveOEPoints
	JSR KillEnemyAboveBlock                      ; if enemy object IS goomba, do this sub

GiveOEPoints:
	LDA #$01                                     ; award 100 points for hitting block beneath enemy
	JSR SetupFloateyNumber

ChkToStunEnemies:
	CMP #$09                                     ; perform many comparisons on enemy object identifier
	BCC SetStun
	CMP #$11                                     ; if the enemy object identifier is equal to the values
	BCS SetStun                                  ; $09, $0e, $0f or $10, it will be modified, and not
	CMP #$0a                                     ; modified if not any of those values, note that piranha plant will
	BCC Demote                                   ; always fail this test because A will still have vertical
	CMP #PiranhaPlant                            ; coordinate from previous addition, also these comparisons
	BCC SetStun                                  ; are only necessary if branching from $d7a1
Demote:
	AND #%00000001                               ; erase all but LSB, essentially turning enemy object
	STA Enemy_ID,x                               ; into green or red koopa troopa to demote them
SetStun:
	LDA Enemy_State,x                            ; load enemy state
	AND #%11110000                               ; save high nybble
	ORA #%00000010
	STA Enemy_State,x                            ; set d1 of enemy state
	DEC Enemy_Y_Position,x
	DEC Enemy_Y_Position,x                       ; subtract two pixels from enemy's vertical position
	LDA Enemy_ID,x
	CMP #Bloober                                 ; check for bloober object
	BEQ SetWYSpd
	LDA #$fd                                     ; set default vertical speed
	LDY AreaType
	BNE SetNotW                                  ; if area type not water, set as speed, otherwise
SetWYSpd:
	LDA #$ff                                     ; change the vertical speed
SetNotW:
	STA Enemy_Y_Speed,x                          ; set vertical speed now
	LDY #$01
	JSR PlayerEnemyDiff                          ; get horizontal difference between player and enemy object
	BPL ChkBBill                                 ; branch if enemy is to the right of player
	INY                                          ; increment Y if not
ChkBBill:
	LDA Enemy_ID,x
	CMP #BulletBill_CannonVar                    ; check for bullet bill (cannon variant)
	BEQ NoCDirF
	CMP #BulletBill_FrenzyVar                    ; check for bullet bill (frenzy variant)
	BEQ NoCDirF                                  ; branch if either found, direction does not change
	STY Enemy_MovingDir,x                        ; store as moving direction
NoCDirF:
	DEY                                          ; decrement and use as offset
	LDA EnemyBGCXSpdData,y                       ; get proper horizontal speed
	STA Enemy_X_Speed,x                          ; and store, then leave
ExEBGChk:
	RTS

; --------------------------------
; $04 - low nybble of vertical coordinate from block buffer routine

LandEnemyProperly:
	LDA $04                                      ; check lower nybble of vertical coordinate saved earlier
	SEC
	SBC #$08                                     ; subtract eight pixels
	CMP #$05                                     ; used to determine whether enemy landed from falling
	BCS ChkForRedKoopa                           ; branch if lower nybble in range of $0d-$0f before subtract
	LDA Enemy_State,x
	AND #%01000000                               ; branch if d6 in enemy state is set
	BNE LandEnemyInitState
	LDA Enemy_State,x
	ASL                                          ; branch if d7 in enemy state is not set
	BCC ChkLandedEnemyState
SChkA:
	JMP DoEnemySideCheck                         ; if lower nybble < $0d, d7 set but d6 not set, jump here

ChkLandedEnemyState:
	LDA Enemy_State,x                            ; if enemy in normal state, branch back to jump here
	BEQ SChkA
	CMP #$05                                     ; if in state used by spiny's egg
	BEQ ProcEnemyDirection                       ; then branch elsewhere
	CMP #$03                                     ; if already in state used by koopas and buzzy beetles
	BCS ExSteChk                                 ; or in higher numbered state, branch to leave
	LDA Enemy_State,x                            ; load enemy state again (why?)
	CMP #$02                                     ; if not in $02 state (used by koopas and buzzy beetles)
	BNE ProcEnemyDirection                       ; then branch elsewhere
	LDA #$10                                     ; load default timer here
	LDY Enemy_ID,x                               ; check enemy identifier for spiny
	CPY #Spiny
	BNE SetForStn                                ; branch if not found
	LDA #$00                                     ; set timer for $00 if spiny
SetForStn:
	STA EnemyIntervalTimer,x                     ; set timer here
	LDA #$03                                     ; set state here, apparently used to render
	STA Enemy_State,x                            ; upside-down koopas and buzzy beetles
	JSR EnemyLanding                             ; then land it properly
ExSteChk:
	RTS                                          ; then leave

ProcEnemyDirection:
	LDA Enemy_ID,x                               ; check enemy identifier for goomba
	CMP #Goomba                                  ; branch if found
	BEQ LandEnemyInitState
	CMP #Spiny                                   ; check for spiny
	BNE InvtD                                    ; branch if not found
	LDA #$01
	STA Enemy_MovingDir,x                        ; send enemy moving to the right by default
	LDA #$08
	STA Enemy_X_Speed,x                          ; set horizontal speed accordingly
	LDA FrameCounter
	AND #%00000111                               ; if timed appropriately, spiny will skip over
	BEQ LandEnemyInitState                       ; trying to face the player
InvtD:
	LDY #$01                                     ; load 1 for enemy to face the left (inverted here)
	JSR PlayerEnemyDiff                          ; get horizontal difference between player and enemy
	BPL CNwCDir                                  ; if enemy to the right of player, branch
	INY                                          ; if to the left, increment by one for enemy to face right (inverted)
CNwCDir:
	TYA
	CMP Enemy_MovingDir,x                        ; compare direction in A with current direction in memory
	BNE LandEnemyInitState
	JSR ChkForBump_HammerBroJ                    ; if equal, not facing in correct dir, do sub to turn around

LandEnemyInitState:
	JSR EnemyLanding                             ; land enemy properly
	LDA Enemy_State,x
	AND #%10000000                               ; if d7 of enemy state is set, branch
	BNE NMovShellFallBit
	LDA #$00                                     ; otherwise initialize enemy state and leave
	STA Enemy_State,x                            ; note this will also turn spiny's egg into spiny
	RTS

NMovShellFallBit:
	LDA Enemy_State,x                            ; nullify d6 of enemy state, save other bits
	AND #%10111111                               ; and store, then leave
	STA Enemy_State,x
	RTS

; --------------------------------

ChkForRedKoopa:
	LDA Enemy_ID,x                               ; check for red koopa troopa $03
	CMP #RedKoopa
	BNE Chk2MSBSt                                ; branch if not found
	LDA Enemy_State,x
	BEQ ChkForBump_HammerBroJ                    ; if enemy found and in normal state, branch
Chk2MSBSt:
	LDA Enemy_State,x                            ; save enemy state into Y
	TAY
	ASL                                          ; check for d7 set
	BCC GetSteFromD                              ; branch if not set
	LDA Enemy_State,x
	ORA #%01000000                               ; set d6
	JMP SetD6Ste                                 ; jump ahead of this part
GetSteFromD:
	LDA EnemyBGCStateData,y                      ; load new enemy state with old as offset
SetD6Ste:
	STA Enemy_State,x                            ; set as new state

; --------------------------------
; $00 - used to store bitmask (not used but initialized here)
; $eb - used in DoEnemySideCheck as counter and to compare moving directions

DoEnemySideCheck:
	LDA Enemy_Y_Position,x                       ; if enemy within status bar, branch to leave
	CMP #$20                                     ; because there's nothing there that impedes movement
	BCC ExESdeC
	LDY #$16                                     ; start by finding block to the left of enemy ($00,$14)
	LDA #$02                                     ; set value here in what is also used as
	STA $eb                                      ; OAM data offset
SdeCLoop:
	LDA $eb                                      ; check value
	CMP Enemy_MovingDir,x                        ; compare value against moving direction
	BNE NextSdeC                                 ; branch if different and do not seek block there
	LDA #$01                                     ; set flag in A for save horizontal coordinate
	JSR BlockBufferChk_Enemy                     ; find block to left or right of enemy object
	BEQ NextSdeC                                 ; if nothing found, branch
	JSR ChkForNonSolids                          ; check for non-solid blocks
	BNE ChkForBump_HammerBroJ                    ; branch if not found
NextSdeC:
	DEC $eb                                      ; move to the next direction
	INY
	CPY #$18                                     ; increment Y, loop only if Y < $18, thus we check
	BCC SdeCLoop                                 ; enemy ($00, $14) and ($10, $14) pixel coordinates
ExESdeC:
	RTS

ChkForBump_HammerBroJ:

	CPX #$05                                     ; check if we're on the special use slot
	BEQ NoBump                                   ; and if so, branch ahead and do not play sound
	LDA Enemy_State,x                            ; if enemy state d7 not set, branch
	ASL                                          ; ahead and do not play sound
	BCC NoBump
	LDA #Sfx_Bump                                ; otherwise, play bump sound
	STA Square1SoundQueue                        ; sound will never be played if branching from ChkForRedKoopa
NoBump:
	LDA Enemy_ID,x                               ; check for hammer bro
	CMP #$05
	BNE InvEnemyDir                              ; branch if not found
	LDA #$00
	STA $00                                      ; initialize value here for bitmask
	LDY #$fa                                     ; load default vertical speed for jumping
	JMP SetHJ                                    ; jump to code that makes hammer bro jump

InvEnemyDir:
	JMP RXSpd                                    ; jump to turn the enemy around

; --------------------------------
; $00 - used to hold horizontal difference between player and enemy

PlayerEnemyDiff:
	LDA Enemy_X_Position,x                       ; get distance between enemy object's
	SEC                                          ; horizontal coordinate and the player's
	SBC Player_X_Position                        ; horizontal coordinate
	STA $00                                      ; and store here
	LDA Enemy_PageLoc,x
	SBC Player_PageLoc                           ; subtract borrow, then leave
	RTS

; --------------------------------

EnemyLanding:
	JSR InitVStf                                 ; do something here to vertical speed and something else
	LDA Enemy_Y_Position,x
	AND #%11110000                               ; save high nybble of vertical coordinate, and
	ORA #%00001000                               ; set d3, then store, probably used to set enemy object
	STA Enemy_Y_Position,x                       ; neatly on whatever it's landing on
	RTS

SubtEnemyYPos:
	LDA Enemy_Y_Position,x                       ; add 62 pixels to enemy object's
	CLC                                          ; vertical coordinate
	ADC #$3e
	CMP #$44                                     ; compare against a certain range
	RTS                                          ; and leave with flags set for conditional branch

EnemyJump:
	JSR SubtEnemyYPos                            ; do a sub here
	BCC DoSide                                   ; if enemy vertical coord + 62 < 68, branch to leave
	LDA Enemy_Y_Speed,x
	CLC                                          ; add two to vertical speed
	ADC #$02
	CMP #$03                                     ; if green paratroopa not falling, branch ahead
	BCC DoSide
	JSR ChkUnderEnemy                            ; otherwise, check to see if green paratroopa is
	BEQ DoSide                                   ; standing on anything, then branch to same place if not
	JSR ChkForNonSolids                          ; check for non-solid blocks
	BEQ DoSide                                   ; branch if found
	JSR EnemyLanding                             ; change vertical coordinate and speed
	LDA #$fd
	STA Enemy_Y_Speed,x                          ; make the paratroopa jump again
DoSide:
	JMP DoEnemySideCheck                         ; check for horizontal blockage, then leave

; --------------------------------

HammerBroBGColl:
	JSR ChkUnderEnemy                            ; check to see if hammer bro is standing on anything
	BEQ NoUnderHammerBro
	CMP #$23                                     ; check for blank metatile $23 and branch if not found
	BNE UnderHammerBro

KillEnemyAboveBlock:
	JSR ShellOrBlockDefeat                       ; do this sub to kill enemy
	LDA #$fc                                     ; alter vertical speed of enemy and leave
	STA Enemy_Y_Speed,x
	RTS

UnderHammerBro:
	LDA EnemyFrameTimer,x                        ; check timer used by hammer bro
	BNE NoUnderHammerBro                         ; branch if not expired
	LDA Enemy_State,x
	AND #%10001000                               ; save d7 and d3 from enemy state, nullify other bits
	STA Enemy_State,x                            ; and store
	JSR EnemyLanding                             ; modify vertical coordinate, speed and something else
	JMP DoEnemySideCheck                         ; then check for horizontal blockage and leave

NoUnderHammerBro:
	LDA Enemy_State,x                            ; if hammer bro is not standing on anything, set d0
	ORA #$01                                     ; in the enemy state to indicate jumping or falling, then leave
	STA Enemy_State,x
	RTS

ChkUnderEnemy:
	LDA #$00                                     ; set flag in A for save vertical coordinate
	LDY #$15                                     ; set Y to check the bottom middle (8,18) of enemy object
	JMP BlockBufferChk_Enemy                     ; hop to it!

ChkForNonSolids:
	CMP #$26                                     ; blank metatile used for vines?
	BEQ NSFnd
	CMP #$c2                                     ; regular coin?
	BEQ NSFnd
	CMP #$c3                                     ; underwater coin?
	BEQ NSFnd
	CMP #$5f                                     ; hidden coin block?
	BEQ NSFnd
	CMP #$60                                     ; hidden 1-up block?
NSFnd:
	RTS

; -------------------------------------------------------------------------------------

FireballBGCollision:
	LDA Fireball_Y_Position,x                    ; check fireball's vertical coordinate
	CMP #$18
	BCC ClearBounceFlag                          ; if within the status bar area of the screen, branch ahead
	JSR BlockBufferChk_FBall                     ; do fireball to background collision detection on bottom of it
	BEQ ClearBounceFlag                          ; if nothing underneath fireball, branch
	JSR ChkForNonSolids                          ; check for non-solid metatiles
	BEQ ClearBounceFlag                          ; branch if any found
	LDA Fireball_Y_Speed,x                       ; if fireball's vertical speed set to move upwards,
	BMI InitFireballExplode                      ; branch to set exploding bit in fireball's state
	LDA FireballBouncingFlag,x                   ; if bouncing flag already set,
	BNE InitFireballExplode                      ; branch to set exploding bit in fireball's state
	LDA #$fd
	STA Fireball_Y_Speed,x                       ; otherwise set vertical speed to move upwards (give it bounce)
	LDA #$01
	STA FireballBouncingFlag,x                   ; set bouncing flag
	LDA Fireball_Y_Position,x
	AND #$f8                                     ; modify vertical coordinate to land it properly
	STA Fireball_Y_Position,x                    ; store as new vertical coordinate
	RTS                                          ; leave

ClearBounceFlag:
	LDA #$00
	STA FireballBouncingFlag,x                   ; clear bouncing flag by default
	RTS                                          ; leave

InitFireballExplode:
	LDA #$80
	STA Fireball_State,x                         ; set exploding flag in fireball's state
	LDA #Sfx_Bump
	STA Square1SoundQueue                        ; load bump sound
	RTS                                          ; leave

; -------------------------------------------------------------------------------------
; $00 - used to hold one of bitmasks, or offset
; $01 - used for relative X coordinate, also used to store middle screen page location
; $02 - used for relative Y coordinate, also used to store middle screen coordinate

; this data added to relative coordinates of sprite objects
; stored in order: left edge, top edge, right edge, bottom edge
BoundBoxCtrlData:
	.db $02, $08, $0e, $20
	.db $03, $14, $0d, $20
	.db $02, $14, $0e, $20
	.db $02, $09, $0e, $15
	.db $00, $00, $18, $06
	.db $00, $00, $20, $0d
	.db $00, $00, $30, $0d
	.db $00, $00, $08, $08
	.db $06, $04, $0a, $08
	.db $03, $0e, $0d, $14
	.db $00, $02, $10, $15
	.db $04, $04, $0c, $1c

GetFireballBoundBox:
	TXA                                          ; add seven bytes to offset
	CLC                                          ; to use in routines as offset for fireball
	ADC #$07
	TAX
	LDY #$02                                     ; set offset for relative coordinates
	BNE FBallB                                   ; unconditional branch

GetMiscBoundBox:
	TXA                                          ; add nine bytes to offset
	CLC                                          ; to use in routines as offset for misc object
	ADC #$09
	TAX
	LDY #$06                                     ; set offset for relative coordinates
FBallB:
	JSR BoundingBoxCore                          ; get bounding box coordinates
	JMP CheckRightScreenBBox                     ; jump to handle any offscreen coordinates

GetEnemyBoundBox:
	LDY #$48                                     ; store bitmask here for now
	STY $00
	LDY #$44                                     ; store another bitmask here for now and jump
	JMP GetMaskedOffScrBits

SmallPlatformBoundBox:
	LDY #$08                                     ; store bitmask here for now
	STY $00
	LDY #$04                                     ; store another bitmask here for now

GetMaskedOffScrBits:
	LDA Enemy_X_Position,x                       ; get enemy object position relative
	SEC                                          ; to the left side of the screen
	SBC ScreenLeft_X_Pos
	STA $01                                      ; store here
	LDA Enemy_PageLoc,x                          ; subtract borrow from current page location
	SBC ScreenLeft_PageLoc                       ; of left side
	BMI CMBits                                   ; if enemy object is beyond left edge, branch
	ORA $01
	BEQ CMBits                                   ; if precisely at the left edge, branch
	LDY $00                                      ; if to the right of left edge, use value in $00 for A
CMBits:
	TYA                                          ; otherwise use contents of Y
	AND Enemy_OffscreenBits                      ; preserve bitwise whatever's in here
	STA EnemyOffscrBitsMasked,x                  ; save masked offscreen bits here
	BNE MoveBoundBoxOffscreen                    ; if anything set here, branch
	JMP SetupEOffsetFBBox                        ; otherwise, do something else

LargePlatformBoundBox:
	INX                                          ; increment X to get the proper offset
	JSR GetXOffscreenBits                        ; then jump directly to the sub for horizontal offscreen bits
	DEX                                          ; decrement to return to original offset
	CMP #$fe                                     ; if completely offscreen, branch to put entire bounding
	BCS MoveBoundBoxOffscreen                    ; box offscreen, otherwise start getting coordinates

SetupEOffsetFBBox:
	TXA                                          ; add 1 to offset to properly address
	CLC                                          ; the enemy object memory locations
	ADC #$01
	TAX
	LDY #$01                                     ; load 1 as offset here, same reason
	JSR BoundingBoxCore                          ; do a sub to get the coordinates of the bounding box
	JMP CheckRightScreenBBox                     ; jump to handle offscreen coordinates of bounding box

MoveBoundBoxOffscreen:
	TXA                                          ; multiply offset by 4
	ASL
	ASL
	TAY                                          ; use as offset here
	LDA #$ff
	STA EnemyBoundingBoxCoord,y                  ; load value into four locations here and leave
	STA EnemyBoundingBoxCoord+1,y
	STA EnemyBoundingBoxCoord+2,y
	STA EnemyBoundingBoxCoord+3,y
	RTS

BoundingBoxCore:
	STX $00                                      ; save offset here
	LDA SprObject_Rel_YPos,y                     ; store object coordinates relative to screen
	STA $02                                      ; vertically and horizontally, respectively
	LDA SprObject_Rel_XPos,y
	STA $01
	TXA                                          ; multiply offset by four and save to stack
	ASL
	ASL
	PHA
	TAY                                          ; use as offset for Y, X is left alone
	LDA SprObj_BoundBoxCtrl,x                    ; load value here to be used as offset for X
	ASL                                          ; multiply that by four and use as X
	ASL
	TAX
	LDA $01                                      ; add the first number in the bounding box data to the
	CLC                                          ; relative horizontal coordinate using enemy object offset
	ADC BoundBoxCtrlData,x                       ; and store somewhere using same offset * 4
	STA BoundingBox_UL_Corner,y                  ; store here
	LDA $01
	CLC
	ADC BoundBoxCtrlData+2,x                     ; add the third number in the bounding box data to the
	STA BoundingBox_LR_Corner,y                  ; relative horizontal coordinate and store
	INX                                          ; increment both offsets
	INY
	LDA $02                                      ; add the second number to the relative vertical coordinate
	CLC                                          ; using incremented offset and store using the other
	ADC BoundBoxCtrlData,x                       ; incremented offset
	STA BoundingBox_UL_Corner,y
	LDA $02
	CLC
	ADC BoundBoxCtrlData+2,x                     ; add the fourth number to the relative vertical coordinate
	STA BoundingBox_LR_Corner,y                  ; and store
	PLA                                          ; get original offset loaded into $00 * y from stack
	TAY                                          ; use as Y
	LDX $00                                      ; get original offset and use as X again
	RTS

CheckRightScreenBBox:
	LDA ScreenLeft_X_Pos                         ; add 128 pixels to left side of screen
	CLC                                          ; and store as horizontal coordinate of middle
	ADC #$80
	STA $02
	LDA ScreenLeft_PageLoc                       ; add carry to page location of left side of screen
	ADC #$00                                     ; and store as page location of middle
	STA $01
	LDA SprObject_X_Position,x                   ; get horizontal coordinate
	CMP $02                                      ; compare against middle horizontal coordinate
	LDA SprObject_PageLoc,x                      ; get page location
	SBC $01                                      ; subtract from middle page location
	BCC CheckLeftScreenBBox                      ; if object is on the left side of the screen, branch
	LDA BoundingBox_DR_XPos,y                    ; check right-side edge of bounding box for offscreen
	BMI NoOfs                                    ; coordinates, branch if still on the screen
	LDA #$ff                                     ; load offscreen value here to use on one or both horizontal sides
	LDX BoundingBox_UL_XPos,y                    ; check left-side edge of bounding box for offscreen
	BMI SORte                                    ; coordinates, and branch if still on the screen
	STA BoundingBox_UL_XPos,y                    ; store offscreen value for left side
SORte:
	STA BoundingBox_DR_XPos,y                    ; store offscreen value for right side
NoOfs:
	LDX ObjectOffset                             ; get object offset and leave
	RTS

CheckLeftScreenBBox:
	LDA BoundingBox_UL_XPos,y                    ; check left-side edge of bounding box for offscreen
	BPL NoOfs2                                   ; coordinates, and branch if still on the screen
	CMP #$a0                                     ; check to see if left-side edge is in the middle of the
	BCC NoOfs2                                   ; screen or really offscreen, and branch if still on
	LDA #$00
	LDX BoundingBox_DR_XPos,y                    ; check right-side edge of bounding box for offscreen
	BPL SOLft                                    ; coordinates, branch if still onscreen
	STA BoundingBox_DR_XPos,y                    ; store offscreen value for right side
SOLft:
	STA BoundingBox_UL_XPos,y                    ; store offscreen value for left side
NoOfs2:
	LDX ObjectOffset                             ; get object offset and leave
	RTS

; -------------------------------------------------------------------------------------
; $06 - second object's offset
; $07 - counter

PlayerCollisionCore:
	LDX #$00                                     ; initialize X to use player's bounding box for comparison

SprObjectCollisionCore:
	STY $06                                      ; save contents of Y here
	LDA #$01
	STA $07                                      ; save value 1 here as counter, compare horizontal coordinates first

CollisionCoreLoop:
	LDA BoundingBox_UL_Corner,y                  ; compare left/top coordinates
	CMP BoundingBox_UL_Corner,x                  ; of first and second objects' bounding boxes
	BCS FirstBoxGreater                          ; if first left/top => second, branch
	CMP BoundingBox_LR_Corner,x                  ; otherwise compare to right/bottom of second
	BCC SecondBoxVerticalChk                     ; if first left/top < second right/bottom, branch elsewhere
	BEQ CollisionFound                           ; if somehow equal, collision, thus branch
	LDA BoundingBox_LR_Corner,y                  ; if somehow greater, check to see if bottom of
	CMP BoundingBox_UL_Corner,y                  ; first object's bounding box is greater than its top
	BCC CollisionFound                           ; if somehow less, vertical wrap collision, thus branch
	CMP BoundingBox_UL_Corner,x                  ; otherwise compare bottom of first bounding box to the top
	BCS CollisionFound                           ; of second box, and if equal or greater, collision, thus branch
	LDY $06                                      ; otherwise return with carry clear and Y = $0006
	RTS                                          ; note horizontal wrapping never occurs

SecondBoxVerticalChk:
	LDA BoundingBox_LR_Corner,x                  ; check to see if the vertical bottom of the box
	CMP BoundingBox_UL_Corner,x                  ; is greater than the vertical top
	BCC CollisionFound                           ; if somehow less, vertical wrap collision, thus branch
	LDA BoundingBox_LR_Corner,y                  ; otherwise compare horizontal right or vertical bottom
	CMP BoundingBox_UL_Corner,x                  ; of first box with horizontal left or vertical top of second box
	BCS CollisionFound                           ; if equal or greater, collision, thus branch
	LDY $06                                      ; otherwise return with carry clear and Y = $0006
	RTS

FirstBoxGreater:
	CMP BoundingBox_UL_Corner,x                  ; compare first and second box horizontal left/vertical top again
	BEQ CollisionFound                           ; if first coordinate = second, collision, thus branch
	CMP BoundingBox_LR_Corner,x                  ; if not, compare with second object right or bottom edge
	BCC CollisionFound                           ; if left/top of first less than or equal to right/bottom of second
	BEQ CollisionFound                           ; then collision, thus branch
	CMP BoundingBox_LR_Corner,y                  ; otherwise check to see if top of first box is greater than bottom
	BCC NoCollisionFound                         ; if less than or equal, no collision, branch to end
	BEQ NoCollisionFound
	LDA BoundingBox_LR_Corner,y                  ; otherwise compare bottom of first to top of second
	CMP BoundingBox_UL_Corner,x                  ; if bottom of first is greater than top of second, vertical wrap
	BCS CollisionFound                           ; collision, and branch, otherwise, proceed onwards here

NoCollisionFound:
	CLC                                          ; clear carry, then load value set earlier, then leave
	LDY $06                                      ; like previous ones, if horizontal coordinates do not collide, we do
	RTS                                          ; not bother checking vertical ones, because what's the point?

CollisionFound:
	INX                                          ; increment offsets on both objects to check
	INY                                          ; the vertical coordinates
	DEC $07                                      ; decrement counter to reflect this
	BPL CollisionCoreLoop                        ; if counter not expired, branch to loop
	SEC                                          ; otherwise we already did both sets, therefore collision, so set carry
	LDY $06                                      ; load original value set here earlier, then leave
	RTS

; -------------------------------------------------------------------------------------
; $02 - modified y coordinate
; $03 - stores metatile involved in block buffer collisions
; $04 - comes in with offset to block buffer adder data, goes out with low nybble x/y coordinate
; $05 - modified x coordinate
; $06-$07 - block buffer address

BlockBufferChk_Enemy:
	PHA                                          ; save contents of A to stack
	TXA
	CLC                                          ; add 1 to X to run sub with enemy offset in mind
	ADC #$01
	TAX
	PLA                                          ; pull A from stack and jump elsewhere
	JMP BBChk_E

ResidualMiscObjectCode:
	TXA
	CLC                                          ; supposedly used once to set offset for
	ADC #$0d                                     ; miscellaneous objects
	TAX
	LDY #$1b                                     ; supposedly used once to set offset for block buffer data
	JMP ResJmpM                                  ; probably used in early stages to do misc to bg collision detection

BlockBufferChk_FBall:
	LDY #$1a                                     ; set offset for block buffer adder data
	TXA
	CLC
	ADC #$07                                     ; add seven bytes to use
	TAX
ResJmpM:
	LDA #$00                                     ; set A to return vertical coordinate
BBChk_E:
	JSR BlockBufferCollision                     ; do collision detection subroutine for sprite object
	LDX ObjectOffset                             ; get object offset
	CMP #$00                                     ; check to see if object bumped into anything
	RTS

BlockBufferAdderData:
	.db $00, $07, $0e

BlockBuffer_X_Adder:
	.db $08, $03, $0c, $02, $02, $0d, $0d, $08
	.db $03, $0c, $02, $02, $0d, $0d, $08, $03
	.db $0c, $02, $02, $0d, $0d, $08, $00, $10
	.db $04, $14, $04, $04

BlockBuffer_Y_Adder:
	.db $04, $20, $20, $08, $18, $08, $18, $02
	.db $20, $20, $08, $18, $08, $18, $12, $20
	.db $20, $18, $18, $18, $18, $18, $14, $14
	.db $06, $06, $08, $10

BlockBufferColli_Feet:
	INY                                          ; if branched here, increment to next set of adders

BlockBufferColli_Head:
	LDA #$00                                     ; set flag to return vertical coordinate
	.db $2c                                      ; BIT instruction opcode

BlockBufferColli_Side:
	LDA #$01                                     ; set flag to return horizontal coordinate
	LDX #$00                                     ; set offset for player object

BlockBufferCollision:
	PHA                                          ; save contents of A to stack
	STY $04                                      ; save contents of Y here
	LDA BlockBuffer_X_Adder,y                    ; add horizontal coordinate
	CLC                                          ; of object to value obtained using Y as offset
	ADC SprObject_X_Position,x
	STA $05                                      ; store here
	LDA SprObject_PageLoc,x
	ADC #$00                                     ; add carry to page location
	AND #$01                                     ; get LSB, mask out all other bits
	LSR                                          ; move to carry
	ORA $05                                      ; get stored value
	ROR                                          ; rotate carry to MSB of A
	LSR                                          ; and effectively move high nybble to
	LSR                                          ; lower, LSB which became MSB will be
	LSR                                          ; d4 at this point
	JSR GetBlockBufferAddr                       ; get address of block buffer into $06, $07
	LDY $04                                      ; get old contents of Y
	LDA SprObject_Y_Position,x                   ; get vertical coordinate of object
	CLC
	ADC BlockBuffer_Y_Adder,y                    ; add it to value obtained using Y as offset
	AND #%11110000                               ; mask out low nybble
	SEC
	SBC #$20                                     ; subtract 32 pixels for the status bar
	STA $02                                      ; store result here
	TAY                                          ; use as offset for block buffer
	LDA ($06),y                                  ; check current content of block buffer
	STA $03                                      ; and store here
	LDY $04                                      ; get old contents of Y again
	PLA                                          ; pull A from stack
	BNE RetXC                                    ; if A = 1, branch
	LDA SprObject_Y_Position,x                   ; if A = 0, load vertical coordinate
	JMP RetYC                                    ; and jump
RetXC:
	LDA SprObject_X_Position,x                   ; otherwise load horizontal coordinate
RetYC:
	AND #%00001111                               ; and mask out high nybble
	STA $04                                      ; store masked out result here
	LDA $03                                      ; get saved content of block buffer
	RTS                                          ; and leave

; -------------------------------------------------------------------------------------

; -------------------------------------------------------------------------------------
; $00 - offset to vine Y coordinate adder
; $02 - offset to sprite data

VineYPosAdder:
	.db $00, $30

DrawVine:
	STY $00                                      ; save offset here
	LDA Enemy_Rel_YPos                           ; get relative vertical coordinate
	CLC
	ADC VineYPosAdder,y                          ; add value using offset in Y to get value
	LDX VineObjOffset,y                          ; get offset to vine
	LDY Enemy_SprDataOffset,x                    ; get sprite data offset
	STY $02                                      ; store sprite data offset here
	JSR SixSpriteStacker                         ; stack six sprites on top of each other vertically
	LDA Enemy_Rel_XPos                           ; get relative horizontal coordinate
	STA Sprite_X_Position,y                      ; store in first, third and fifth sprites
	STA Sprite_X_Position+8,y
	STA Sprite_X_Position+16,y
	CLC
	ADC #$06                                     ; add six pixels to second, fourth and sixth sprites
	STA Sprite_X_Position+4,y                    ; to give characteristic staggered vine shape to
	STA Sprite_X_Position+12,y                   ; our vertical stack of sprites
	STA Sprite_X_Position+20,y
	LDA #%00100001                               ; set bg priority and palette attribute bits
	STA Sprite_Attributes,y                      ; set in first, third and fifth sprites
	STA Sprite_Attributes+8,y
	STA Sprite_Attributes+16,y
	ORA #%01000000                               ; additionally, set horizontal flip bit
	STA Sprite_Attributes+4,y                    ; for second, fourth and sixth sprites
	STA Sprite_Attributes+12,y
	STA Sprite_Attributes+20,y
	LDX #$05                                     ; set tiles for six sprites
VineTL:
	LDA #$e1                                     ; set tile number for sprite
	STA Sprite_Tilenumber,y
	INY                                          ; move offset to next sprite data
	INY
	INY
	INY
	DEX                                          ; move onto next sprite
	BPL VineTL                                   ; loop until all sprites are done
	LDY $02                                      ; get original offset
	LDA $00                                      ; get offset to vine adding data
	BNE SkpVTop                                  ; if offset not zero, skip this part
	LDA #$e0
	STA Sprite_Tilenumber,y                      ; set other tile number for top of vine
SkpVTop:
	LDX #$00                                     ; start with the first sprite again
ChkFTop:
	LDA VineStart_Y_Position                     ; get original starting vertical coordinate
	SEC
	SBC Sprite_Y_Position,y                      ; subtract top-most sprite's Y coordinate
	CMP #$64                                     ; if two coordinates are less than 100/$64 pixels
	BCC NextVSp                                  ; apart, skip this to leave sprite alone
	LDA #$f8
	STA Sprite_Y_Position,y                      ; otherwise move sprite offscreen
NextVSp:
	INY                                          ; move offset to next OAM data
	INY
	INY
	INY
	INX                                          ; move onto next sprite
	CPX #$06                                     ; do this until all sprites are checked
	BNE ChkFTop
	LDY $00                                      ; return offset set earlier
	RTS

SixSpriteStacker:
	LDX #$06                                     ; do six sprites
StkLp:
	STA Sprite_Data,y                            ; store X or Y coordinate into OAM data
	CLC
	ADC #$08                                     ; add eight pixels
	INY
	INY                                          ; move offset four bytes forward
	INY
	INY
	DEX                                          ; do another sprite
	BNE StkLp                                    ; do this until all sprites are done
	LDY $02                                      ; get saved OAM data offset and leave
	RTS

; -------------------------------------------------------------------------------------

FirstSprXPos:
	.db $04, $00, $04, $00

FirstSprYPos:
	.db $00, $04, $00, $04

SecondSprXPos:
	.db $00, $08, $00, $08

SecondSprYPos:
	.db $08, $00, $08, $00

FirstSprTilenum:
	.db $80, $82, $81, $83

SecondSprTilenum:
	.db $81, $83, $80, $82

HammerSprAttrib:
	.db $03, $03, $c3, $c3

DrawHammer:
	LDY Misc_SprDataOffset,x                     ; get misc object OAM data offset
	LDA TimerControl
	BNE ForceHPose                               ; if master timer control set, skip this part
	LDA Misc_State,x                             ; otherwise get hammer's state
	AND #%01111111                               ; mask out d7
	CMP #$01                                     ; check to see if set to 1 yet
	BEQ GetHPose                                 ; if so, branch
ForceHPose:
	LDX #$00                                     ; reset offset here
	BEQ RenderH                                  ; do unconditional branch to rendering part
GetHPose:
	LDA FrameCounter                             ; get frame counter
	LSR                                          ; move d3-d2 to d1-d0
	LSR
	AND #%00000011                               ; mask out all but d1-d0 (changes every four frames)
	TAX                                          ; use as timing offset
RenderH:
	LDA Misc_Rel_YPos                            ; get relative vertical coordinate
	CLC
	ADC FirstSprYPos,x                           ; add first sprite vertical adder based on offset
	STA Sprite_Y_Position,y                      ; store as sprite Y coordinate for first sprite
	CLC
	ADC SecondSprYPos,x                          ; add second sprite vertical adder based on offset
	STA Sprite_Y_Position+4,y                    ; store as sprite Y coordinate for second sprite
	LDA Misc_Rel_XPos                            ; get relative horizontal coordinate
	CLC
	ADC FirstSprXPos,x                           ; add first sprite horizontal adder based on offset
	STA Sprite_X_Position,y                      ; store as sprite X coordinate for first sprite
	CLC
	ADC SecondSprXPos,x                          ; add second sprite horizontal adder based on offset
	STA Sprite_X_Position+4,y                    ; store as sprite X coordinate for second sprite
	LDA FirstSprTilenum,x
	STA Sprite_Tilenumber,y                      ; get and store tile number of first sprite
	LDA SecondSprTilenum,x
	STA Sprite_Tilenumber+4,y                    ; get and store tile number of second sprite
	LDA HammerSprAttrib,x
	STA Sprite_Attributes,y                      ; get and store attribute bytes for both
	STA Sprite_Attributes+4,y                    ; note in this case they use the same data
	LDX ObjectOffset                             ; get misc object offset
	LDA Misc_OffscreenBits
	AND #%11111100                               ; check offscreen bits
	BEQ NoHOffscr                                ; if all bits clear, leave object alone
	LDA #$00
	STA Misc_State,x                             ; otherwise nullify misc object state
	LDA #$f8
	JSR DumpTwoSpr                               ; do sub to move hammer sprites offscreen
NoHOffscr:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------
; $00-$01 - used to hold tile numbers ($01 addressed in draw floatey number part)
; $02 - used to hold Y coordinate for floatey number
; $03 - residual byte used for flip (but value set here affects nothing)
; $04 - attribute byte for floatey number
; $05 - used as X coordinate for floatey number

FlagpoleScoreNumTiles:
	.db $f9, $50
	.db $f7, $50
	.db $fa, $fb
	.db $f8, $fb
	.db $f6, $fb

FlagpoleGfxHandler:
	LDY Enemy_SprDataOffset,x                    ; get sprite data offset for flagpole flag
	LDA Enemy_Rel_XPos                           ; get relative horizontal coordinate
	STA Sprite_X_Position,y                      ; store as X coordinate for first sprite
	CLC
	ADC #$08                                     ; add eight pixels and store
	STA Sprite_X_Position+4,y                    ; as X coordinate for second and third sprites
	STA Sprite_X_Position+8,y
	CLC
	ADC #$0c                                     ; add twelve more pixels and
	STA $05                                      ; store here to be used later by floatey number
	LDA Enemy_Y_Position,x                       ; get vertical coordinate
	JSR DumpTwoSpr                               ; and do sub to dump into first and second sprites
	ADC #$08                                     ; add eight pixels
	STA Sprite_Y_Position+8,y                    ; and store into third sprite
	LDA FlagpoleFNum_Y_Pos                       ; get vertical coordinate for floatey number
	STA $02                                      ; store it here
	LDA #$01
	STA $03                                      ; set value for flip which will not be used, and
	STA $04                                      ; attribute byte for floatey number
	STA Sprite_Attributes,y                      ; set attribute bytes for all three sprites
	STA Sprite_Attributes+4,y
	STA Sprite_Attributes+8,y
	LDA #$7e
	STA Sprite_Tilenumber,y                      ; put triangle shaped tile
	STA Sprite_Tilenumber+8,y                    ; into first and third sprites
	LDA #$7f
	STA Sprite_Tilenumber+4,y                    ; put skull tile into second sprite
	LDA FlagpoleCollisionYPos                    ; get vertical coordinate at time of collision
	BEQ ChkFlagOffscreen                         ; if zero, branch ahead
	TYA
	CLC                                          ; add 12 bytes to sprite data offset
	ADC #$0c
	TAY                                          ; put back in Y
	LDA FlagpoleScore                            ; get offset used to award points for touching flagpole
	ASL                                          ; multiply by 2 to get proper offset here
	TAX
	LDA FlagpoleScoreNumTiles,x                  ; get appropriate tile data
	STA $00
	LDA FlagpoleScoreNumTiles+1,x
	JSR DrawOneSpriteRow                         ; use it to render floatey number

ChkFlagOffscreen:
	LDX ObjectOffset                             ; get object offset for flag
	LDY Enemy_SprDataOffset,x                    ; get OAM data offset
	LDA Enemy_OffscreenBits                      ; get offscreen bits
	AND #%00001110                               ; mask out all but d3-d1
	BEQ ExitDumpSpr                              ; if none of these bits set, branch to leave

; -------------------------------------------------------------------------------------

MoveSixSpritesOffscreen:
	LDA #$f8                                     ; set offscreen coordinate if jumping here

DumpSixSpr:
	STA Sprite_Data+20,y                         ; dump A contents
	STA Sprite_Data+16,y                         ; into third row sprites

DumpFourSpr:
	STA Sprite_Data+12,y                         ; into second row sprites

DumpThreeSpr:
	STA Sprite_Data+8,y

DumpTwoSpr:
	STA Sprite_Data+4,y                          ; and into first row sprites
	STA Sprite_Data,y

ExitDumpSpr:
	RTS

; -------------------------------------------------------------------------------------

DrawLargePlatform:
	LDY Enemy_SprDataOffset,x                    ; get OAM data offset
	STY $02                                      ; store here
	INY                                          ; add 3 to it for offset
	INY                                          ; to X coordinate
	INY
	LDA Enemy_Rel_XPos                           ; get horizontal relative coordinate
	JSR SixSpriteStacker                         ; store X coordinates using A as base, stack horizontally
	LDX ObjectOffset
	LDA Enemy_Y_Position,x                       ; get vertical coordinate
	JSR DumpFourSpr                              ; dump into first four sprites as Y coordinate
	LDY AreaType
	CPY #$03                                     ; check for castle-type level
	BEQ ShrinkPlatform
	LDY SecondaryHardMode                        ; check for secondary hard mode flag set
	BEQ SetLast2Platform                         ; branch if not set elsewhere

ShrinkPlatform:
	LDA #$f8                                     ; load offscreen coordinate if flag set or castle-type level

SetLast2Platform:
	LDY Enemy_SprDataOffset,x                    ; get OAM data offset
	STA Sprite_Y_Position+16,y                   ; store vertical coordinate or offscreen
	STA Sprite_Y_Position+20,y                   ; coordinate into last two sprites as Y coordinate
	LDA #$5b                                     ; load default tile for platform (girder)
	LDX CloudTypeOverride
	BEQ SetPlatformTilenum                       ; if cloud level override flag not set, use
	LDA #$75                                     ; otherwise load other tile for platform (puff)

SetPlatformTilenum:
	LDX ObjectOffset                             ; get enemy object buffer offset
	INY                                          ; increment Y for tile offset
	JSR DumpSixSpr                               ; dump tile number into all six sprites
	LDA #$02                                     ; set palette controls
	INY                                          ; increment Y for sprite attributes
	JSR DumpSixSpr                               ; dump attributes into all six sprites
	INX                                          ; increment X for enemy objects
	JSR GetXOffscreenBits                        ; get offscreen bits again
	DEX
	LDY Enemy_SprDataOffset,x                    ; get OAM data offset
	ASL                                          ; rotate d7 into carry, save remaining
	PHA                                          ; bits to the stack
	BCC SChk2
	LDA #$f8                                     ; if d7 was set, move first sprite offscreen
	STA Sprite_Y_Position,y
SChk2:
	PLA                                          ; get bits from stack
	ASL                                          ; rotate d6 into carry
	PHA                                          ; save to stack
	BCC SChk3
	LDA #$f8                                     ; if d6 was set, move second sprite offscreen
	STA Sprite_Y_Position+4,y
SChk3:
	PLA                                          ; get bits from stack
	ASL                                          ; rotate d5 into carry
	PHA                                          ; save to stack
	BCC SChk4
	LDA #$f8                                     ; if d5 was set, move third sprite offscreen
	STA Sprite_Y_Position+8,y
SChk4:
	PLA                                          ; get bits from stack
	ASL                                          ; rotate d4 into carry
	PHA                                          ; save to stack
	BCC SChk5
	LDA #$f8                                     ; if d4 was set, move fourth sprite offscreen
	STA Sprite_Y_Position+12,y
SChk5:
	PLA                                          ; get bits from stack
	ASL                                          ; rotate d3 into carry
	PHA                                          ; save to stack
	BCC SChk6
	LDA #$f8                                     ; if d3 was set, move fifth sprite offscreen
	STA Sprite_Y_Position+16,y
SChk6:
	PLA                                          ; get bits from stack
	ASL                                          ; rotate d2 into carry
	BCC SLChk                                    ; save to stack
	LDA #$f8
	STA Sprite_Y_Position+20,y                   ; if d2 was set, move sixth sprite offscreen
SLChk:
	LDA Enemy_OffscreenBits                      ; check d7 of offscreen bits
	ASL                                          ; and if d7 is not set, skip sub
	BCC ExDLPl
	JSR MoveSixSpritesOffscreen                  ; otherwise branch to move all sprites offscreen
ExDLPl:
	RTS

; -------------------------------------------------------------------------------------

DrawFloateyNumber_Coin:
	LDA FrameCounter                             ; get frame counter
	LSR                                          ; divide by 2
	BCS NotRsNum                                 ; branch if d0 not set to raise number every other frame
	DEC Misc_Y_Position,x                        ; otherwise, decrement vertical coordinate
NotRsNum:
	LDA Misc_Y_Position,x                        ; get vertical coordinate
	JSR DumpTwoSpr                               ; dump into both sprites
	LDA Misc_Rel_XPos                            ; get relative horizontal coordinate
	STA Sprite_X_Position,y                      ; store as X coordinate for first sprite
	CLC
	ADC #$08                                     ; add eight pixels
	STA Sprite_X_Position+4,y                    ; store as X coordinate for second sprite
	LDA #$02
	STA Sprite_Attributes,y                      ; store attribute byte in both sprites
	STA Sprite_Attributes+4,y
	LDA #$f7
	STA Sprite_Tilenumber,y                      ; put tile numbers into both sprites
	LDA #$fb                                     ; that resemble "200"
	STA Sprite_Tilenumber+4,y
	JMP ExJCGfx                                  ; then jump to leave (why not an rts here instead?)

JumpingCoinTiles:
	.db $60, $61, $62, $63

JCoinGfxHandler:
	LDY Misc_SprDataOffset,x                     ; get coin/floatey number's OAM data offset
	LDA Misc_State,x                             ; get state of misc object
	CMP #$02                                     ; if 2 or greater,
	BCS DrawFloateyNumber_Coin                   ; branch to draw floatey number
	LDA Misc_Y_Position,x                        ; store vertical coordinate as
	STA Sprite_Y_Position,y                      ; Y coordinate for first sprite
	CLC
	ADC #$08                                     ; add eight pixels
	STA Sprite_Y_Position+4,y                    ; store as Y coordinate for second sprite
	LDA Misc_Rel_XPos                            ; get relative horizontal coordinate
	STA Sprite_X_Position,y
	STA Sprite_X_Position+4,y                    ; store as X coordinate for first and second sprites
	LDA FrameCounter                             ; get frame counter
	LSR                                          ; divide by 2 to alter every other frame
	AND #%00000011                               ; mask out d2-d1
	TAX                                          ; use as graphical offset
	LDA JumpingCoinTiles,x                       ; load tile number
	INY                                          ; increment OAM data offset to write tile numbers
	JSR DumpTwoSpr                               ; do sub to dump tile number into both sprites
	DEY                                          ; decrement to get old offset
	LDA #$02
	STA Sprite_Attributes,y                      ; set attribute byte in first sprite
	LDA #$82
	STA Sprite_Attributes+4,y                    ; set attribute byte with vertical flip in second sprite
	LDX ObjectOffset                             ; get misc object offset
ExJCGfx:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------
; $00-$01 - used to hold tiles for drawing the power-up, $00 also used to hold power-up type
; $02 - used to hold bottom row Y position
; $03 - used to hold flip control (not used here)
; $04 - used to hold sprite attributes
; $05 - used to hold X position
; $07 - counter

; tiles arranged in top left, right, bottom left, right order
PowerUpGfxTable:
	.db $76, $77, $78, $79                       ; regular mushroom
	.db $d6, $d6, $d9, $d9                       ; fire flower
	.db $8d, $8d, $e4, $e4                       ; star
	.db $76, $77, $78, $79                       ; 1-up mushroom

PowerUpAttributes:
	.db $02, $01, $02, $01

DrawPowerUp:
	LDY Enemy_SprDataOffset+5                    ; get power-up's sprite data offset
	LDA Enemy_Rel_YPos                           ; get relative vertical coordinate
	CLC
	ADC #$08                                     ; add eight pixels
	STA $02                                      ; store result here
	LDA Enemy_Rel_XPos                           ; get relative horizontal coordinate
	STA $05                                      ; store here
	LDX PowerUpType                              ; get power-up type
	LDA PowerUpAttributes,x                      ; get attribute data for power-up type
	ORA Enemy_SprAttrib+5                        ; add background priority bit if set
	STA $04                                      ; store attributes here
	TXA
	PHA                                          ; save power-up type to the stack
	ASL
	ASL                                          ; multiply by four to get proper offset
	TAX                                          ; use as X
	LDA #$01
	STA $07                                      ; set counter here to draw two rows of sprite object
	STA $03                                      ; init d1 of flip control

PUpDrawLoop:
	LDA PowerUpGfxTable,x                        ; load left tile of power-up object
	STA $00
	LDA PowerUpGfxTable+1,x                      ; load right tile
	JSR DrawOneSpriteRow                         ; branch to draw one row of our power-up object
	DEC $07                                      ; decrement counter
	BPL PUpDrawLoop                              ; branch until two rows are drawn
	LDY Enemy_SprDataOffset+5                    ; get sprite data offset again
	PLA                                          ; pull saved power-up type from the stack
	BEQ PUpOfs                                   ; if regular mushroom, branch, do not change colors or flip
	CMP #$03
	BEQ PUpOfs                                   ; if 1-up mushroom, branch, do not change colors or flip
	STA $00                                      ; store power-up type here now
	LDA FrameCounter                             ; get frame counter
	LSR                                          ; divide by 2 to change colors every two frames
	AND #%00000011                               ; mask out all but d1 and d0 (previously d2 and d1)
	ORA Enemy_SprAttrib+5                        ; add background priority bit if any set
	STA Sprite_Attributes,y                      ; set as new palette bits for top left and
	STA Sprite_Attributes+4,y                    ; top right sprites for fire flower and star
	LDX $00
	DEX                                          ; check power-up type for fire flower
	BEQ FlipPUpRightSide                         ; if found, skip this part
	STA Sprite_Attributes+8,y                    ; otherwise set new palette bits  for bottom left
	STA Sprite_Attributes+12,y                   ; and bottom right sprites as well for star only

FlipPUpRightSide:
	LDA Sprite_Attributes+4,y
	ORA #%01000000                               ; set horizontal flip bit for top right sprite
	STA Sprite_Attributes+4,y
	LDA Sprite_Attributes+12,y
	ORA #%01000000                               ; set horizontal flip bit for bottom right sprite
	STA Sprite_Attributes+12,y                   ; note these are only done for fire flower and star power-ups
PUpOfs:
	JMP SprObjectOffscrChk                       ; jump to check to see if power-up is offscreen at all, then leave

; -------------------------------------------------------------------------------------
; $00-$01 - used in DrawEnemyObjRow to hold sprite tile numbers
; $02 - used to store Y position
; $03 - used to store moving direction, used to flip enemies horizontally
; $04 - used to store enemy's sprite attributes
; $05 - used to store X position
; $eb - used to hold sprite data offset
; $ec - used to hold either altered enemy state or special value used in gfx handler as condition
; $ed - used to hold enemy state from buffer
; $ef - used to hold enemy code used in gfx handler (may or may not resemble Enemy_ID values)

; tiles arranged in top left, right, middle left, right, bottom left, right order
EnemyGraphicsTable:
	.db $fc, $fc, $aa, $ab, $ac, $ad             ; buzzy beetle frame 1
	.db $fc, $fc, $ae, $af, $b0, $b1             ;              frame 2
	.db $fc, $a5, $a6, $a7, $a8, $a9             ; koopa troopa frame 1
	.db $fc, $a0, $a1, $a2, $a3, $a4             ;              frame 2
	.db $69, $a5, $6a, $a7, $a8, $a9             ; koopa paratroopa frame 1
	.db $6b, $a0, $6c, $a2, $a3, $a4             ;                  frame 2
	.db $fc, $fc, $96, $97, $98, $99             ; spiny frame 1
	.db $fc, $fc, $9a, $9b, $9c, $9d             ;       frame 2
	.db $fc, $fc, $8f, $8e, $8e, $8f             ; spiny's egg frame 1
	.db $fc, $fc, $95, $94, $94, $95             ;             frame 2
	.db $fc, $fc, $dc, $dc, $df, $df             ; bloober frame 1
	.db $dc, $dc, $dd, $dd, $de, $de             ;         frame 2
	.db $fc, $fc, $b2, $b3, $b4, $b5             ; cheep-cheep frame 1
	.db $fc, $fc, $b6, $b3, $b7, $b5             ;             frame 2
	.db $fc, $fc, $70, $71, $72, $73             ; goomba
	.db $fc, $fc, $6e, $6e, $6f, $6f             ; koopa shell frame 1 (upside-down)
	.db $fc, $fc, $6d, $6d, $6f, $6f             ;             frame 2
	.db $fc, $fc, $6f, $6f, $6e, $6e             ; koopa shell frame 1 (rightsideup)
	.db $fc, $fc, $6f, $6f, $6d, $6d             ;             frame 2
	.db $fc, $fc, $f4, $f4, $f5, $f5             ; buzzy beetle shell frame 1 (rightsideup)
	.db $fc, $fc, $f4, $f4, $f5, $f5             ;                    frame 2
	.db $fc, $fc, $f5, $f5, $f4, $f4             ; buzzy beetle shell frame 1 (upside-down)
	.db $fc, $fc, $f5, $f5, $f4, $f4             ;                    frame 2
	.db $fc, $fc, $fc, $fc, $ef, $ef             ; defeated goomba
	.db $b9, $b8, $bb, $ba, $bc, $bc             ; lakitu frame 1
	.db $fc, $fc, $bd, $bd, $bc, $bc             ;        frame 2
	.db $7a, $7b, $da, $db, $d8, $d8             ; princess
	.db $cd, $cd, $ce, $ce, $cf, $cf             ; mushroom retainer
	.db $7d, $7c, $d1, $8c, $d3, $d2             ; hammer bro frame 1
	.db $7d, $7c, $89, $88, $8b, $8a             ;            frame 2
	.db $d5, $d4, $e3, $e2, $d3, $d2             ;            frame 3
	.db $d5, $d4, $e3, $e2, $8b, $8a             ;            frame 4
	.db $e5, $e5, $e6, $e6, $eb, $eb             ; piranha plant frame 1
	.db $ec, $ec, $ed, $ed, $ee, $ee             ;               frame 2
	.db $fc, $fc, $d0, $d0, $d7, $d7             ; podoboo
	.db $bf, $be, $c1, $c0, $c2, $fc             ; bowser front frame 1
	.db $c4, $c3, $c6, $c5, $c8, $c7             ; bowser rear frame 1
	.db $bf, $be, $ca, $c9, $c2, $fc             ;        front frame 2
	.db $c4, $c3, $c6, $c5, $cc, $cb             ;        rear frame 2
	.db $fc, $fc, $e8, $e7, $ea, $e9             ; bullet bill
	.db $f2, $f2, $f3, $f3, $f2, $f2             ; jumpspring frame 1
	.db $f1, $f1, $f1, $f1, $fc, $fc             ;            frame 2
	.db $f0, $f0, $fc, $fc, $fc, $fc             ;            frame 3

EnemyGfxTableOffsets:
	.db $0c, $0c, $00, $0c, $0c, $a8, $54, $3c
	.db $ea, $18, $48, $48, $cc, $c0, $18, $18
	.db $18, $90, $24, $ff, $48, $9c, $d2, $d8
	.db $f0, $f6, $fc

EnemyAttributeData:
	.db $01, $02, $03, $02, $01, $01, $03, $03
	.db $03, $01, $01, $02, $02, $21, $01, $02
	.db $01, $01, $02, $ff, $02, $02, $01, $01
	.db $02, $02, $02

EnemyAnimTimingBMask:
	.db $08, $18

JumpspringFrameOffsets:
	.db $18, $19, $1a, $19, $18

EnemyGfxHandler:
	LDA Enemy_Y_Position,x                       ; get enemy object vertical position
	STA $02
	LDA Enemy_Rel_XPos                           ; get enemy object horizontal position
	STA $05                                      ; relative to screen
	LDY Enemy_SprDataOffset,x
	STY $eb                                      ; get sprite data offset
	LDA #$00
	STA VerticalFlipFlag                         ; initialize vertical flip flag by default
	LDA Enemy_MovingDir,x
	STA $03                                      ; get enemy object moving direction
	LDA Enemy_SprAttrib,x
	STA $04                                      ; get enemy object sprite attributes
	LDA Enemy_ID,x
	CMP #PiranhaPlant                            ; is enemy object piranha plant?
	BNE CheckForRetainerObj                      ; if not, branch
	LDY PiranhaPlant_Y_Speed,x
	BMI CheckForRetainerObj                      ; if piranha plant moving upwards, branch
	LDY EnemyFrameTimer,x
	BEQ CheckForRetainerObj                      ; if timer for movement expired, branch
	RTS                                          ; if all conditions fail, leave

CheckForRetainerObj:
	LDA Enemy_State,x                            ; store enemy state
	STA $ed
	AND #%00011111                               ; nullify all but 5 LSB and use as Y
	TAY
	LDA Enemy_ID,x                               ; check for mushroom retainer/princess object
	CMP #RetainerObject
	BNE CheckForBulletBillCV                     ; if not found, branch
	LDY #$00                                     ; if found, nullify saved state in Y
	LDA #$01                                     ; set value that will not be used
	STA $03
	LDA #$15                                     ; set value $15 as code for mushroom retainer/princess object

CheckForBulletBillCV:
	CMP #BulletBill_CannonVar                    ; otherwise check for bullet bill object
	BNE CheckForJumpspring                       ; if not found, branch again
	DEC $02                                      ; decrement saved vertical position
	LDA #$03
	LDY EnemyFrameTimer,x                        ; get timer for enemy object
	BEQ SBBAt                                    ; if expired, do not set priority bit
	ORA #%00100000                               ; otherwise do so
SBBAt:
	STA $04                                      ; set new sprite attributes
	LDY #$00                                     ; nullify saved enemy state both in Y and in
	STY $ed                                      ; memory location here
	LDA #$08                                     ; set specific value to unconditionally branch once

CheckForJumpspring:
	CMP #JumpspringObject                        ; check for jumpspring object
	BNE CheckForPodoboo
	LDY #$03                                     ; set enemy state -2 MSB here for jumpspring object
	LDX JumpspringAnimCtrl                       ; get current frame number for jumpspring object
	LDA JumpspringFrameOffsets,x                 ; load data using frame number as offset

CheckForPodoboo:
	STA $ef                                      ; store saved enemy object value here
	STY $ec                                      ; and Y here (enemy state -2 MSB if not changed)
	LDX ObjectOffset                             ; get enemy object offset
	CMP #$0c                                     ; check for podoboo object
	BNE CheckBowserGfxFlag                       ; branch if not found
	LDA Enemy_Y_Speed,x                          ; if moving upwards, branch
	BMI CheckBowserGfxFlag
	INC VerticalFlipFlag                         ; otherwise, set flag for vertical flip

CheckBowserGfxFlag:
	LDA BowserGfxFlag                            ; if not drawing bowser at all, skip to something else
	BEQ CheckForGoomba
	LDY #$16                                     ; if set to 1, draw bowser's front
	CMP #$01
	BEQ SBwsrGfxOfs
	INY                                          ; otherwise draw bowser's rear
SBwsrGfxOfs:
	STY $ef

CheckForGoomba:
	LDY $ef                                      ; check value for goomba object
	CPY #Goomba
	BNE CheckBowserFront                         ; branch if not found
	LDA Enemy_State,x
	CMP #$02                                     ; check for defeated state
	BCC GmbaAnim                                 ; if not defeated, go ahead and animate
	LDX #$04                                     ; if defeated, write new value here
	STX $ec
GmbaAnim:
	AND #%00100000                               ; check for d5 set in enemy object state
	ORA TimerControl                             ; or timer disable flag set
	BNE CheckBowserFront                         ; if either condition true, do not animate goomba
	LDA FrameCounter
	AND #%00001000                               ; check for every eighth frame
	BNE CheckBowserFront
	LDA $03
	EOR #%00000011                               ; invert bits to flip horizontally every eight frames
	STA $03                                      ; leave alone otherwise

CheckBowserFront:
	LDA EnemyAttributeData,y                     ; load sprite attribute using enemy object
	ORA $04                                      ; as offset, and add to bits already loaded
	STA $04
	LDA EnemyGfxTableOffsets,y                   ; load value based on enemy object as offset
	TAX                                          ; save as X
	LDY $ec                                      ; get previously saved value
	LDA BowserGfxFlag
	BEQ CheckForSpiny                            ; if not drawing bowser object at all, skip all of this
	CMP #$01
	BNE CheckBowserRear                          ; if not drawing front part, branch to draw the rear part
	LDA BowserBodyControls                       ; check bowser's body control bits
	BPL ChkFrontSte                              ; branch if d7 not set (control's bowser's mouth)
	LDX #$de                                     ; otherwise load offset for second frame
ChkFrontSte:
	LDA $ed                                      ; check saved enemy state
	AND #%00100000                               ; if bowser not defeated, do not set flag
	BEQ DrawBowser

FlipBowserOver:
	STX VerticalFlipFlag                         ; set vertical flip flag to nonzero

DrawBowser:
	JMP DrawEnemyObject                          ; draw bowser's graphics now

CheckBowserRear:
	LDA BowserBodyControls                       ; check bowser's body control bits
	AND #$01
	BEQ ChkRearSte                               ; branch if d0 not set (control's bowser's feet)
	LDX #$e4                                     ; otherwise load offset for second frame
ChkRearSte:
	LDA $ed                                      ; check saved enemy state
	AND #%00100000                               ; if bowser not defeated, do not set flag
	BEQ DrawBowser
	LDA $02                                      ; subtract 16 pixels from
	SEC                                          ; saved vertical coordinate
	SBC #$10
	STA $02
	JMP FlipBowserOver                           ; jump to set vertical flip flag

CheckForSpiny:
	CPX #$24                                     ; check if value loaded is for spiny
	BNE CheckForLakitu                           ; if not found, branch
	CPY #$05                                     ; if enemy state set to $05, do this,
	BNE NotEgg                                   ; otherwise branch
	LDX #$30                                     ; set to spiny egg offset
	LDA #$02
	STA $03                                      ; set enemy direction to reverse sprites horizontally
	LDA #$05
	STA $ec                                      ; set enemy state
NotEgg:
	JMP CheckForHammerBro                        ; skip a big chunk of this if we found spiny but not in egg

CheckForLakitu:
	CPX #$90                                     ; check value for lakitu's offset loaded
	BNE CheckUpsideDownShell                     ; branch if not loaded
	LDA $ed
	AND #%00100000                               ; check for d5 set in enemy state
	BNE NoLAFr                                   ; branch if set
	LDA FrenzyEnemyTimer
	CMP #$10                                     ; check timer to see if we've reached a certain range
	BCS NoLAFr                                   ; branch if not
	LDX #$96                                     ; if d6 not set and timer in range, load alt frame for lakitu
NoLAFr:
	JMP CheckDefeatedState                       ; skip this next part if we found lakitu but alt frame not needed

CheckUpsideDownShell:
	LDA $ef                                      ; check for enemy object => $04
	CMP #$04
	BCS CheckRightSideUpShell                    ; branch if true
	CPY #$02
	BCC CheckRightSideUpShell                    ; branch if enemy state < $02
	LDX #$5a                                     ; set for upside-down koopa shell by default
	LDY $ef
	CPY #BuzzyBeetle                             ; check for buzzy beetle object
	BNE CheckRightSideUpShell
	LDX #$7e                                     ; set for upside-down buzzy beetle shell if found
	INC $02                                      ; increment vertical position by one pixel

CheckRightSideUpShell:
	LDA $ec                                      ; check for value set here
	CMP #$04                                     ; if enemy state < $02, do not change to shell, if
	BNE CheckForHammerBro                        ; enemy state => $02 but not = $04, leave shell upside-down
	LDX #$72                                     ; set right-side up buzzy beetle shell by default
	INC $02                                      ; increment saved vertical position by one pixel
	LDY $ef
	CPY #BuzzyBeetle                             ; check for buzzy beetle object
	BEQ CheckForDefdGoomba                       ; branch if found
	LDX #$66                                     ; change to right-side up koopa shell if not found
	INC $02                                      ; and increment saved vertical position again

CheckForDefdGoomba:
	CPY #Goomba                                  ; check for goomba object (necessary if previously
	BNE CheckForHammerBro                        ; failed buzzy beetle object test)
	LDX #$54                                     ; load for regular goomba
	LDA $ed                                      ; note that this only gets performed if enemy state => $02
	AND #%00100000                               ; check saved enemy state for d5 set
	BNE CheckForHammerBro                        ; branch if set
	LDX #$8a                                     ; load offset for defeated goomba
	DEC $02                                      ; set different value and decrement saved vertical position

CheckForHammerBro:
	LDY ObjectOffset
	LDA $ef                                      ; check for hammer bro object
	CMP #HammerBro
	BNE CheckForBloober                          ; branch if not found
	LDA $ed
	BEQ CheckToAnimateEnemy                      ; branch if not in normal enemy state
	AND #%00001000
	BEQ CheckDefeatedState                       ; if d3 not set, branch further away
	LDX #$b4                                     ; otherwise load offset for different frame
	BNE CheckToAnimateEnemy                      ; unconditional branch

CheckForBloober:
	CPX #$48                                     ; check for cheep-cheep offset loaded
	BEQ CheckToAnimateEnemy                      ; branch if found
	LDA EnemyIntervalTimer,y
	CMP #$05
	BCS CheckDefeatedState                       ; branch if some timer is above a certain point
	CPX #$3c                                     ; check for bloober offset loaded
	BNE CheckToAnimateEnemy                      ; branch if not found this time
	CMP #$01
	BEQ CheckDefeatedState                       ; branch if timer is set to certain point
	INC $02                                      ; increment saved vertical coordinate three pixels
	INC $02
	INC $02
	JMP CheckAnimationStop                       ; and do something else

CheckToAnimateEnemy:
	LDA $ef                                      ; check for specific enemy objects
	CMP #Goomba
	BEQ CheckDefeatedState                       ; branch if goomba
	CMP #$08
	BEQ CheckDefeatedState                       ; branch if bullet bill (note both variants use $08 here)
	CMP #Podoboo
	BEQ CheckDefeatedState                       ; branch if podoboo
	CMP #$18                                     ; branch if => $18
	BCS CheckDefeatedState
	LDY #$00
	CMP #$15                                     ; check for mushroom retainer/princess object
	BNE CheckForSecondFrame                      ; which uses different code here, branch if not found
	INY                                          ; residual instruction
	LDA WorldNumber                              ; are we on world 8?
	CMP #World8
	BCS CheckDefeatedState                       ; if so, leave the offset alone (use princess)
	LDX #$a2                                     ; otherwise, set for mushroom retainer object instead
	LDA #$03                                     ; set alternate state here
	STA $ec
	BNE CheckDefeatedState                       ; unconditional branch

CheckForSecondFrame:
	LDA FrameCounter                             ; load frame counter
	AND EnemyAnimTimingBMask,y                   ; mask it (partly residual, one byte not ever used)
	BNE CheckDefeatedState                       ; branch if timing is off

CheckAnimationStop:
	LDA $ed                                      ; check saved enemy state
	AND #%10100000                               ; for d7 or d5, or check for timers stopped
	ORA TimerControl
	BNE CheckDefeatedState                       ; if either condition true, branch
	TXA
	CLC
	ADC #$06                                     ; add $06 to current enemy offset
	TAX                                          ; to animate various enemy objects

CheckDefeatedState:
	LDA $ed                                      ; check saved enemy state
	AND #%00100000                               ; for d5 set
	BEQ DrawEnemyObject                          ; branch if not set
	LDA $ef
	CMP #$04                                     ; check for saved enemy object => $04
	BCC DrawEnemyObject                          ; branch if less
	LDY #$01
	STY VerticalFlipFlag                         ; set vertical flip flag
	DEY
	STY $ec                                      ; init saved value here

DrawEnemyObject:
	LDY $eb                                      ; load sprite data offset
	JSR DrawEnemyObjRow                          ; draw six tiles of data
	JSR DrawEnemyObjRow                          ; into sprite data
	JSR DrawEnemyObjRow
	LDX ObjectOffset                             ; get enemy object offset
	LDY Enemy_SprDataOffset,x                    ; get sprite data offset
	LDA $ef
	CMP #$08                                     ; get saved enemy object and check
	BNE CheckForVerticalFlip                     ; for bullet bill, branch if not found

SkipToOffScrChk:
	JMP SprObjectOffscrChk                       ; jump if found

CheckForVerticalFlip:
	LDA VerticalFlipFlag                         ; check if vertical flip flag is set here
	BEQ CheckForESymmetry                        ; branch if not
	LDA Sprite_Attributes,y                      ; get attributes of first sprite we dealt with
	ORA #%10000000                               ; set bit for vertical flip
	INY
	INY                                          ; increment two bytes so that we store the vertical flip
	JSR DumpSixSpr                               ; in attribute bytes of enemy obj sprite data
	DEY
	DEY                                          ; now go back to the Y coordinate offset
	TYA
	TAX                                          ; give offset to X
	LDA $ef
	CMP #HammerBro                               ; check saved enemy object for hammer bro
	BEQ FlipEnemyVertically
	CMP #Lakitu                                  ; check saved enemy object for lakitu
	BEQ FlipEnemyVertically                      ; branch for hammer bro or lakitu
	CMP #$15
	BCS FlipEnemyVertically                      ; also branch if enemy object => $15
	TXA
	CLC
	ADC #$08                                     ; if not selected objects or => $15, set
	TAX                                          ; offset in X for next row

FlipEnemyVertically:
	LDA Sprite_Tilenumber,x                      ; load first or second row tiles
	PHA                                          ; and save tiles to the stack
	LDA Sprite_Tilenumber+4,x
	PHA
	LDA Sprite_Tilenumber+16,y                   ; exchange third row tiles
	STA Sprite_Tilenumber,x                      ; with first or second row tiles
	LDA Sprite_Tilenumber+20,y
	STA Sprite_Tilenumber+4,x
	PLA                                          ; pull first or second row tiles from stack
	STA Sprite_Tilenumber+20,y                   ; and save in third row
	PLA
	STA Sprite_Tilenumber+16,y

CheckForESymmetry:
	LDA BowserGfxFlag                            ; are we drawing bowser at all?
	BNE SkipToOffScrChk                          ; branch if so
	LDA $ef
	LDX $ec                                      ; get alternate enemy state
	CMP #$05                                     ; check for hammer bro object
	BNE ContES
	JMP SprObjectOffscrChk                       ; jump if found
ContES:
	CMP #Bloober                                 ; check for bloober object
	BEQ MirrorEnemyGfx
	CMP #PiranhaPlant                            ; check for piranha plant object
	BEQ MirrorEnemyGfx
	CMP #Podoboo                                 ; check for podoboo object
	BEQ MirrorEnemyGfx                           ; branch if either of three are found
	CMP #Spiny                                   ; check for spiny object
	BNE ESRtnr                                   ; branch closer if not found
	CPX #$05                                     ; check spiny's state
	BNE CheckToMirrorLakitu                      ; branch if not an egg, otherwise
ESRtnr:
	CMP #$15                                     ; check for princess/mushroom retainer object
	BNE SpnySC
	LDA #$42                                     ; set horizontal flip on bottom right sprite
	STA Sprite_Attributes+20,y                   ; note that palette bits were already set earlier
SpnySC:
	CPX #$02                                     ; if alternate enemy state set to 1 or 0, branch
	BCC CheckToMirrorLakitu

MirrorEnemyGfx:
	LDA BowserGfxFlag                            ; if enemy object is bowser, skip all of this
	BNE CheckToMirrorLakitu
	LDA Sprite_Attributes,y                      ; load attribute bits of first sprite
	AND #%10100011
	STA Sprite_Attributes,y                      ; save vertical flip, priority, and palette bits
	STA Sprite_Attributes+8,y                    ; in left sprite column of enemy object OAM data
	STA Sprite_Attributes+16,y
	ORA #%01000000                               ; set horizontal flip
	CPX #$05                                     ; check for state used by spiny's egg
	BNE EggExc                                   ; if alternate state not set to $05, branch
	ORA #%10000000                               ; otherwise set vertical flip
EggExc:
	STA Sprite_Attributes+4,y                    ; set bits of right sprite column
	STA Sprite_Attributes+12,y                   ; of enemy object sprite data
	STA Sprite_Attributes+20,y
	CPX #$04                                     ; check alternate enemy state
	BNE CheckToMirrorLakitu                      ; branch if not $04
	LDA Sprite_Attributes+8,y                    ; get second row left sprite attributes
	ORA #%10000000
	STA Sprite_Attributes+8,y                    ; store bits with vertical flip in
	STA Sprite_Attributes+16,y                   ; second and third row left sprites
	ORA #%01000000
	STA Sprite_Attributes+12,y                   ; store with horizontal and vertical flip in
	STA Sprite_Attributes+20,y                   ; second and third row right sprites

CheckToMirrorLakitu:
	LDA $ef                                      ; check for lakitu enemy object
	CMP #Lakitu
	BNE CheckToMirrorJSpring                     ; branch if not found
	LDA VerticalFlipFlag
	BNE NVFLak                                   ; branch if vertical flip flag not set
	LDA Sprite_Attributes+16,y                   ; save vertical flip and palette bits
	AND #%10000001                               ; in third row left sprite
	STA Sprite_Attributes+16,y
	LDA Sprite_Attributes+20,y                   ; set horizontal flip and palette bits
	ORA #%01000001                               ; in third row right sprite
	STA Sprite_Attributes+20,y
	LDX FrenzyEnemyTimer                         ; check timer
	CPX #$10
	BCS SprObjectOffscrChk                       ; branch if timer has not reached a certain range
	STA Sprite_Attributes+12,y                   ; otherwise set same for second row right sprite
	AND #%10000001
	STA Sprite_Attributes+8,y                    ; preserve vertical flip and palette bits for left sprite
	BCC SprObjectOffscrChk                       ; unconditional branch
NVFLak:
	LDA Sprite_Attributes,y                      ; get first row left sprite attributes
	AND #%10000001
	STA Sprite_Attributes,y                      ; save vertical flip and palette bits
	LDA Sprite_Attributes+4,y                    ; get first row right sprite attributes
	ORA #%01000001                               ; set horizontal flip and palette bits
	STA Sprite_Attributes+4,y                    ; note that vertical flip is left as-is

CheckToMirrorJSpring:
	LDA $ef                                      ; check for jumpspring object (any frame)
	CMP #$18
	BCC SprObjectOffscrChk                       ; branch if not jumpspring object at all
	LDA #$82
	STA Sprite_Attributes+8,y                    ; set vertical flip and palette bits of
	STA Sprite_Attributes+16,y                   ; second and third row left sprites
	ORA #%01000000
	STA Sprite_Attributes+12,y                   ; set, in addition to those, horizontal flip
	STA Sprite_Attributes+20,y                   ; for second and third row right sprites

SprObjectOffscrChk:
	LDX ObjectOffset                             ; get enemy buffer offset
	LDA Enemy_OffscreenBits                      ; check offscreen information
	LSR
	LSR                                          ; shift three times to the right
	LSR                                          ; which puts d2 into carry
	PHA                                          ; save to stack
	BCC LcChk                                    ; branch if not set
	LDA #$04                                     ; set for right column sprites
	JSR MoveESprColOffscreen                     ; and move them offscreen
LcChk:
	PLA                                          ; get from stack
	LSR                                          ; move d3 to carry
	PHA                                          ; save to stack
	BCC Row3C                                    ; branch if not set
	LDA #$00                                     ; set for left column sprites,
	JSR MoveESprColOffscreen                     ; move them offscreen
Row3C:
	PLA                                          ; get from stack again
	LSR                                          ; move d5 to carry this time
	LSR
	PHA                                          ; save to stack again
	BCC Row23C                                   ; branch if carry not set
	LDA #$10                                     ; set for third row of sprites
	JSR MoveESprRowOffscreen                     ; and move them offscreen
Row23C:
	PLA                                          ; get from stack
	LSR                                          ; move d6 into carry
	PHA                                          ; save to stack
	BCC AllRowC
	LDA #$08                                     ; set for second and third rows
	JSR MoveESprRowOffscreen                     ; move them offscreen
AllRowC:
	PLA                                          ; get from stack once more
	LSR                                          ; move d7 into carry
	BCC ExEGHandler
	JSR MoveESprRowOffscreen                     ; move all sprites offscreen (A should be 0 by now)
	LDA Enemy_ID,x
	CMP #Podoboo                                 ; check enemy identifier for podoboo
	BEQ ExEGHandler                              ; skip this part if found, we do not want to erase podoboo!
	LDA Enemy_Y_HighPos,x                        ; check high byte of vertical position
	CMP #$02                                     ; if not yet past the bottom of the screen, branch
	BNE ExEGHandler
	JSR EraseEnemyObject                         ; what it says

ExEGHandler:
	RTS

DrawEnemyObjRow:
	LDA EnemyGraphicsTable,x                     ; load two tiles of enemy graphics
	STA $00
	LDA EnemyGraphicsTable+1,x

DrawOneSpriteRow:
	STA $01
	JMP DrawSpriteObject                         ; draw them

MoveESprRowOffscreen:
	CLC                                          ; add A to enemy object OAM data offset
	ADC Enemy_SprDataOffset,x
	TAY                                          ; use as offset
	LDA #$f8
	JMP DumpTwoSpr                               ; move first row of sprites offscreen

MoveESprColOffscreen:
	CLC                                          ; add A to enemy object OAM data offset
	ADC Enemy_SprDataOffset,x
	TAY                                          ; use as offset
	JSR MoveColOffscreen                         ; move first and second row sprites in column offscreen
	STA Sprite_Data+16,y                         ; move third row sprite in column offscreen
	RTS

; -------------------------------------------------------------------------------------
; $00-$01 - tile numbers
; $02 - relative Y position
; $03 - horizontal flip flag (not used here)
; $04 - attributes
; $05 - relative X position

DefaultBlockObjTiles:
	.db $85, $85, $86, $86                       ; brick w/ line (these are sprite tiles, not BG!)

DrawBlock:
	LDA Block_Rel_YPos                           ; get relative vertical coordinate of block object
	STA $02                                      ; store here
	LDA Block_Rel_XPos                           ; get relative horizontal coordinate of block object
	STA $05                                      ; store here
	LDA #$03
	STA $04                                      ; set attribute byte here
	LSR
	STA $03                                      ; set horizontal flip bit here (will not be used)
	LDY Block_SprDataOffset,x                    ; get sprite data offset
	LDX #$00                                     ; reset X for use as offset to tile data
DBlkLoop:
	LDA DefaultBlockObjTiles,x                   ; get left tile number
	STA $00                                      ; set here
	LDA DefaultBlockObjTiles+1,x                 ; get right tile number
	JSR DrawOneSpriteRow                         ; do sub to write tile numbers to first row of sprites
	CPX #$04                                     ; check incremented offset
	BNE DBlkLoop                                 ; and loop back until all four sprites are done
	LDX ObjectOffset                             ; get block object offset
	LDY Block_SprDataOffset,x                    ; get sprite data offset
	LDA AreaType
	CMP #$01                                     ; check for ground level type area
	BEQ ChkRep                                   ; if found, branch to next part
	LDA #$86
	STA Sprite_Tilenumber,y                      ; otherwise remove brick tiles with lines
	STA Sprite_Tilenumber+4,y                    ; and replace then with lineless brick tiles
ChkRep:
	LDA Block_Metatile,x                         ; check replacement metatile
	CMP #$c4                                     ; if not used block metatile, then
	BNE BlkOffscr                                ; branch ahead to use current graphics
	LDA #$87                                     ; set A for used block tile
	INY                                          ; increment Y to write to tile bytes
	JSR DumpFourSpr                              ; do sub to dump into all four sprites
	DEY                                          ; return Y to original offset
	LDA #$03                                     ; set palette bits
	LDX AreaType
	DEX                                          ; check for ground level type area again
	BEQ SetBFlip                                 ; if found, use current palette bits
	LSR                                          ; otherwise set to $01
SetBFlip:
	LDX ObjectOffset                             ; put block object offset back in X
	STA Sprite_Attributes,y                      ; store attribute byte as-is in first sprite
	ORA #%01000000
	STA Sprite_Attributes+4,y                    ; set horizontal flip bit for second sprite
	ORA #%10000000
	STA Sprite_Attributes+12,y                   ; set both flip bits for fourth sprite
	AND #%10000011
	STA Sprite_Attributes+8,y                    ; set vertical flip bit for third sprite
BlkOffscr:
	LDA Block_OffscreenBits                      ; get offscreen bits for block object
	PHA                                          ; save to stack
	AND #%00000100                               ; check to see if d2 in offscreen bits are set
	BEQ PullOfsB                                 ; if not set, branch, otherwise move sprites offscreen
	LDA #$f8                                     ; move offscreen two OAMs
	STA Sprite_Y_Position+4,y                    ; on the right side
	STA Sprite_Y_Position+12,y
PullOfsB:
	PLA                                          ; pull offscreen bits from stack
ChkLeftCo:
	AND #%00001000                               ; check to see if d3 in offscreen bits are set
	BEQ ExDBlk                                   ; if not set, branch, otherwise move sprites offscreen

MoveColOffscreen:
	LDA #$f8                                     ; move offscreen two OAMs
	STA Sprite_Y_Position,y                      ; on the left side (or two rows of enemy on either side
	STA Sprite_Y_Position+8,y                    ; if branched here from enemy graphics handler)
ExDBlk:
	RTS

; -------------------------------------------------------------------------------------
; $00 - used to hold palette bits for attribute byte or relative X position

DrawBrickChunks:
	LDA #$02                                     ; set palette bits here
	STA $00
	LDA #$75                                     ; set tile number for ball (something residual, likely)
	LDY GameEngineSubroutine
	CPY #$05                                     ; if end-of-level routine running,
	BEQ DChunks                                  ; use palette and tile number assigned
	LDA #$03                                     ; otherwise set different palette bits
	STA $00
	LDA #$84                                     ; and set tile number for brick chunks
DChunks:
	LDY Block_SprDataOffset,x                    ; get OAM data offset
	INY                                          ; increment to start with tile bytes in OAM
	JSR DumpFourSpr                              ; do sub to dump tile number into all four sprites
	LDA FrameCounter                             ; get frame counter
	ASL
	ASL
	ASL                                          ; move low nybble to high
	ASL
	AND #$c0                                     ; get what was originally d3-d2 of low nybble
	ORA $00                                      ; add palette bits
	INY                                          ; increment offset for attribute bytes
	JSR DumpFourSpr                              ; do sub to dump attribute data into all four sprites
	DEY
	DEY                                          ; decrement offset to Y coordinate
	LDA Block_Rel_YPos                           ; get first block object's relative vertical coordinate
	JSR DumpTwoSpr                               ; do sub to dump current Y coordinate into two sprites
	LDA Block_Rel_XPos                           ; get first block object's relative horizontal coordinate
	STA Sprite_X_Position,y                      ; save into X coordinate of first sprite
	LDA Block_Orig_XPos,x                        ; get original horizontal coordinate
	SEC
	SBC ScreenLeft_X_Pos                         ; subtract coordinate of left side from original coordinate
	STA $00                                      ; store result as relative horizontal coordinate of original
	SEC
	SBC Block_Rel_XPos                           ; get difference of relative positions of original - current
	ADC $00                                      ; add original relative position to result
	ADC #$06                                     ; plus 6 pixels to position second brick chunk correctly
	STA Sprite_X_Position+4,y                    ; save into X coordinate of second sprite
	LDA Block_Rel_YPos+1                         ; get second block object's relative vertical coordinate
	STA Sprite_Y_Position+8,y
	STA Sprite_Y_Position+12,y                   ; dump into Y coordinates of third and fourth sprites
	LDA Block_Rel_XPos+1                         ; get second block object's relative horizontal coordinate
	STA Sprite_X_Position+8,y                    ; save into X coordinate of third sprite
	LDA $00                                      ; use original relative horizontal position
	SEC
	SBC Block_Rel_XPos+1                         ; get difference of relative positions of original - current
	ADC $00                                      ; add original relative position to result
	ADC #$06                                     ; plus 6 pixels to position fourth brick chunk correctly
	STA Sprite_X_Position+12,y                   ; save into X coordinate of fourth sprite
	LDA Block_OffscreenBits                      ; get offscreen bits for block object
	JSR ChkLeftCo                                ; do sub to move left half of sprites offscreen if necessary
	LDA Block_OffscreenBits                      ; get offscreen bits again
	ASL                                          ; shift d7 into carry
	BCC ChnkOfs                                  ; if d7 not set, branch to last part
	LDA #$f8
	JSR DumpTwoSpr                               ; otherwise move top sprites offscreen
ChnkOfs:
	LDA $00                                      ; if relative position on left side of screen,
	BPL ExBCDr                                   ; go ahead and leave
	LDA Sprite_X_Position,y                      ; otherwise compare left-side X coordinate
	CMP Sprite_X_Position+4,y                    ; to right-side X coordinate
	BCC ExBCDr                                   ; branch to leave if less
	LDA #$f8                                     ; otherwise move right half of sprites offscreen
	STA Sprite_Y_Position+4,y
	STA Sprite_Y_Position+12,y
ExBCDr:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------

DrawFireball:
	LDY FBall_SprDataOffset,x                    ; get fireball's sprite data offset
	LDA Fireball_Rel_YPos                        ; get relative vertical coordinate
	STA Sprite_Y_Position,y                      ; store as sprite Y coordinate
	LDA Fireball_Rel_XPos                        ; get relative horizontal coordinate
	STA Sprite_X_Position,y                      ; store as sprite X coordinate, then do shared code

DrawFirebar:
	LDA FrameCounter                             ; get frame counter
	LSR                                          ; divide by four
	LSR
	PHA                                          ; save result to stack
	AND #$01                                     ; mask out all but last bit
	EOR #$64                                     ; set either tile $64 or $65 as fireball tile
	STA Sprite_Tilenumber,y                      ; thus tile changes every four frames
	PLA                                          ; get from stack
	LSR                                          ; divide by four again
	LSR
	LDA #$02                                     ; load value $02 to set palette in attrib byte
	BCC FireA                                    ; if last bit shifted out was not set, skip this
	ORA #%11000000                               ; otherwise flip both ways every eight frames
FireA:
	STA Sprite_Attributes,y                      ; store attribute byte and leave
	RTS

; -------------------------------------------------------------------------------------

ExplosionTiles:
	.db $68, $67, $66

DrawExplosion_Fireball:
	LDY Alt_SprDataOffset,x                      ; get OAM data offset of alternate sort for fireball's explosion
	LDA Fireball_State,x                         ; load fireball state
	INC Fireball_State,x                         ; increment state for next frame
	LSR                                          ; divide by 2
	AND #%00000111                               ; mask out all but d3-d1
	CMP #$03                                     ; check to see if time to kill fireball
	BCS KillFireBall                             ; branch if so, otherwise continue to draw explosion

DrawExplosion_Fireworks:
	TAX                                          ; use whatever's in A for offset
	LDA ExplosionTiles,x                         ; get tile number using offset
	INY                                          ; increment Y (contains sprite data offset)
	JSR DumpFourSpr                              ; and dump into tile number part of sprite data
	DEY                                          ; decrement Y so we have the proper offset again
	LDX ObjectOffset                             ; return enemy object buffer offset to X
	LDA Fireball_Rel_YPos                        ; get relative vertical coordinate
	SEC                                          ; subtract four pixels vertically
	SBC #$04                                     ; for first and third sprites
	STA Sprite_Y_Position,y
	STA Sprite_Y_Position+8,y
	CLC                                          ; add eight pixels vertically
	ADC #$08                                     ; for second and fourth sprites
	STA Sprite_Y_Position+4,y
	STA Sprite_Y_Position+12,y
	LDA Fireball_Rel_XPos                        ; get relative horizontal coordinate
	SEC                                          ; subtract four pixels horizontally
	SBC #$04                                     ; for first and second sprites
	STA Sprite_X_Position,y
	STA Sprite_X_Position+4,y
	CLC                                          ; add eight pixels horizontally
	ADC #$08                                     ; for third and fourth sprites
	STA Sprite_X_Position+8,y
	STA Sprite_X_Position+12,y
	LDA #$02                                     ; set palette attributes for all sprites, but
	STA Sprite_Attributes,y                      ; set no flip at all for first sprite
	LDA #$82
	STA Sprite_Attributes+4,y                    ; set vertical flip for second sprite
	LDA #$42
	STA Sprite_Attributes+8,y                    ; set horizontal flip for third sprite
	LDA #$c2
	STA Sprite_Attributes+12,y                   ; set both flips for fourth sprite
	RTS                                          ; we are done

KillFireBall:
	LDA #$00                                     ; clear fireball state to kill it
	STA Fireball_State,x
	RTS

; -------------------------------------------------------------------------------------

DrawSmallPlatform:
	LDY Enemy_SprDataOffset,x                    ; get OAM data offset
	LDA #$5b                                     ; load tile number for small platforms
	INY                                          ; increment offset for tile numbers
	JSR DumpSixSpr                               ; dump tile number into all six sprites
	INY                                          ; increment offset for attributes
	LDA #$02                                     ; load palette controls
	JSR DumpSixSpr                               ; dump attributes into all six sprites
	DEY                                          ; decrement for original offset
	DEY
	LDA Enemy_Rel_XPos                           ; get relative horizontal coordinate
	STA Sprite_X_Position,y
	STA Sprite_X_Position+12,y                   ; dump as X coordinate into first and fourth sprites
	CLC
	ADC #$08                                     ; add eight pixels
	STA Sprite_X_Position+4,y                    ; dump into second and fifth sprites
	STA Sprite_X_Position+16,y
	CLC
	ADC #$08                                     ; add eight more pixels
	STA Sprite_X_Position+8,y                    ; dump into third and sixth sprites
	STA Sprite_X_Position+20,y
	LDA Enemy_Y_Position,x                       ; get vertical coordinate
	TAX
	PHA                                          ; save to stack
	CPX #$20                                     ; if vertical coordinate below status bar,
	BCS TopSP                                    ; do not mess with it
	LDA #$f8                                     ; otherwise move first three sprites offscreen
TopSP:
	JSR DumpThreeSpr                             ; dump vertical coordinate into Y coordinates
	PLA                                          ; pull from stack
	CLC
	ADC #$80                                     ; add 128 pixels
	TAX
	CPX #$20                                     ; if below status bar (taking wrap into account)
	BCS BotSP                                    ; then do not change altered coordinate
	LDA #$f8                                     ; otherwise move last three sprites offscreen
BotSP:
	STA Sprite_Y_Position+12,y                   ; dump vertical coordinate + 128 pixels
	STA Sprite_Y_Position+16,y                   ; into Y coordinates
	STA Sprite_Y_Position+20,y
	LDA Enemy_OffscreenBits                      ; get offscreen bits
	PHA                                          ; save to stack
	AND #%00001000                               ; check d3
	BEQ SOfs
	LDA #$f8                                     ; if d3 was set, move first and
	STA Sprite_Y_Position,y                      ; fourth sprites offscreen
	STA Sprite_Y_Position+12,y
SOfs:
	PLA                                          ; move out and back into stack
	PHA
	AND #%00000100                               ; check d2
	BEQ SOfs2
	LDA #$f8                                     ; if d2 was set, move second and
	STA Sprite_Y_Position+4,y                    ; fifth sprites offscreen
	STA Sprite_Y_Position+16,y
SOfs2:
	PLA                                          ; get from stack
	AND #%00000010                               ; check d1
	BEQ ExSPl
	LDA #$f8                                     ; if d1 was set, move third and
	STA Sprite_Y_Position+8,y                    ; sixth sprites offscreen
	STA Sprite_Y_Position+20,y
ExSPl:
	LDX ObjectOffset                             ; get enemy object offset and leave
	RTS

; -------------------------------------------------------------------------------------

DrawBubble:
	LDY Player_Y_HighPos                         ; if player's vertical high position
	DEY                                          ; not within screen, skip all of this
	BNE ExDBub
	LDA Bubble_OffscreenBits                     ; check air bubble's offscreen bits
	AND #%00001000
	BNE ExDBub                                   ; if bit set, branch to leave
	LDY Bubble_SprDataOffset,x                   ; get air bubble's OAM data offset
	LDA Bubble_Rel_XPos                          ; get relative horizontal coordinate
	STA Sprite_X_Position,y                      ; store as X coordinate here
	LDA Bubble_Rel_YPos                          ; get relative vertical coordinate
	STA Sprite_Y_Position,y                      ; store as Y coordinate here
	LDA #$74
	STA Sprite_Tilenumber,y                      ; put air bubble tile into OAM data
	LDA #$02
	STA Sprite_Attributes,y                      ; set attribute byte
ExDBub:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------
; $00 - used to store player's vertical offscreen bits

PlayerGfxTblOffsets:
	.db $20, $28, $c8, $18, $00, $40, $50, $58
	.db $80, $88, $b8, $78, $60, $a0, $b0, $b8

; tiles arranged in order, 2 tiles per row, top to bottom

PlayerGraphicsTable:
; big player table
	.db $00, $01, $02, $03, $04, $05, $06, $07   ; walking frame 1
	.db $08, $09, $0a, $0b, $0c, $0d, $0e, $0f   ;         frame 2
	.db $10, $11, $12, $13, $14, $15, $16, $17   ;         frame 3
	.db $18, $19, $1a, $1b, $1c, $1d, $1e, $1f   ; skidding
	.db $20, $21, $22, $23, $24, $25, $26, $27   ; jumping
	.db $08, $09, $28, $29, $2a, $2b, $2c, $2d   ; swimming frame 1
	.db $08, $09, $0a, $0b, $0c, $30, $2c, $2d   ;          frame 2
	.db $08, $09, $0a, $0b, $2e, $2f, $2c, $2d   ;          frame 3
	.db $08, $09, $28, $29, $2a, $2b, $5c, $5d   ; climbing frame 1
	.db $08, $09, $0a, $0b, $0c, $0d, $5e, $5f   ;          frame 2
	.db $fc, $fc, $08, $09, $58, $59, $5a, $5a   ; crouching
	.db $08, $09, $28, $29, $2a, $2b, $0e, $0f   ; fireball throwing

; small player table
	.db $fc, $fc, $fc, $fc, $32, $33, $34, $35   ; walking frame 1
	.db $fc, $fc, $fc, $fc, $36, $37, $38, $39   ;         frame 2
	.db $fc, $fc, $fc, $fc, $3a, $37, $3b, $3c   ;         frame 3
	.db $fc, $fc, $fc, $fc, $3d, $3e, $3f, $40   ; skidding
	.db $fc, $fc, $fc, $fc, $32, $41, $42, $43   ; jumping
	.db $fc, $fc, $fc, $fc, $32, $33, $44, $45   ; swimming frame 1
	.db $fc, $fc, $fc, $fc, $32, $33, $44, $47   ;          frame 2
	.db $fc, $fc, $fc, $fc, $32, $33, $48, $49   ;          frame 3
	.db $fc, $fc, $fc, $fc, $32, $33, $90, $91   ; climbing frame 1
	.db $fc, $fc, $fc, $fc, $3a, $37, $92, $93   ;          frame 2
	.db $fc, $fc, $fc, $fc, $9e, $9e, $9f, $9f   ; killed

; used by both player sizes
	.db $fc, $fc, $fc, $fc, $3a, $37, $4f, $4f   ; small player standing
	.db $fc, $fc, $00, $01, $4c, $4d, $4e, $4e   ; intermediate grow frame
	.db $00, $01, $4c, $4d, $4a, $4a, $4b, $4b   ; big player standing

SwimKickTileNum:
	.db $31, $46

PlayerGfxHandler:
	LDA InjuryTimer                              ; if player's injured invincibility timer
	BEQ CntPl                                    ; not set, skip checkpoint and continue code
	LDA FrameCounter
	LSR                                          ; otherwise check frame counter and branch
	BCS ExPGH                                    ; to leave on every other frame (when d0 is set)
CntPl:
	LDA GameEngineSubroutine                     ; if executing specific game engine routine,
	CMP #$0b                                     ; branch ahead to some other part
	BEQ PlayerKilled
	LDA PlayerChangeSizeFlag                     ; if grow/shrink flag set
	BNE DoChangeSize                             ; then branch to some other code
	LDY SwimmingFlag                             ; if swimming flag set, branch to
	BEQ FindPlayerAction                         ; different part, do not return
	LDA Player_State
	CMP #$00                                     ; if player status normal,
	BEQ FindPlayerAction                         ; branch and do not return
	JSR FindPlayerAction                         ; otherwise jump and return
	LDA FrameCounter
	AND #%00000100                               ; check frame counter for d2 set (8 frames every
	BNE ExPGH                                    ; eighth frame), and branch if set to leave
	TAX                                          ; initialize X to zero
	LDY Player_SprDataOffset                     ; get player sprite data offset
	LDA PlayerFacingDir                          ; get player's facing direction
	LSR
	BCS SwimKT                                   ; if player facing to the right, use current offset
	INY
	INY                                          ; otherwise move to next OAM data
	INY
	INY
SwimKT:
	LDA PlayerSize                               ; check player's size
	BEQ BigKTS                                   ; if big, use first tile
	LDA Sprite_Tilenumber+24,y                   ; check tile number of seventh/eighth sprite
	CMP SwimTileRepOffset                        ; against tile number in player graphics table
	BEQ ExPGH                                    ; if spr7/spr8 tile number = value, branch to leave
	INX                                          ; otherwise increment X for second tile
BigKTS:
	LDA SwimKickTileNum,x                        ; overwrite tile number in sprite 7/8
	STA Sprite_Tilenumber+24,y                   ; to animate player's feet when swimming
ExPGH:
	RTS                                          ; then leave

FindPlayerAction:
	JSR ProcessPlayerAction                      ; find proper offset to graphics table by player's actions
	JMP PlayerGfxProcessing                      ; draw player, then process for fireball throwing

DoChangeSize:
	JSR HandleChangeSize                         ; find proper offset to graphics table for grow/shrink
	JMP PlayerGfxProcessing                      ; draw player, then process for fireball throwing

PlayerKilled:
	LDY #$0e                                     ; load offset for player killed
	LDA PlayerGfxTblOffsets,y                    ; get offset to graphics table

PlayerGfxProcessing:
	STA PlayerGfxOffset                          ; store offset to graphics table here
	LDA #$04
	JSR RenderPlayerSub                          ; draw player based on offset loaded
	JSR ChkForPlayerAttrib                       ; set horizontal flip bits as necessary
	LDA FireballThrowingTimer
	BEQ PlayerOffscreenChk                       ; if fireball throw timer not set, skip to the end
	LDY #$00                                     ; set value to initialize by default
	LDA PlayerAnimTimer                          ; get animation frame timer
	CMP FireballThrowingTimer                    ; compare to fireball throw timer
	STY FireballThrowingTimer                    ; initialize fireball throw timer
	BCS PlayerOffscreenChk                       ; if animation frame timer => fireball throw timer skip to end
	STA FireballThrowingTimer                    ; otherwise store animation timer into fireball throw timer
	LDY #$07                                     ; load offset for throwing
	LDA PlayerGfxTblOffsets,y                    ; get offset to graphics table
	STA PlayerGfxOffset                          ; store it for use later
	LDY #$04                                     ; set to update four sprite rows by default
	LDA Player_X_Speed
	ORA Left_Right_Buttons                       ; check for horizontal speed or left/right button press
	BEQ SUpdR                                    ; if no speed or button press, branch using set value in Y
	DEY                                          ; otherwise set to update only three sprite rows
SUpdR:
	TYA                                          ; save in A for use
	JSR RenderPlayerSub                          ; in sub, draw player object again

PlayerOffscreenChk:
	LDA Player_OffscreenBits                     ; get player's offscreen bits
	LSR
	LSR                                          ; move vertical bits to low nybble
	LSR
	LSR
	STA $00                                      ; store here
	LDX #$03                                     ; check all four rows of player sprites
	LDA Player_SprDataOffset                     ; get player's sprite data offset
	CLC
	ADC #$18                                     ; add 24 bytes to start at bottom row
	TAY                                          ; set as offset here
PROfsLoop:
	LDA #$f8                                     ; load offscreen Y coordinate just in case
	LSR $00                                      ; shift bit into carry
	BCC NPROffscr                                ; if bit not set, skip, do not move sprites
	JSR DumpTwoSpr                               ; otherwise dump offscreen Y coordinate into sprite data
NPROffscr:
	TYA
	SEC                                          ; subtract eight bytes to do
	SBC #$08                                     ; next row up
	TAY
	DEX                                          ; decrement row counter
	BPL PROfsLoop                                ; do this until all sprite rows are checked
	RTS                                          ; then we are done!

; -------------------------------------------------------------------------------------

IntermediatePlayerData:
	.db $58, $01, $00, $60, $ff, $04

DrawPlayer_Intermediate:
	LDX #$05                                     ; store data into zero page memory
PIntLoop:
	LDA IntermediatePlayerData,x                 ; load data to display player as he always
	STA $02,x                                    ; appears on world/lives display
	DEX
	BPL PIntLoop                                 ; do this until all data is loaded
	LDX #$b8                                     ; load offset for small standing
	LDY #$04                                     ; load sprite data offset
	JSR DrawPlayerLoop                           ; draw player accordingly
	LDA Sprite_Attributes+36                     ; get empty sprite attributes
	ORA #%01000000                               ; set horizontal flip bit for bottom-right sprite
	STA Sprite_Attributes+32                     ; store and leave
	RTS

; -------------------------------------------------------------------------------------
; $00-$01 - used to hold tile numbers, $00 also used to hold upper extent of animation frames
; $02 - vertical position
; $03 - facing direction, used as horizontal flip control
; $04 - attributes
; $05 - horizontal position
; $07 - number of rows to draw
; these also used in IntermediatePlayerData

RenderPlayerSub:
	STA $07                                      ; store number of rows of sprites to draw
	LDA Player_Rel_XPos
	STA Player_Pos_ForScroll                     ; store player's relative horizontal position
	STA $05                                      ; store it here also
	LDA Player_Rel_YPos
	STA $02                                      ; store player's vertical position
	LDA PlayerFacingDir
	STA $03                                      ; store player's facing direction
	LDA Player_SprAttrib
	STA $04                                      ; store player's sprite attributes
	LDX PlayerGfxOffset                          ; load graphics table offset
	LDY Player_SprDataOffset                     ; get player's sprite data offset

DrawPlayerLoop:
	LDA PlayerGraphicsTable,x                    ; load player's left side
	STA $00
	LDA PlayerGraphicsTable+1,x                  ; now load right side
	JSR DrawOneSpriteRow
	DEC $07                                      ; decrement rows of sprites to draw
	BNE DrawPlayerLoop                           ; do this until all rows are drawn
	RTS

ProcessPlayerAction:
	LDA Player_State                             ; get player's state
	CMP #$03
	BEQ ActionClimbing                           ; if climbing, branch here
	CMP #$02
	BEQ ActionFalling                            ; if falling, branch here
	CMP #$01
	BNE ProcOnGroundActs                         ; if not jumping, branch here
	LDA SwimmingFlag
	BNE ActionSwimming                           ; if swimming flag set, branch elsewhere
	LDY #$06                                     ; load offset for crouching
	LDA CrouchingFlag                            ; get crouching flag
	BNE NonAnimatedActs                          ; if set, branch to get offset for graphics table
	LDY #$00                                     ; otherwise load offset for jumping
	JMP NonAnimatedActs                          ; go to get offset to graphics table

ProcOnGroundActs:
	LDY #$06                                     ; load offset for crouching
	LDA CrouchingFlag                            ; get crouching flag
	BNE NonAnimatedActs                          ; if set, branch to get offset for graphics table
	LDY #$02                                     ; load offset for standing
	LDA Player_X_Speed                           ; check player's horizontal speed
	ORA Left_Right_Buttons                       ; and left/right controller bits
	BEQ NonAnimatedActs                          ; if no speed or buttons pressed, use standing offset
	LDA Player_XSpeedAbsolute                    ; load walking/running speed
	CMP #$09
	BCC ActionWalkRun                            ; if less than a certain amount, branch, too slow to skid
	LDA Player_MovingDir                         ; otherwise check to see if moving direction
	AND PlayerFacingDir                          ; and facing direction are the same
	BNE ActionWalkRun                            ; if moving direction = facing direction, branch, don't skid
	INY                                          ; otherwise increment to skid offset ($03)

NonAnimatedActs:
	JSR GetGfxOffsetAdder                        ; do a sub here to get offset adder for graphics table
	LDA #$00
	STA PlayerAnimCtrl                           ; initialize animation frame control
	LDA PlayerGfxTblOffsets,y                    ; load offset to graphics table using size as offset
	RTS

ActionFalling:
	LDY #$04                                     ; load offset for walking/running
	JSR GetGfxOffsetAdder                        ; get offset to graphics table
	JMP GetCurrentAnimOffset                     ; execute instructions for falling state

ActionWalkRun:
	LDY #$04                                     ; load offset for walking/running
	JSR GetGfxOffsetAdder                        ; get offset to graphics table
	JMP FourFrameExtent                          ; execute instructions for normal state

ActionClimbing:
	LDY #$05                                     ; load offset for climbing
	LDA Player_Y_Speed                           ; check player's vertical speed
	BEQ NonAnimatedActs                          ; if no speed, branch, use offset as-is
	JSR GetGfxOffsetAdder                        ; otherwise get offset for graphics table
	JMP ThreeFrameExtent                         ; then skip ahead to more code

ActionSwimming:
	LDY #$01                                     ; load offset for swimming
	JSR GetGfxOffsetAdder
	LDA JumpSwimTimer                            ; check jump/swim timer
	ORA PlayerAnimCtrl                           ; and animation frame control
	BNE FourFrameExtent                          ; if any one of these set, branch ahead
	LDA A_B_Buttons
	ASL                                          ; check for A button pressed
	BCS FourFrameExtent                          ; branch to same place if A button pressed

GetCurrentAnimOffset:
	LDA PlayerAnimCtrl                           ; get animation frame control
	JMP GetOffsetFromAnimCtrl                    ; jump to get proper offset to graphics table

FourFrameExtent:
	LDA #$03                                     ; load upper extent for frame control
	JMP AnimationControl                         ; jump to get offset and animate player object

ThreeFrameExtent:
	LDA #$02                                     ; load upper extent for frame control for climbing

AnimationControl:
	STA $00                                      ; store upper extent here
	JSR GetCurrentAnimOffset                     ; get proper offset to graphics table
	PHA                                          ; save offset to stack
	LDA PlayerAnimTimer                          ; load animation frame timer
	BNE ExAnimC                                  ; branch if not expired
	LDA PlayerAnimTimerSet                       ; get animation frame timer amount
	STA PlayerAnimTimer                          ; and set timer accordingly
	LDA PlayerAnimCtrl
	CLC                                          ; add one to animation frame control
	ADC #$01
	CMP $00                                      ; compare to upper extent
	BCC SetAnimC                                 ; if frame control + 1 < upper extent, use as next
	LDA #$00                                     ; otherwise initialize frame control
SetAnimC:
	STA PlayerAnimCtrl                           ; store as new animation frame control
ExAnimC:
	PLA                                          ; get offset to graphics table from stack and leave
	RTS

GetGfxOffsetAdder:
	LDA PlayerSize                               ; get player's size
	BEQ SzOfs                                    ; if player big, use current offset as-is
	TYA                                          ; for big player
	CLC                                          ; otherwise add eight bytes to offset
	ADC #$08                                     ; for small player
	TAY
SzOfs:
	RTS                                          ; go back

ChangeSizeOffsetAdder:
	.db $00, $01, $00, $01, $00, $01, $02, $00, $01, $02
	.db $02, $00, $02, $00, $02, $00, $02, $00, $02, $00

HandleChangeSize:
	LDY PlayerAnimCtrl                           ; get animation frame control
	LDA FrameCounter
	AND #%00000011                               ; get frame counter and execute this code every
	BNE GorSLog                                  ; fourth frame, otherwise branch ahead
	INY                                          ; increment frame control
	CPY #$0a                                     ; check for preset upper extent
	BCC CSzNext                                  ; if not there yet, skip ahead to use
	LDY #$00                                     ; otherwise initialize both grow/shrink flag
	STY PlayerChangeSizeFlag                     ; and animation frame control
CSzNext:
	STY PlayerAnimCtrl                           ; store proper frame control
GorSLog:
	LDA PlayerSize                               ; get player's size
	BNE ShrinkPlayer                             ; if player small, skip ahead to next part
	LDA ChangeSizeOffsetAdder,y                  ; get offset adder based on frame control as offset
	LDY #$0f                                     ; load offset for player growing

GetOffsetFromAnimCtrl:
	ASL                                          ; multiply animation frame control
	ASL                                          ; by eight to get proper amount
	ASL                                          ; to add to our offset
	ADC PlayerGfxTblOffsets,y                    ; add to offset to graphics table
	RTS                                          ; and return with result in A

ShrinkPlayer:
	TYA                                          ; add ten bytes to frame control as offset
	CLC
	ADC #$0a                                     ; this thing apparently uses two of the swimming frames
	TAX                                          ; to draw the player shrinking
	LDY #$09                                     ; load offset for small player swimming
	LDA ChangeSizeOffsetAdder,x                  ; get what would normally be offset adder
	BNE ShrPlF                                   ; and branch to use offset if nonzero
	LDY #$01                                     ; otherwise load offset for big player swimming
ShrPlF:
	LDA PlayerGfxTblOffsets,y                    ; get offset to graphics table based on offset loaded
	RTS                                          ; and leave

ChkForPlayerAttrib:
	LDY Player_SprDataOffset                     ; get sprite data offset
	LDA GameEngineSubroutine
	CMP #$0b                                     ; if executing specific game engine routine,
	BEQ KilledAtt                                ; branch to change third and fourth row OAM attributes
	LDA PlayerGfxOffset                          ; get graphics table offset
	CMP #$50
	BEQ C_S_IGAtt                                ; if crouch offset, either standing offset,
	CMP #$b8                                     ; or intermediate growing offset,
	BEQ C_S_IGAtt                                ; go ahead and execute code to change
	CMP #$c0                                     ; fourth row OAM attributes only
	BEQ C_S_IGAtt
	CMP #$c8
	BNE ExPlyrAt                                 ; if none of these, branch to leave
KilledAtt:
	LDA Sprite_Attributes+16,y
	AND #%00111111                               ; mask out horizontal and vertical flip bits
	STA Sprite_Attributes+16,y                   ; for third row sprites and save
	LDA Sprite_Attributes+20,y
	AND #%00111111
	ORA #%01000000                               ; set horizontal flip bit for second
	STA Sprite_Attributes+20,y                   ; sprite in the third row
C_S_IGAtt:
	LDA Sprite_Attributes+24,y
	AND #%00111111                               ; mask out horizontal and vertical flip bits
	STA Sprite_Attributes+24,y                   ; for fourth row sprites and save
	LDA Sprite_Attributes+28,y
	AND #%00111111
	ORA #%01000000                               ; set horizontal flip bit for second
	STA Sprite_Attributes+28,y                   ; sprite in the fourth row
ExPlyrAt:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------
; $00 - used in adding to get proper offset

RelativePlayerPosition:
	LDX #$00                                     ; set offsets for relative cooordinates
	LDY #$00                                     ; routine to correspond to player object
	JMP RelWOfs                                  ; get the coordinates

RelativeBubblePosition:
	LDY #$01                                     ; set for air bubble offsets
	JSR GetProperObjOffset                       ; modify X to get proper air bubble offset
	LDY #$03
	JMP RelWOfs                                  ; get the coordinates

RelativeFireballPosition:
	LDY #$00                                     ; set for fireball offsets
	JSR GetProperObjOffset                       ; modify X to get proper fireball offset
	LDY #$02
RelWOfs:
	JSR GetObjRelativePosition                   ; get the coordinates
	LDX ObjectOffset                             ; return original offset
	RTS                                          ; leave

RelativeMiscPosition:
	LDY #$02                                     ; set for misc object offsets
	JSR GetProperObjOffset                       ; modify X to get proper misc object offset
	LDY #$06
	JMP RelWOfs                                  ; get the coordinates

RelativeEnemyPosition:
	LDA #$01                                     ; get coordinates of enemy object
	LDY #$01                                     ; relative to the screen
	JMP VariableObjOfsRelPos

RelativeBlockPosition:
	LDA #$09                                     ; get coordinates of one block object
	LDY #$04                                     ; relative to the screen
	JSR VariableObjOfsRelPos
	INX                                          ; adjust offset for other block object if any
	INX
	LDA #$09
	INY                                          ; adjust other and get coordinates for other one

VariableObjOfsRelPos:
	STX $00                                      ; store value to add to A here
	CLC
	ADC $00                                      ; add A to value stored
	TAX                                          ; use as enemy offset
	JSR GetObjRelativePosition
	LDX ObjectOffset                             ; reload old object offset and leave
	RTS

GetObjRelativePosition:
	LDA SprObject_Y_Position,x                   ; load vertical coordinate low
	STA SprObject_Rel_YPos,y                     ; store here
	LDA SprObject_X_Position,x                   ; load horizontal coordinate
	SEC                                          ; subtract left edge coordinate
	SBC ScreenLeft_X_Pos
	STA SprObject_Rel_XPos,y                     ; store result here
	RTS

; -------------------------------------------------------------------------------------
; $00 - used as temp variable to hold offscreen bits

GetPlayerOffscreenBits:
	LDX #$00                                     ; set offsets for player-specific variables
	LDY #$00                                     ; and get offscreen information about player
	JMP GetOffScreenBitsSet

GetFireballOffscreenBits:
	LDY #$00                                     ; set for fireball offsets
	JSR GetProperObjOffset                       ; modify X to get proper fireball offset
	LDY #$02                                     ; set other offset for fireball's offscreen bits
	JMP GetOffScreenBitsSet                      ; and get offscreen information about fireball

GetBubbleOffscreenBits:
	LDY #$01                                     ; set for air bubble offsets
	JSR GetProperObjOffset                       ; modify X to get proper air bubble offset
	LDY #$03                                     ; set other offset for airbubble's offscreen bits
	JMP GetOffScreenBitsSet                      ; and get offscreen information about air bubble

GetMiscOffscreenBits:
	LDY #$02                                     ; set for misc object offsets
	JSR GetProperObjOffset                       ; modify X to get proper misc object offset
	LDY #$06                                     ; set other offset for misc object's offscreen bits
	JMP GetOffScreenBitsSet                      ; and get offscreen information about misc object

ObjOffsetData:
	.db $07, $16, $0d

GetProperObjOffset:
	TXA                                          ; move offset to A
	CLC
	ADC ObjOffsetData,y                          ; add amount of bytes to offset depending on setting in Y
	TAX                                          ; put back in X and leave
	RTS

GetEnemyOffscreenBits:
	LDA #$01                                     ; set A to add 1 byte in order to get enemy offset
	LDY #$01                                     ; set Y to put offscreen bits in Enemy_OffscreenBits
	JMP SetOffscrBitsOffset

GetBlockOffscreenBits:
	LDA #$09                                     ; set A to add 9 bytes in order to get block obj offset
	LDY #$04                                     ; set Y to put offscreen bits in Block_OffscreenBits

SetOffscrBitsOffset:
	STX $00
	CLC                                          ; add contents of X to A to get
	ADC $00                                      ; appropriate offset, then give back to X
	TAX

GetOffScreenBitsSet:
	TYA                                          ; save offscreen bits offset to stack for now
	PHA
	JSR RunOffscrBitsSubs
	ASL                                          ; move low nybble to high nybble
	ASL
	ASL
	ASL
	ORA $00                                      ; mask together with previously saved low nybble
	STA $00                                      ; store both here
	PLA                                          ; get offscreen bits offset from stack
	TAY
	LDA $00                                      ; get value here and store elsewhere
	STA SprObject_OffscrBits,y
	LDX ObjectOffset
	RTS

RunOffscrBitsSubs:
	JSR GetXOffscreenBits                        ; do subroutine here
	LSR                                          ; move high nybble to low
	LSR
	LSR
	LSR
	STA $00                                      ; store here
	JMP GetYOffscreenBits

; --------------------------------
; (these apply to these three subsections)
; $04 - used to store proper offset
; $05 - used as adder in DividePDiff
; $06 - used to store preset value used to compare to pixel difference in $07
; $07 - used to store difference between coordinates of object and screen edges

XOffscreenBitsData:
	.db $7f, $3f, $1f, $0f, $07, $03, $01, $00
	.db $80, $c0, $e0, $f0, $f8, $fc, $fe, $ff

DefaultXOnscreenOfs:
	.db $07, $0f, $07

GetXOffscreenBits:
	STX $04                                      ; save position in buffer to here
	LDY #$01                                     ; start with right side of screen
XOfsLoop:
	LDA ScreenEdge_X_Pos,y                       ; get pixel coordinate of edge
	SEC                                          ; get difference between pixel coordinate of edge
	SBC SprObject_X_Position,x                   ; and pixel coordinate of object position
	STA $07                                      ; store here
	LDA ScreenEdge_PageLoc,y                     ; get page location of edge
	SBC SprObject_PageLoc,x                      ; subtract from page location of object position
	LDX DefaultXOnscreenOfs,y                    ; load offset value here
	CMP #$00
	BMI XLdBData                                 ; if beyond right edge or in front of left edge, branch
	LDX DefaultXOnscreenOfs+1,y                  ; if not, load alternate offset value here
	CMP #$01
	BPL XLdBData                                 ; if one page or more to the left of either edge, branch
	LDA #$38                                     ; if no branching, load value here and store
	STA $06
	LDA #$08                                     ; load some other value and execute subroutine
	JSR DividePDiff
XLdBData:
	LDA XOffscreenBitsData,x                     ; get bits here
	LDX $04                                      ; reobtain position in buffer
	CMP #$00                                     ; if bits not zero, branch to leave
	BNE ExXOfsBS
	DEY                                          ; otherwise, do left side of screen now
	BPL XOfsLoop                                 ; branch if not already done with left side
ExXOfsBS:
	RTS

; --------------------------------

YOffscreenBitsData:
	.db $00, $08, $0c, $0e
	.db $0f, $07, $03, $01
	.db $00

DefaultYOnscreenOfs:
	.db $04, $00, $04

HighPosUnitData:
	.db $ff, $00

GetYOffscreenBits:
	STX $04                                      ; save position in buffer to here
	LDY #$01                                     ; start with top of screen
YOfsLoop:
	LDA HighPosUnitData,y                        ; load coordinate for edge of vertical unit
	SEC
	SBC SprObject_Y_Position,x                   ; subtract from vertical coordinate of object
	STA $07                                      ; store here
	LDA #$01                                     ; subtract one from vertical high byte of object
	SBC SprObject_Y_HighPos,x
	LDX DefaultYOnscreenOfs,y                    ; load offset value here
	CMP #$00
	BMI YLdBData                                 ; if under top of the screen or beyond bottom, branch
	LDX DefaultYOnscreenOfs+1,y                  ; if not, load alternate offset value here
	CMP #$01
	BPL YLdBData                                 ; if one vertical unit or more above the screen, branch
	LDA #$20                                     ; if no branching, load value here and store
	STA $06
	LDA #$04                                     ; load some other value and execute subroutine
	JSR DividePDiff
YLdBData:
	LDA YOffscreenBitsData,x                     ; get offscreen data bits using offset
	LDX $04                                      ; reobtain position in buffer
	CMP #$00
	BNE ExYOfsBS                                 ; if bits not zero, branch to leave
	DEY                                          ; otherwise, do bottom of the screen now
	BPL YOfsLoop
ExYOfsBS:
	RTS

; --------------------------------

DividePDiff:
	STA $05                                      ; store current value in A here
	LDA $07                                      ; get pixel difference
	CMP $06                                      ; compare to preset value
	BCS ExDivPD                                  ; if pixel difference >= preset value, branch
	LSR                                          ; divide by eight
	LSR
	LSR
	AND #$07                                     ; mask out all but 3 LSB
	CPY #$01                                     ; right side of the screen or top?
	BCS SetOscrO                                 ; if so, branch, use difference / 8 as offset
	ADC $05                                      ; if not, add value to difference / 8
SetOscrO:
	TAX                                          ; use as offset
ExDivPD:
	RTS                                          ; leave

; -------------------------------------------------------------------------------------
; $00-$01 - tile numbers
; $02 - Y coordinate
; $03 - flip control
; $04 - sprite attributes
; $05 - X coordinate

DrawSpriteObject:
	LDA $03                                      ; get saved flip control bits
	LSR
	LSR                                          ; move d1 into carry
	LDA $00
	BCC NoHFlip                                  ; if d1 not set, branch
	STA Sprite_Tilenumber+4,y                    ; store first tile into second sprite
	LDA $01                                      ; and second into first sprite
	STA Sprite_Tilenumber,y
	LDA #$40                                     ; activate horizontal flip OAM attribute
	BNE SetHFAt                                  ; and unconditionally branch
NoHFlip:
	STA Sprite_Tilenumber,y                      ; store first tile into first sprite
	LDA $01                                      ; and second into second sprite
	STA Sprite_Tilenumber+4,y
	LDA #$00                                     ; clear bit for horizontal flip
SetHFAt:
	ORA $04                                      ; add other OAM attributes if necessary
	STA Sprite_Attributes,y                      ; store sprite attributes
	STA Sprite_Attributes+4,y
	LDA $02                                      ; now the y coordinates
	STA Sprite_Y_Position,y                      ; note because they are
	STA Sprite_Y_Position+4,y                    ; side by side, they are the same
	LDA $05
	STA Sprite_X_Position,y                      ; store x coordinate, then
	CLC                                          ; add 8 pixels and store another to
	ADC #$08                                     ; put them side by side
	STA Sprite_X_Position+4,y
	LDA $02                                      ; add eight pixels to the next y
	CLC                                          ; coordinate
	ADC #$08
	STA $02
	TYA                                          ; add eight to the offset in Y to
	CLC                                          ; move to the next two sprites
	ADC #$08
	TAY
	INX                                          ; increment offset to return it to the
	INX                                          ; routine that called this subroutine
	RTS

; -------------------------------------------------------------------------------------


; -------------------------------------------------------------------------------------

	.include "src/music-engine.asm"

; --------------------------------

	.include "src/music-data.asm"

; -------------------------------------------------------------------------------------
; INTERRUPT VECTORS

	.pad $FFFA, $FF

	.dw NonMaskableInterrupt
	.dw Start
	.dw $fff0                                    ; unused

