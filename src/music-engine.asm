SoundEngine:
	LDA OperMode                                 ; are we in title screen mode?
	BNE SndOn
	STA SND_MASTERCTRL_REG                       ; if so, disable sound and leave
	RTS
SndOn:
	LDA #$ff
	STA JOYPAD_PORT2                             ; disable irqs and set frame counter mode???
	LDA #$0f
	STA SND_MASTERCTRL_REG                       ; enable first four channels
	LDA PauseModeFlag                            ; is sound already in pause mode?
	BNE InPause
	LDA PauseSoundQueue                          ; if not, check pause sfx queue
	CMP #$01
	BNE RunSoundSubroutines                      ; if queue is empty, skip pause mode routine
InPause:
	LDA PauseSoundBuffer                         ; check pause sfx buffer
	BNE ContPau
	LDA PauseSoundQueue                          ; check pause queue
	BEQ SkipSoundSubroutines
	STA PauseSoundBuffer                         ; if queue full, store in buffer and activate
	STA PauseModeFlag                            ; pause mode to interrupt game sounds
	LDA #$00                                     ; disable sound and clear sfx buffers
	STA SND_MASTERCTRL_REG
	STA Square1SoundBuffer
	STA Square2SoundBuffer
	STA NoiseSoundBuffer
	LDA #$0f
	STA SND_MASTERCTRL_REG                       ; enable sound again
	LDA #$2a                                     ; store length of sound in pause counter
	STA Squ1_SfxLenCounter
PTone1F:
	LDA #$44                                     ; play first tone
	BNE PTRegC                                   ; unconditional branch
ContPau:
	LDA Squ1_SfxLenCounter                       ; check pause length left
	CMP #$24                                     ; time to play second?
	BEQ PTone2F
	CMP #$1e                                     ; time to play first again?
	BEQ PTone1F
	CMP #$18                                     ; time to play second again?
	BNE DecPauC                                  ; only load regs during times, otherwise skip
PTone2F:
	LDA #$64                                     ; store reg contents and play the pause sfx
PTRegC:
	LDX #$84
	LDY #$7f
	JSR PlaySqu1Sfx
DecPauC:
	DEC Squ1_SfxLenCounter                       ; decrement pause sfx counter
	BNE SkipSoundSubroutines
	LDA #$00                                     ; disable sound if in pause mode and
	STA SND_MASTERCTRL_REG                       ; not currently playing the pause sfx
	LDA PauseSoundBuffer                         ; if no longer playing pause sfx, check to see
	CMP #$02                                     ; if we need to be playing sound again
	BNE SkipPIn
	LDA #$00                                     ; clear pause mode to allow game sounds again
	STA PauseModeFlag
SkipPIn:
	LDA #$00                                     ; clear pause sfx buffer
	STA PauseSoundBuffer
	BEQ SkipSoundSubroutines

RunSoundSubroutines:
	JSR Square1SfxHandler                        ; play sfx on square channel 1
	JSR Square2SfxHandler                        ; ''  ''  '' square channel 2
	JSR NoiseSfxHandler                          ; ''  ''  '' noise channel
	JSR MusicHandler                             ; play music on all channels
	LDA #$00                                     ; clear the music queues
	STA AreaMusicQueue
	STA EventMusicQueue

SkipSoundSubroutines:
	LDA #$00                                     ; clear the sound effects queues
	STA Square1SoundQueue
	STA Square2SoundQueue
	STA NoiseSoundQueue
	STA PauseSoundQueue
	LDY DAC_Counter                              ; load some sort of counter
	LDA AreaMusicBuffer
	AND #%00000011                               ; check for specific music
	BEQ NoIncDAC
	INC DAC_Counter                              ; increment and check counter
	CPY #$30
	BCC StrWave                                  ; if not there yet, just store it
NoIncDAC:
	TYA
	BEQ StrWave                                  ; if we are at zero, do not decrement
	DEC DAC_Counter                              ; decrement counter
StrWave:
	STY SND_DELTA_REG+1                          ; store into DMC load register (??)
	RTS                                          ; we are done here

; --------------------------------

Dump_Squ1_Regs:
	STY SND_SQUARE1_REG+1                        ; dump the contents of X and Y into square 1's control regs
	STX SND_SQUARE1_REG
	RTS

PlaySqu1Sfx:
	JSR Dump_Squ1_Regs                           ; do sub to set ctrl regs for square 1, then set frequency regs

SetFreq_Squ1:
	LDX #$00                                     ; set frequency reg offset for square 1 sound channel

Dump_Freq_Regs:
	TAY
	LDA FreqRegLookupTbl+1,y                     ; use previous contents of A for sound reg offset
	BEQ NoTone                                   ; if zero, then do not load
	STA SND_REGISTER+2,x                         ; first byte goes into LSB of frequency divider
	LDA FreqRegLookupTbl,y                       ; second byte goes into 3 MSB plus extra bit for
	ORA #%00001000                               ; length counter
	STA SND_REGISTER+3,x
