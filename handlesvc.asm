; (c) Dominic Beesley 2021
; This is more or less cribbed from the New Advanced User Guide and used as a template
; with {XXXX} being replaced in the perl script

; NOTE: if you make any changes to this code you must update the $DATA_OFFSET constant
; in the perl script - the $DATA_OFFSET should be set to the size of the header and
; service handler with zero-length title, version string and copyright

 
; *************************************
; *                                   *
; *   *ROM filing system ROM example  *
; *                                   *
; *************************************
serROM=&F5
ROMid=&F4
ROMptr=&F6
OSRDRM=&FFB9

			ORG &8000


.ROMstart 		EQUB 0			\ null language entry
			EQUB 0
 			EQUB 0
 			JMP service 		\ service entry point
			EQUB &82		\ ROM type, service ROM
			EQUB copyr-ROMstart	\ offset to copyright$
		        EQUB {version}		\ binary version number
			EQUS {rom_title}    	\ ROM title string
			EQUB 0
			EQUS {version_str}      \ ROM version string
.copyr			EQUB 0
			EQUS {copyright}	\ copyright$
			EQUB 0			\ end of paged ROM header
.service		CMP #&D			\ service routine
			BEQ initsp		\ initialise call?
			CMP #&E
			BEQ rdbyte		\ read byte call?
			RTS			\ not my call
	\ Routine for paged ROM service call &D
.initsp			PHA			\ save accumulator
			JSR invsno		\ invert *ROM number
			CMP ROMid		\ compare with ROM id
			BCC exit		\ if *ROM > me, not my call
			LDA #data AND 255    	\ low byte of data address
			STA ROMptr		\ store in pointer location
			LDA #data DIV &100	\ high byte of data address
			STA ROMptr+1		\ store in pointer location
			LDA ROMid		\ get my paged ROM number
			JSR invert		\ invert it
			STA serROM		\ make me current *ROM
.claim			PLA			\ restore accumulator/stack
			LDA #0			\ service call claimed
			RTS			\ finished
.exit			PLA			\ call not claimed restore
			RTS			\    accumulator and return
	\ Routine for paged ROM service call &E
.rdbyte			PHA			\ save accumulator
			TYA			\ copy Y to A
			BMI os120		\ if Y -ve OS has OSRDRM
	\ this part for OS with no OSRDRM
			JSR invsno		\ invert *ROM number
			CMP ROMid		\ is it my paged ROM no.
			BNE exit		\ if not do not claim call
			LDY #0			\ Y=0
			LDA (ROMptr),Y		\ load A with byte
			TAY			\ copy A to Y
.claim1			INC ROMptr		\ increment ptr low byte
			BNE claim		\ no overflow
			INC ROMptr+1		\ increment ptr high byte
			JMP claim		\ claim call and return
	\ this part for OS with OSRDRM
.os120			JSR invsno		\ A=current *ROM number
						\ not necessarily me
			TAY			\ copy A to Y
			JSR OSRDRM		\ OS will select ROM
			TAY			\ byte returned in A
			JMP claim1		\ incremnt ptr & claim call
	\ Subroutine for inverting *ROM numbers
.invsno			LDA serROM		\ A=*ROM number
.invert   		EOR #&FF		\ invert bits
			AND #&F			\ mask out unwanted bits
          		RTS			\ finished

.data
{data}

.ROMend


		SAVE "", ROMstart, ROMend
