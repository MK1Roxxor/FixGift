; Fix for the lame "freezes during startup" bug in Gift by Potion
; stingray, 23-sep-2015
;
; This version done on 30-Mar-2020, uses Execute() to load the intro and
; patches Draw() in graphics.library, binary of the intro stays unmodified!
; LoadSeg version didn't work correctly.
;
; 31.03.2020: OS check added (doesn't silently quit anymore), some
; error texts adapted, description how the code works added
;
; This code simply fixes the bug in "Gift" by Potion which freezes
; the machine. Reason for this is that regster A1 is not preserved
; in the intro when calling Draw() (graphics libary routine) which in turn
; leads to a trashed RastPort pointer. To fix this, Draw() will be patched
; to not modify register A1, then the intro will be executed and upon exit
; the Draw() patch will be removed. 

ERR_NONE	= 0
ERR_READARGS	= 1			; ReadArgs() failed
ERR_FILE	= 2			; error loading intro
ERR_NOMEM	= 3			; no memory for Draw() patch
ERR_NOGFX	= 4			; error opening graphics library
ERR_WRONGKICK	= 5			; wrong OS version (V39+ required)



START	bra.b	.Go
	dc.b	"$VER: Gift fix 1.0 (31.03.2020) by StingRay/[S]carab^Scoopex",10,0
	CNOP	0,2

.Go	lea	VARS(pc),a5

	move.l	$4.w,a6
	lea	DOSName(pc),a1
	moveq	#0,d0
	jsr	-552(a6)		; OpenLibrary()
	move.l	d0,DOSBase(a5)
	beq.w	.error
	move.l	d0,a6

	; check if OS is at least 3.0 (V39)
	moveq	#ERR_WRONGKICK,d7
	move.l	$4.w,a0
	cmp.w	#39,$14(a0)
	blt.w	.exit


	moveq	#ERR_READARGS,d7
	pea	TEMPLATE(pc)
	move.l	(a7)+,d1		; template
	pea	FileName(a5)
	move.l	(a7)+,d2		; array
	moveq	#0,d3			; rdargs
	jsr	-798(a6)		; ReadArgs()
	move.l	d0,Args(a5)
	beq.w	.exit

	; try Open() to check if file exists
	moveq	#ERR_FILE,d7
	move.l	FileName(a5),d1
	move.l	#1005,d2		; MODE_OLDFILE
	jsr	-30(a6)			; Open()
	move.l	d0,d1
	beq.w	.exit
	jsr	-36(a6)			; Close()	

	; open graphics library for patching Draw()
	moveq	#ERR_NOGFX,d7
	move.l	$4.w,a6
	moveq	#0,d0
	lea	GfxName(pc),a1
	jsr	-552(a6)		; OpenLibrary()
	tst.l	d0
	beq.w	.exit
	move.l	d0,a4
	

	; allocate memory for patch code
	moveq	#ERR_NOMEM,d7
	moveq	#PatchSize,d0
	moveq	#0,d1
	jsr	-684(a6)		; AllocVec()
	move.l	d0,PatchMem(a5)
	beq.b	.exit


	move.l	d0,a1
	move.l	d0,a2

	lea	NewDraw(pc),a0
	moveq	#PatchSize/2-1,d0
.copy	move.w	(a0)+,(a1)+
	dbf	d0,.copy


	moveq	#ERR_NONE,d7

	; patch Draw()
	move.l	a2,d0			; new Draw()
	bsr.b	.PatchDraw	
	move.l	d0,OldDraw-NewDraw(a2)

	; run intro
	move.l	DOSBase(a5),a6
	move.l	FileName(a5),d1
	moveq	#0,d2
	moveq	#0,d3
	jsr	-222(a6)		; Execute()


	; restore old Draw()
	move.l	PatchMem(a5),a0
	move.l	OldDraw-NewDraw(a0),d0	; original Draw()
	bsr.b	.PatchDraw

.exit


	; deallocate memory used for the patch
	move.l	PatchMem(a5),a1
	jsr	-690(a6)		; FreeVec()

	; close graphics library
	move.l	a4,d0
	beq.b	.noGfx
	move.l	d0,a1
	jsr	-414(a6)		; CloseLibrary()
.noGfx	

	; free args
	move.l	DOSBase(a5),a6
	move.l	Args(a5),d1
	jsr	-858(a6)		; FreeArgs()

	; write error text if needed
	move.l	d7,d0
	bsr.b	WriteStatus

	; and finally close dos library
	move.l	DOSBase(a5),a1
	move.l	$4.w,a6
	jsr	-414(a6)		; CloseLibrary()
	

	moveq	#0,d0
	rts
	
.error	moveq	#20,d0
	rts

; d0.l: pointer to patch routine to install
.PatchDraw
	move.l	$4.w,a6
	jsr	-132(a6)		; Forbid()
	lea	-246.w,a0		; Draw()
	move.l	a4,a1			; GfxBase
	jsr	-420(a6)		; SetFunction()
	jmp	-138(a6)		; Permit


;----------------------------------------------------------------------------
; Routine uses standard output to write the error/status text. dos.library
; must be opened and the pointer to it stored in DOSBase.
; The error text must be null-terminated. All registers are preserved.


; d0.w: error/status code
; a6.l: DOSBase

WriteStatus
	movem.l	d0-a6,-(a7)
	move.w	d0,d4

	move.l	DOSBase(a5),a6
	jsr	-60(a6)			; Output
	move.l	d0,d5			; save output handle
	beq.b	.noWrite

	lea	.TAB(pc),a2
.loop	movem.w	(a2)+,d0/d1		; error code/text offset
	cmp.w	d4,d0
	beq.b	.found
	tst.w	(a2)
	bpl.b	.loop
	moveq	#.TXT_UNDEFERROR-.TAB,d1


.found	lea	.TAB(pc,d1.w),a0	; ptr to error text	
	move.l	a0,d2
	moveq	#-1,d3
.getlen	addq.l	#1,d3
	tst.b	(a0)+
	bne.b	.getlen

	move.l	d5,d1
	jsr	-48(a6)			; Write()

.noWrite
	movem.l	(a7)+,d0-a6
	rts


; format of the table:
; dc.w error code, offset to text

.TAB	dc.w	ERR_NONE,0
	dc.w	ERR_READARGS,.TXT_ARGSERROR-.TAB
	dc.w	ERR_FILE,.TXT_FILEERROR-.TAB
	dc.w	ERR_NOGFX,.TXT_GFXERROR-.TAB
	dc.w	ERR_WRONGKICK,.TXT_WRONGKICK-.TAB
	dc.w	-1			; end of table

.TXT_UNDEFERROR	dc.b	"Undefined error!",10,0
.TXT_FILEERROR	dc.b	"Error: file could not be loaded!",10,0
.TXT_ARGSERROR	dc.b	"FixGift 1.0 by StingRay/Scarab",10,10
		;dc.b	"Required argument missing!",10,0
		dc.b	"Usage: FixGift Introfile",10,0
.TXT_GFXERROR	dc.b	"Error: graphics.library could not be opened!",10,0
.TXT_WRONGKICK	dc.b	"Error: Kickstart 3.0+ (V39+) required!",10,0
		CNOP	0,2


NewDraw
	move.l	a1,-(a7)
	bsr.b	.Draw
	move.l	(a7)+,a1
	rts

.Draw	move.l	OldDraw(pc),-(a7)
	rts

OldDraw	dc.l	0

PatchSize	= *-NewDraw



VARS		RSRESET
DOSBase		rs.l	1
PatchMem	rs.l	1
FileName	rs.l	1
Args		rs.l	1
.size		rs.b	0
		ds.b	.size



DOSName		dc.b	"dos.library",0
GfxName		dc.b	"graphics.library",0
TEMPLATE	dc.b	"INTROFILE/A",0