NoTone:
	RTS

Dump_Sq2_Regs:
	STX SND_SQUARE2_REG                          ; dump the contents of X and Y into square 2's control regs
	STY SND_SQUARE2_REG+1
	RTS

PlaySqu2Sfx:
	JSR Dump_Sq2_Regs                            ; do sub to set ctrl regs for square 2, then set frequency regs

SetFreq_Squ2:
	LDX #$04                                     ; set frequency reg offset for square 2 sound channel
	BNE Dump_Freq_Regs                           ; unconditional branch

SetFreq_Tri:
	LDX #$08                                     ; set frequency reg offset for triangle sound channel
	BNE Dump_Freq_Regs                           ; unconditional branch

; --------------------------------

SwimStompEnvelopeData:
	.db $9f, $9b, $98, $96, $95, $94, $92, $90
	.db $90, $9a, $97, $95, $93, $92

PlayFlagpoleSlide:
	LDA #$40                                     ; store length of flagpole sound
	STA Squ1_SfxLenCounter
	LDA #$62                                     ; load part of reg contents for flagpole sound
	JSR SetFreq_Squ1
	LDX #$99                                     ; now load the rest
	BNE FPS2nd

PlaySmallJump:
	LDA #$26                                     ; branch here for small mario jumping sound
	BNE JumpRegContents

PlayBigJump:
	LDA #$18                                     ; branch here for big mario jumping sound

JumpRegContents:
	LDX #$82                                     ; note that small and big jump borrow each others' reg contents
	LDY #$a7                                     ; anyway, this loads the first part of mario's jumping sound
	JSR PlaySqu1Sfx
	LDA #$28                                     ; store length of sfx for both jumping sounds
	STA Squ1_SfxLenCounter                       ; then continue on here

ContinueSndJump:
	LDA Squ1_SfxLenCounter                       ; jumping sounds seem to be composed of three parts
	CMP #$25                                     ; check for time to play second part yet
	BNE N2Prt
	LDX #$5f                                     ; load second part
	LDY #$f6
	BNE DmpJpFPS                                 ; unconditional branch
N2Prt:
	CMP #$20                                     ; check for third part
	BNE DecJpFPS
	LDX #$48                                     ; load third part
FPS2nd:
	LDY #$bc                                     ; the flagpole slide sound shares part of third part
DmpJpFPS:
	JSR Dump_Squ1_Regs
	BNE DecJpFPS                                 ; unconditional branch outta here

PlayFireballThrow:
	LDA #$05
	LDY #$99                                     ; load reg contents for fireball throw sound
	BNE Fthrow                                   ; unconditional branch

PlayBump:
	LDA #$0a                                     ; load length of sfx and reg contents for bump sound
	LDY #$93
Fthrow:
	LDX #$9e                                     ; the fireball sound shares reg contents with the bump sound
	STA Squ1_SfxLenCounter
	LDA #$0c                                     ; load offset for bump sound
	JSR PlaySqu1Sfx

ContinueBumpThrow:

	LDA Squ1_SfxLenCounter                       ; check for second part of bump sound
	CMP #$06
	BNE DecJpFPS
	LDA #$bb                                     ; load second part directly
	STA SND_SQUARE1_REG+1
DecJpFPS:
	BNE BranchToDecLength1                       ; unconditional branch


Square1SfxHandler:
	LDY Square1SoundQueue                        ; check for sfx in queue
	BEQ CheckSfx1Buffer
	STY Square1SoundBuffer                       ; if found, put in buffer
	BMI PlaySmallJump                            ; small jump
	LSR Square1SoundQueue
	BCS PlayBigJump                              ; big jump
	LSR Square1SoundQueue
	BCS PlayBump                                 ; bump
	LSR Square1SoundQueue
	BCS PlaySwimStomp                            ; swim/stomp
	LSR Square1SoundQueue
	BCS PlaySmackEnemy                           ; smack enemy
	LSR Square1SoundQueue
	BCS PlayPipeDownInj                          ; pipedown/injury
	LSR Square1SoundQueue
	BCS PlayFireballThrow                        ; fireball throw
	LSR Square1SoundQueue
	BCS PlayFlagpoleSlide                        ; slide flagpole

CheckSfx1Buffer:
	LDA Square1SoundBuffer                       ; check for sfx in buffer
	BEQ ExS1H                                    ; if not found, exit sub
	BMI ContinueSndJump                          ; small mario jump
	LSR
	BCS ContinueSndJump                          ; big mario jump
	LSR
	BCS ContinueBumpThrow                        ; bump
	LSR
	BCS ContinueSwimStomp                        ; swim/stomp
	LSR
	BCS ContinueSmackEnemy                       ; smack enemy
	LSR
	BCS ContinuePipeDownInj                      ; pipedown/injury
	LSR
	BCS ContinueBumpThrow                        ; fireball throw
	LSR
	BCS DecrementSfx1Length                      ; slide flagpole
ExS1H:
	RTS

PlaySwimStomp:
	LDA #$0e                                     ; store length of swim/stomp sound
	STA Squ1_SfxLenCounter
	LDY #$9c                                     ; store reg contents for swim/stomp sound
	LDX #$9e
	LDA #$26
	JSR PlaySqu1Sfx

ContinueSwimStomp:

	LDY Squ1_SfxLenCounter                       ; look up reg contents in data section based on
	LDA SwimStompEnvelopeData-1,y                ; length of sound left, used to control sound's
	STA SND_SQUARE1_REG                          ; envelope
	CPY #$06
	BNE BranchToDecLength1
	LDA #$9e                                     ; when the length counts down to a certain point, put this
	STA SND_SQUARE1_REG+2                        ; directly into the LSB of square 1's frequency divider

BranchToDecLength1:

	BNE DecrementSfx1Length                      ; unconditional branch (regardless of how we got here)

PlaySmackEnemy:
	LDA #$0e                                     ; store length of smack enemy sound
	LDY #$cb
	LDX #$9f
	STA Squ1_SfxLenCounter
	LDA #$28                                     ; store reg contents for smack enemy sound
	JSR PlaySqu1Sfx
	BNE DecrementSfx1Length                      ; unconditional branch

ContinueSmackEnemy:
	LDY Squ1_SfxLenCounter                       ; check about halfway through
	CPY #$08
	BNE SmSpc
	LDA #$a0                                     ; if we're at the about-halfway point, make the second tone
	STA SND_SQUARE1_REG+2                        ; in the smack enemy sound
	LDA #$9f
	BNE SmTick
SmSpc:
	LDA #$90                                     ; this creates spaces in the sound, giving it its distinct noise
SmTick:
	STA SND_SQUARE1_REG

DecrementSfx1Length:
	DEC Squ1_SfxLenCounter                       ; decrement length of sfx
	BNE ExSfx1

StopSquare1Sfx:
	LDX #$00                                     ; if end of sfx reached, clear buffer
	STX $f1                                      ; and stop making the sfx
	LDX #$0e
	STX SND_MASTERCTRL_REG
	LDX #$0f
	STX SND_MASTERCTRL_REG
ExSfx1:
	RTS

PlayPipeDownInj:

	LDA #$2f                                     ; load length of pipedown sound
	STA Squ1_SfxLenCounter

ContinuePipeDownInj:
	LDA Squ1_SfxLenCounter                       ; some bitwise logic, forces the regs
	LSR                                          ; to be written to only during six specific times
	BCS NoPDwnL                                  ; during which d3 must be set and d1-0 must be clear
	LSR
	BCS NoPDwnL
	AND #%00000010
	BEQ NoPDwnL
	LDY #$91                                     ; and this is where it actually gets written in
	LDX #$9a
	LDA #$44
	JSR PlaySqu1Sfx
NoPDwnL:
	JMP DecrementSfx1Length

; --------------------------------

ExtraLifeFreqData:
	.db $58, $02, $54, $56, $4e, $44

PowerUpGrabFreqData:
	.db $4c, $52, $4c, $48, $3e, $36, $3e, $36, $30
	.db $28, $4a, $50, $4a, $64, $3c, $32, $3c, $32
	.db $2c, $24, $3a, $64, $3a, $34, $2c, $22, $2c

; residual frequency data
	.db $22, $1c, $14

PUp_VGrow_FreqData:
	.db $14, $04, $22, $24, $16, $04, $24, $26   ; used by both
	.db $18, $04, $26, $28, $1a, $04, $28, $2a
	.db $1c, $04, $2a, $2c, $1e, $04, $2c, $2e   ; used by vinegrow
	.db $20, $04, $2e, $30, $22, $04, $30, $32

PlayCoinGrab:
	LDA #$35                                     ; load length of coin grab sound
	LDX #$8d                                     ; and part of reg contents
	BNE CGrab_TTickRegL

PlayTimerTick:
	LDA #$06                                     ; load length of timer tick sound
	LDX #$98                                     ; and part of reg contents

CGrab_TTickRegL:
	STA Squ2_SfxLenCounter
	LDY #$7f                                     ; load the rest of reg contents
	LDA #$42                                     ; of coin grab and timer tick sound
	JSR PlaySqu2Sfx

ContinueCGrabTTick:
	LDA Squ2_SfxLenCounter                       ; check for time to play second tone yet
	CMP #$30                                     ; timer tick sound also executes this, not sure why
	BNE N2Tone
	LDA #$54                                     ; if so, load the tone directly into the reg
	STA SND_SQUARE2_REG+2
N2Tone:
	BNE DecrementSfx2Length

PlayBlast:
	LDA #$20                                     ; load length of fireworks/gunfire sound
	STA Squ2_SfxLenCounter
	LDY #$94                                     ; load reg contents of fireworks/gunfire sound
	LDA #$5e
	BNE SBlasJ

ContinueBlast:
	LDA Squ2_SfxLenCounter                       ; check for time to play second part
	CMP #$18
	BNE DecrementSfx2Length
	LDY #$93                                     ; load second part reg contents then
	LDA #$18
SBlasJ:
	BNE BlstSJp                                  ; unconditional branch to load rest of reg contents

PlayPowerUpGrab:
	LDA #$36                                     ; load length of power-up grab sound
	STA Squ2_SfxLenCounter

ContinuePowerUpGrab:

	LDA Squ2_SfxLenCounter                       ; load frequency reg based on length left over
	LSR                                          ; divide by 2
	BCS DecrementSfx2Length                      ; alter frequency every other frame
	TAY
	LDA PowerUpGrabFreqData-1,y                  ; use length left over / 2 for frequency offset
	LDX #$5d                                     ; store reg contents of power-up grab sound
	LDY #$7f

LoadSqu2Regs:
	JSR PlaySqu2Sfx

DecrementSfx2Length:
	DEC Squ2_SfxLenCounter                       ; decrement length of sfx
	BNE ExSfx2

EmptySfx2Buffer:
	LDX #$00                                     ; initialize square 2's sound effects buffer
	STX Square2SoundBuffer

StopSquare2Sfx:
	LDX #$0d                                     ; stop playing the sfx
	STX SND_MASTERCTRL_REG
	LDX #$0f
	STX SND_MASTERCTRL_REG
ExSfx2:
	RTS

Square2SfxHandler:
	LDA Square2SoundBuffer                       ; special handling for the 1-up sound to keep it
	AND #Sfx_ExtraLife                           ; from being interrupted by other sounds on square 2
	BNE ContinueExtraLife
	LDY Square2SoundQueue                        ; check for sfx in queue
	BEQ CheckSfx2Buffer
	STY Square2SoundBuffer                       ; if found, put in buffer and check for the following
	BMI PlayBowserFall                           ; bowser fall
	LSR Square2SoundQueue
	BCS PlayCoinGrab                             ; coin grab
	LSR Square2SoundQueue
	BCS PlayGrowPowerUp                          ; power-up reveal
	LSR Square2SoundQueue
	BCS PlayGrowVine                             ; vine grow
	LSR Square2SoundQueue
	BCS PlayBlast                                ; fireworks/gunfire
	LSR Square2SoundQueue
	BCS PlayTimerTick                            ; timer tick
	LSR Square2SoundQueue
	BCS PlayPowerUpGrab                          ; power-up grab
	LSR Square2SoundQueue
	BCS PlayExtraLife                            ; 1-up

CheckSfx2Buffer:
	LDA Square2SoundBuffer                       ; check for sfx in buffer
	BEQ ExS2H                                    ; if not found, exit sub
	BMI ContinueBowserFall                       ; bowser fall
	LSR
	BCS Cont_CGrab_TTick                         ; coin grab
	LSR
	BCS ContinueGrowItems                        ; power-up reveal
	LSR
	BCS ContinueGrowItems                        ; vine grow
	LSR
	BCS ContinueBlast                            ; fireworks/gunfire
	LSR
	BCS Cont_CGrab_TTick                         ; timer tick
	LSR
	BCS ContinuePowerUpGrab                      ; power-up grab
	LSR
	BCS ContinueExtraLife                        ; 1-up
ExS2H:
	RTS

Cont_CGrab_TTick:
	JMP ContinueCGrabTTick

JumpToDecLength2:
	JMP DecrementSfx2Length

PlayBowserFall:

	LDA #$38                                     ; load length of bowser defeat sound
	STA Squ2_SfxLenCounter
	LDY #$c4                                     ; load contents of reg for bowser defeat sound
	LDA #$18
BlstSJp:
	BNE PBFRegs

ContinueBowserFall:
	LDA Squ2_SfxLenCounter                       ; check for almost near the end
	CMP #$08
	BNE DecrementSfx2Length
	LDY #$a4                                     ; if so, load the rest of reg contents for bowser defeat sound
	LDA #$5a
PBFRegs:
	LDX #$9f                                     ; the fireworks/gunfire sound shares part of reg contents here
EL_LRegs:
	BNE LoadSqu2Regs                             ; this is an unconditional branch outta here

PlayExtraLife:
	LDA #$30                                     ; load length of 1-up sound
	STA Squ2_SfxLenCounter

ContinueExtraLife:
	LDA Squ2_SfxLenCounter
	LDX #$03                                     ; load new tones only every eight frames
DivLLoop:
	LSR
	BCS JumpToDecLength2                         ; if any bits set here, branch to dec the length
	DEX
	BNE DivLLoop                                 ; do this until all bits checked, if none set, continue
	TAY
	LDA ExtraLifeFreqData-1,y                    ; load our reg contents
	LDX #$82
	LDY #$7f
	BNE EL_LRegs                                 ; unconditional branch

PlayGrowPowerUp:
	LDA #$10                                     ; load length of power-up reveal sound
	BNE GrowItemRegs

PlayGrowVine:
	LDA #$20                                     ; load length of vine grow sound

GrowItemRegs:
	STA Squ2_SfxLenCounter
	LDA #$7f                                     ; load contents of reg for both sounds directly
	STA SND_SQUARE2_REG+1
	LDA #$00                                     ; start secondary counter for both sounds
	STA Sfx_SecondaryCounter

ContinueGrowItems:
	INC Sfx_SecondaryCounter                     ; increment secondary counter for both sounds
	LDA Sfx_SecondaryCounter                     ; this sound doesn't decrement the usual counter
	LSR                                          ; divide by 2 to get the offset
	TAY
	CPY Squ2_SfxLenCounter                       ; have we reached the end yet?
	BEQ StopGrowItems                            ; if so, branch to jump, and stop playing sounds
	LDA #$9d                                     ; load contents of other reg directly
	STA SND_SQUARE2_REG
	LDA PUp_VGrow_FreqData,y                     ; use secondary counter / 2 as offset for frequency regs
	JSR SetFreq_Squ2
	RTS

StopGrowItems:
	JMP EmptySfx2Buffer                          ; branch to stop playing sounds

; --------------------------------

BrickShatterFreqData:
	.db $01, $0e, $0e, $0d, $0b, $06, $0c, $0f
	.db $0a, $09, $03, $0d, $08, $0d, $06, $0c

PlayBrickShatter:
	LDA #$20                                     ; load length of brick shatter sound
	STA Noise_SfxLenCounter

ContinueBrickShatter:
	LDA Noise_SfxLenCounter
	LSR                                          ; divide by 2 and check for bit set to use offset
	BCC DecrementSfx3Length
	TAY
	LDX BrickShatterFreqData,y                   ; load reg contents of brick shatter sound
	LDA BrickShatterEnvData,y

PlayNoiseSfx:
	STA SND_NOISE_REG                            ; play the sfx
	STX SND_NOISE_REG+2
	LDA #$18
	STA SND_NOISE_REG+3

DecrementSfx3Length:
	DEC Noise_SfxLenCounter                      ; decrement length of sfx
	BNE ExSfx3
	LDA #$f0                                     ; if done, stop playing the sfx
	STA SND_NOISE_REG
	LDA #$00
	STA NoiseSoundBuffer
ExSfx3:
	RTS

NoiseSfxHandler:
	LDY NoiseSoundQueue                          ; check for sfx in queue
	BEQ CheckNoiseBuffer
	STY NoiseSoundBuffer                         ; if found, put in buffer
	LSR NoiseSoundQueue
	BCS PlayBrickShatter                         ; brick shatter
	LSR NoiseSoundQueue
	BCS PlayBowserFlame                          ; bowser flame

CheckNoiseBuffer:
	LDA NoiseSoundBuffer                         ; check for sfx in buffer
	BEQ ExNH                                     ; if not found, exit sub
	LSR
	BCS ContinueBrickShatter                     ; brick shatter
	LSR
	BCS ContinueBowserFlame                      ; bowser flame
ExNH:
	RTS

PlayBowserFlame:
	LDA #$40                                     ; load length of bowser flame sound
	STA Noise_SfxLenCounter

ContinueBowserFlame:
	LDA Noise_SfxLenCounter
	LSR
	TAY
	LDX #$0f                                     ; load reg contents of bowser flame sound
	LDA BowserFlameEnvData-1,y
	BNE PlayNoiseSfx                             ; unconditional branch here

; --------------------------------

ContinueMusic:
	JMP HandleSquare2Music                       ; if we have music, start with square 2 channel

MusicHandler:
	LDA EventMusicQueue                          ; check event music queue
	BNE LoadEventMusic
	LDA AreaMusicQueue                           ; check area music queue
	BNE LoadAreaMusic
	LDA EventMusicBuffer                         ; check both buffers
	ORA AreaMusicBuffer
	BNE ContinueMusic
	RTS                                          ; no music, then leave

LoadEventMusic:
	STA EventMusicBuffer                         ; copy event music queue contents to buffer
	CMP #DeathMusic                              ; is it death music?
	BNE NoStopSfx                                ; if not, jump elsewhere
	JSR StopSquare1Sfx                           ; stop sfx in square 1 and 2
	JSR StopSquare2Sfx                           ; but clear only square 1's sfx buffer
NoStopSfx:
	LDX AreaMusicBuffer
	STX AreaMusicBuffer_Alt                      ; save current area music buffer to be re-obtained later
	LDY #$00
	STY NoteLengthTblAdder                       ; default value for additional length byte offset
	STY AreaMusicBuffer                          ; clear area music buffer
	CMP #TimeRunningOutMusic                     ; is it time running out music?
	BNE FindEventMusicHeader
	LDX #$08                                     ; load offset to be added to length byte of header
	STX NoteLengthTblAdder
	BNE FindEventMusicHeader                     ; unconditional branch

LoadAreaMusic:
	CMP #$04                                     ; is it underground music?
	BNE NoStop1                                  ; no, do not stop square 1 sfx
	JSR StopSquare1Sfx
NoStop1:
	LDY #$10                                     ; start counter used only by ground level music
GMLoopB:
	STY GroundMusicHeaderOfs

HandleAreaMusicLoopB:
	LDY #$00                                     ; clear event music buffer
	STY EventMusicBuffer
	STA AreaMusicBuffer                          ; copy area music queue contents to buffer
	CMP #$01                                     ; is it ground level music?
	BNE FindAreaMusicHeader
	INC GroundMusicHeaderOfs                     ; increment but only if playing ground level music
	LDY GroundMusicHeaderOfs                     ; is it time to loopback ground level music?
	CPY #$32
	BNE LoadHeader                               ; branch ahead with alternate offset
	LDY #$11
	BNE GMLoopB                                  ; unconditional branch

FindAreaMusicHeader:
	LDY #$08                                     ; load Y for offset of area music
	STY MusicOffset_Square2                      ; residual instruction here

FindEventMusicHeader:
	INY                                          ; increment Y pointer based on previously loaded queue contents
	LSR                                          ; bit shift and increment until we find a set bit for music
	BCC FindEventMusicHeader

LoadHeader:
	LDA MusicHeaderOffsetData,y                  ; load offset for header
	TAY
	LDA MusicHeaderData,y                        ; now load the header
	STA NoteLenLookupTblOfs
	LDA MusicHeaderData+1,y
	STA MusicDataLow
	LDA MusicHeaderData+2,y
	STA MusicDataHigh
	LDA MusicHeaderData+3,y
	STA MusicOffset_Triangle
	LDA MusicHeaderData+4,y
	STA MusicOffset_Square1
	LDA MusicHeaderData+5,y
	STA MusicOffset_Noise
	STA NoiseDataLoopbackOfs
	LDA #$01                                     ; initialize music note counters
	STA Squ2_NoteLenCounter
	STA Squ1_NoteLenCounter
	STA Tri_NoteLenCounter
	STA Noise_BeatLenCounter
	LDA #$00                                     ; initialize music data offset for square 2
	STA MusicOffset_Square2
	STA AltRegContentFlag                        ; initialize alternate control reg data used by square 1
	LDA #$0b                                     ; disable triangle channel and reenable it
	STA SND_MASTERCTRL_REG
	LDA #$0f
	STA SND_MASTERCTRL_REG

HandleSquare2Music:
	DEC Squ2_NoteLenCounter                      ; decrement square 2 note length
	BNE MiscSqu2MusicTasks                       ; is it time for more data?  if not, branch to end tasks
	LDY MusicOffset_Square2                      ; increment square 2 music offset and fetch data
	INC MusicOffset_Square2
	LDA (MusicData),y
	BEQ EndOfMusicData                           ; if zero, the data is a null terminator
	BPL Squ2NoteHandler                          ; if non-negative, data is a note
	BNE Squ2LengthHandler                        ; otherwise it is length data

EndOfMusicData:
	LDA EventMusicBuffer                         ; check secondary buffer for time running out music
	CMP #TimeRunningOutMusic
	BNE NotTRO
	LDA AreaMusicBuffer_Alt                      ; load previously saved contents of primary buffer
	BNE MusicLoopBack                            ; and start playing the song again if there is one
NotTRO:
	AND #VictoryMusic                            ; check for victory music (the only secondary that loops)
	BNE VictoryMLoopBack
	LDA AreaMusicBuffer                          ; check primary buffer for any music except pipe intro
	AND #%01011111
	BNE MusicLoopBack                            ; if any area music except pipe intro, music loops
	LDA #$00                                     ; clear primary and secondary buffers and initialize
	STA AreaMusicBuffer                          ; control regs of square and triangle channels
	STA EventMusicBuffer
	STA SND_TRIANGLE_REG
	LDA #$90
	STA SND_SQUARE1_REG
	STA SND_SQUARE2_REG
	RTS

MusicLoopBack:
	JMP HandleAreaMusicLoopB

VictoryMLoopBack:
	JMP LoadEventMusic

Squ2LengthHandler:
	JSR ProcessLengthData                        ; store length of note
	STA Squ2_NoteLenBuffer
	LDY MusicOffset_Square2                      ; fetch another byte (MUST NOT BE LENGTH BYTE!)
	INC MusicOffset_Square2
	LDA (MusicData),y

Squ2NoteHandler:
	LDX Square2SoundBuffer                       ; is there a sound playing on this channel?
	BNE SkipFqL1
	JSR SetFreq_Squ2                             ; no, then play the note
	BEQ Rest                                     ; check to see if note is rest
	JSR LoadControlRegs                          ; if not, load control regs for square 2
Rest:
	STA Squ2_EnvelopeDataCtrl                    ; save contents of A
	JSR Dump_Sq2_Regs                            ; dump X and Y into square 2 control regs
SkipFqL1:
	LDA Squ2_NoteLenBuffer                       ; save length in square 2 note counter
	STA Squ2_NoteLenCounter

MiscSqu2MusicTasks:
	LDA Square2SoundBuffer                       ; is there a sound playing on square 2?
	BNE HandleSquare1Music
	LDA EventMusicBuffer                         ; check for death music or d4 set on secondary buffer
	AND #%10010001                               ; note that regs for death music or d4 are loaded by default
	BNE HandleSquare1Music
	LDY Squ2_EnvelopeDataCtrl                    ; check for contents saved from LoadControlRegs
	BEQ NoDecEnv1
	DEC Squ2_EnvelopeDataCtrl                    ; decrement unless already zero
NoDecEnv1:
	JSR LoadEnvelopeData                         ; do a load of envelope data to replace default
	STA SND_SQUARE2_REG                          ; based on offset set by first load unless playing
	LDX #$7f                                     ; death music or d4 set on secondary buffer
	STX SND_SQUARE2_REG+1

HandleSquare1Music:
	LDY MusicOffset_Square1                      ; is there a nonzero offset here?
	BEQ HandleTriangleMusic                      ; if not, skip ahead to the triangle channel
	DEC Squ1_NoteLenCounter                      ; decrement square 1 note length
	BNE MiscSqu1MusicTasks                       ; is it time for more data?

FetchSqu1MusicData:
	LDY MusicOffset_Square1                      ; increment square 1 music offset and fetch data
	INC MusicOffset_Square1
	LDA (MusicData),y
	BNE Squ1NoteHandler                          ; if nonzero, then skip this part
	LDA #$83
	STA SND_SQUARE1_REG                          ; store some data into control regs for square 1
	LDA #$94                                     ; and fetch another byte of data, used to give
	STA SND_SQUARE1_REG+1                        ; death music its unique sound
	STA AltRegContentFlag
	BNE FetchSqu1MusicData                       ; unconditional branch

Squ1NoteHandler:
	JSR AlternateLengthHandler
	STA Squ1_NoteLenCounter                      ; save contents of A in square 1 note counter
	LDY Square1SoundBuffer                       ; is there a sound playing on square 1?
	BNE HandleTriangleMusic
	TXA
	AND #%00111110                               ; change saved data to appropriate note format
	JSR SetFreq_Squ1                             ; play the note
	BEQ SkipCtrlL
	JSR LoadControlRegs
SkipCtrlL:
	STA Squ1_EnvelopeDataCtrl                    ; save envelope offset
	JSR Dump_Squ1_Regs

MiscSqu1MusicTasks:
	LDA Square1SoundBuffer                       ; is there a sound playing on square 1?
	BNE HandleTriangleMusic
	LDA EventMusicBuffer                         ; check for death music or d4 set on secondary buffer
	AND #%10010001
	BNE DeathMAltReg
	LDY Squ1_EnvelopeDataCtrl                    ; check saved envelope offset
	BEQ NoDecEnv2
	DEC Squ1_EnvelopeDataCtrl                    ; decrement unless already zero
NoDecEnv2:
	JSR LoadEnvelopeData                         ; do a load of envelope data
	STA SND_SQUARE1_REG                          ; based on offset set by first load
DeathMAltReg:
	LDA AltRegContentFlag                        ; check for alternate control reg data
	BNE DoAltLoad
	LDA #$7f                                     ; load this value if zero, the alternate value
DoAltLoad:
	STA SND_SQUARE1_REG+1                        ; if nonzero, and let's move on

HandleTriangleMusic:
	LDA MusicOffset_Triangle
	DEC Tri_NoteLenCounter                       ; decrement triangle note length
	BNE HandleNoiseMusic                         ; is it time for more data?
	LDY MusicOffset_Triangle                     ; increment square 1 music offset and fetch data
	INC MusicOffset_Triangle
	LDA (MusicData),y
	BEQ LoadTriCtrlReg                           ; if zero, skip all this and move on to noise
	BPL TriNoteHandler                           ; if non-negative, data is note
	JSR ProcessLengthData                        ; otherwise, it is length data
	STA Tri_NoteLenBuffer                        ; save contents of A
	LDA #$1f
	STA SND_TRIANGLE_REG                         ; load some default data for triangle control reg
	LDY MusicOffset_Triangle                     ; fetch another byte
	INC MusicOffset_Triangle
	LDA (MusicData),y
	BEQ LoadTriCtrlReg                           ; check once more for nonzero data

TriNoteHandler:
	JSR SetFreq_Tri
	LDX Tri_NoteLenBuffer                        ; save length in triangle note counter
	STX Tri_NoteLenCounter
	LDA EventMusicBuffer
	AND #%01101110                               ; check for death music or d4 set on secondary buffer
	BNE NotDOrD4                                 ; if playing any other secondary, skip primary buffer check
	LDA AreaMusicBuffer                          ; check primary buffer for water or castle level music
	AND #%00001010
	BEQ HandleNoiseMusic                         ; if playing any other primary, or death or d4, go on to noise routine
NotDOrD4:
	TXA                                          ; if playing water or castle music or any secondary
	CMP #$12                                     ; besides death music or d4 set, check length of note
	BCS LongN
	LDA EventMusicBuffer                         ; check for win castle music again if not playing a long note
	AND #EndOfCastleMusic
	BEQ MediN
	LDA #$0f                                     ; load value $0f if playing the win castle music and playing a short
	BNE LoadTriCtrlReg                           ; note, load value $1f if playing water or castle level music or any
MediN:
	LDA #$1f                                     ; secondary besides death and d4 except win castle or win castle and playing
	BNE LoadTriCtrlReg                           ; a short note, and load value $ff if playing a long note on water, castle
LongN:
	LDA #$ff                                     ; or any secondary (including win castle) except death and d4

LoadTriCtrlReg:

	STA SND_TRIANGLE_REG                         ; save final contents of A into control reg for triangle

HandleNoiseMusic:
	LDA AreaMusicBuffer                          ; check if playing underground or castle music
	AND #%11110011
	BEQ ExitMusicHandler                         ; if so, skip the noise routine
	DEC Noise_BeatLenCounter                     ; decrement noise beat length
	BNE ExitMusicHandler                         ; is it time for more data?

FetchNoiseBeatData:
	LDY MusicOffset_Noise                        ; increment noise beat offset and fetch data
	INC MusicOffset_Noise
	LDA (MusicData),y                            ; get noise beat data, if nonzero, branch to handle
	BNE NoiseBeatHandler
	LDA NoiseDataLoopbackOfs                     ; if data is zero, reload original noise beat offset
	STA MusicOffset_Noise                        ; and loopback next time around
	BNE FetchNoiseBeatData                       ; unconditional branch

NoiseBeatHandler:
	JSR AlternateLengthHandler
	STA Noise_BeatLenCounter                     ; store length in noise beat counter
	TXA
	AND #%00111110                               ; reload data and erase length bits
	BEQ SilentBeat                               ; if no beat data, silence
	CMP #$30                                     ; check the beat data and play the appropriate
	BEQ LongBeat                                 ; noise accordingly
	CMP #$20
	BEQ StrongBeat
	AND #%00010000
	BEQ SilentBeat
	LDA #$1c                                     ; short beat data
	LDX #$03
	LDY #$18
	BNE PlayBeat

StrongBeat:
	LDA #$1c                                     ; strong beat data
	LDX #$0c
	LDY #$18
	BNE PlayBeat

LongBeat:
	LDA #$1c                                     ; long beat data
	LDX #$03
	LDY #$58
	BNE PlayBeat

SilentBeat:
	LDA #$10                                     ; silence

PlayBeat:
	STA SND_NOISE_REG                            ; load beat data into noise regs
	STX SND_NOISE_REG+2
	STY SND_NOISE_REG+3

ExitMusicHandler:
	RTS

AlternateLengthHandler:
	TAX                                          ; save a copy of original byte into X
	ROR                                          ; save LSB from original byte into carry
	TXA                                          ; reload original byte and rotate three times
	ROL                                          ; turning xx00000x into 00000xxx, with the
	ROL                                          ; bit in carry as the MSB here
	ROL

ProcessLengthData:
	AND #%00000111                               ; clear all but the three LSBs
	CLC
	ADC $f0                                      ; add offset loaded from first header byte
	ADC NoteLengthTblAdder                       ; add extra if time running out music
	TAY
	LDA MusicLengthLookupTbl,y                   ; load length
	RTS

LoadControlRegs:
	LDA EventMusicBuffer                         ; check secondary buffer for win castle music
	AND #EndOfCastleMusic
	BEQ NotECstlM
	LDA #$04                                     ; this value is only used for win castle music
	BNE AllMus                                   ; unconditional branch
NotECstlM:
	LDA AreaMusicBuffer
	AND #%01111101                               ; check primary buffer for water music
	BEQ WaterMus
	LDA #$08                                     ; this is the default value for all other music
	BNE AllMus
WaterMus:
	LDA #$28                                     ; this value is used for water music and all other event music
AllMus:
	LDX #$82                                     ; load contents of other sound regs for square 2
	LDY #$7f
	RTS

LoadEnvelopeData:
	LDA EventMusicBuffer                         ; check secondary buffer for win castle music
	AND #EndOfCastleMusic
	BEQ LoadUsualEnvData
	LDA EndOfCastleMusicEnvData,y                ; load data from offset for win castle music
	RTS

LoadUsualEnvData:
	LDA AreaMusicBuffer                          ; check primary buffer for water music
	AND #%01111101
	BEQ LoadWaterEventMusEnvData
	LDA AreaMusicEnvData,y                       ; load default data from offset for all other music
	RTS

LoadWaterEventMusEnvData:
	LDA WaterEventMusEnvData,y                   ; load data from offset for water music and all other event music
	RTS
