''
'' VGA display 128xH (quad cog) - video driver and pixel generator (LHS)
''
''        Author: Marko Lukat
'' Last modified: 2016/08/19
''       Version: 0.4
''
'' long[par][0]:  screen:      [!Z]:addr =   16:16 -> zero (accepted)
'' long[par][1]:    font: size:[!Z]:addr =  8:8:16 -> zero (accepted)
'' long[par][2]: colours:  c/a:[!Z]:addr = 1:15:16 -> zero (accepted), optional colour [buffer]
'' long[par][3]: frame indicator/sync lock
''
'' colour [buffer] format
''
''  - (%0--//--0) address (full colour, word array)
''  - (%1--//---) colour value (waitvid 2 colour VGA format)
'' 
'' acknowledgements
'' - loader code based on work done by Phil Pilgrim (PhiPi) and Ray Rodrick (Cluso99)
''
'' 20120402: documented emitter sequence
'' 20160819: added 8x16 support
''
OBJ
  system: "core.con.system"
  
PUB null
'' This is not a top level object.

PUB init(ID, mailbox) : cog
                                      
  cog := system.launch( ID, @reader, mailbox) & 7
  cog := system.launch(cog, @reader, mailbox|$8000)

DAT             org     0                       ' cog binary header

header_2048     long    system#ID_2             ' magic number for a cog binary
                word    header_size             ' header size
                word    %00000000_00000000      ' flags
                word    0, 0                    ' start register, register count

header_size     fit     16
                
DAT             org     0                       ' video driver and pixel generator

reader          jmpret  $, #setup               ' once

                mov     dira, mask              ' drive outputs

' horizontal timing 1024(1024) 3(24) 17(136) 20(160)
'   vertical timing  768(768)  3(3)   6(6)   29(29)

:vsync          mov     do_v, #pointer          ' reset task chain (vsync)
        
                mov     ecnt, #3
                call    #blank                  ' front porch
                djnz    ecnt, #$-1

                xor     sync, #$0101            ' active

                mov     ecnt, #6
                call    #blank                  ' vertical sync
                djnz    ecnt, #$-1

                xor     sync, #$0101            ' inactive

                mov     ecnt, #29 -4
                call    #blank                  ' back porch
                djnz    ecnt, #$-1

        if_nc   mov     ecnt, #4                ' |
        if_nc   call    #blank                  ' |
        if_nc   djnz    ecnt, #$-1              ' remaining 4 back porch lines

' Vertical sync chain done, do visible area.

                mov     zwei, scrn              ' screen base address
                add     zwei, #64               ' LHS adjustment
                mov     drei, plte              ' colour [buffer]
'{n/a}          add     drei, #(128 - 66) * 2   ' RHS adjustment
                
                mov     lcnt, #96
                mov     slot, #0                ' secondary: 0 2 1 ...
        if_nc   mov     slot, #1                '   primary:  1 0 2 ...

:line           mov     vscl, lots              ' |
                waitvid zero, #0                ' 206 hub windows for pixel data
                
                mov     eins, slot              ' |
                shl     eins, #10               ' 1K per font section
                add     eins, font              ' font base + slot offset

                call    #load_pixels

                shr     eins, #24               ' get font size (size:[!Z]:addr = 8:8:16)
'{n/a}          cmp     eins, #8 wz             ' small size: 0->2: 2(update)->(4)->0
'{n/a}  if_e    add     slot, #2                '             1->3: 3(update)->(5)->1

       {if_ne}  cmp     eins, #16 wz            ' exclude 8x16
        if_ne   cmp     slot, #0 wz             ' 8x12:    0: 0(update)->(2)->2
        if_ne   add     slot, #1                ' 8x12: 1->2: 2(update)->(4)->0
                                                ' 8x12: 2->3: 3(update)->(5)->1
                mov     vscl, lots              ' |
                waitvid zero, #0                ' 206 hub windows for colour data

                call    #load_colour

' slot advancement

                add     slot, #2                ' next slot
                testn   slot, #3 wz             ' check for line transition(s)
        if_nz   sub     zwei, #128              ' anything but 0->2/1->3 is a line transition
        if_nz   and     slot, #3                ' 2->(4)->0, 3->(5)->1
        if_nz   add     drei, #256              ' advance colour buffer (moved from load_colour)
                
' We collected 4 lines worth of data, now send them out.

' LHS: 64*8 active, 64*8 null,   hsync
' RHS: 62*8 null,   66*8 active, null
'
' braking sequence (1 pixel/frame clock to something manageable)
'
'               waitvid pal+$??, pix+$??        ' chars ??..??
'
'               waitpne $, #%00000000           ' start second half/hsync
'               mov     vscl, #N - 8            ' remainder of line/hsync
'               cmp     zero, #0                ' |
'               cmp     zero, #0                ' idle for remainder of line
'
'      waitvid             waitpne              mov             cmp             cmp
'   W           R |         L             |             R |         L     |         L     |
' 
'                                                                           
'   last tracked WHOP       latch zero     └┤           update      latch zero    ├┘latch zero
'                           colour          WHOP        vscl        colour     WHOP colour

                mov     vier, #4
'-----------------------------------------------
:emit           mov     vscl, fast              ' speed up (one pixel per frame clock)

                waitvid pal+$00, pix+$00
                waitvid pal+$01, pix+$01
                waitvid pal+$02, pix+$02
                waitvid pal+$03, pix+$03
                waitvid pal+$04, pix+$04
                waitvid pal+$05, pix+$05
                waitvid pal+$06, pix+$06
                waitvid pal+$07, pix+$07
                waitvid pal+$08, pix+$08
                waitvid pal+$09, pix+$09
                waitvid pal+$0A, pix+$0A
                waitvid pal+$0B, pix+$0B
                waitvid pal+$0C, pix+$0C
                waitvid pal+$0D, pix+$0D
                waitvid pal+$0E, pix+$0E
                waitvid pal+$0F, pix+$0F        ' chars 0..15

                waitvid pal+$10, pix+$10
                waitvid pal+$11, pix+$11
                waitvid pal+$12, pix+$12
                waitvid pal+$13, pix+$13
                waitvid pal+$14, pix+$14
                waitvid pal+$15, pix+$15
                waitvid pal+$16, pix+$16
                waitvid pal+$17, pix+$17
                waitvid pal+$18, pix+$18
                waitvid pal+$19, pix+$19
                waitvid pal+$1A, pix+$1A
                waitvid pal+$1B, pix+$1B
                waitvid pal+$1C, pix+$1C
                waitvid pal+$1D, pix+$1D
                waitvid pal+$1E, pix+$1E
                waitvid pal+$1F, pix+$1F        ' chars 16..23

                waitvid pal+$20, pix+$20
                waitvid pal+$21, pix+$21
                waitvid pal+$22, pix+$22
                waitvid pal+$23, pix+$23
                waitvid pal+$24, pix+$24
                waitvid pal+$25, pix+$25
                waitvid pal+$26, pix+$26
                waitvid pal+$27, pix+$27
                waitvid pal+$28, pix+$28
                waitvid pal+$29, pix+$29
                waitvid pal+$2A, pix+$2A
                waitvid pal+$2B, pix+$2B
                waitvid pal+$2C, pix+$2C
                waitvid pal+$2D, pix+$2D
                waitvid pal+$2E, pix+$2E
                waitvid pal+$2F, pix+$2F        ' chars 24..47

                waitvid pal+$30, pix+$30
                waitvid pal+$31, pix+$31
                waitvid pal+$32, pix+$32
                waitvid pal+$33, pix+$33
                waitvid pal+$34, pix+$34
                waitvid pal+$35, pix+$35
                waitvid pal+$36, pix+$36
                waitvid pal+$37, pix+$37
                waitvid pal+$38, pix+$38
                waitvid pal+$39, pix+$39
                waitvid pal+$3A, pix+$3A
                waitvid pal+$3B, pix+$3B
                waitvid pal+$3C, pix+$3C
                waitvid pal+$3D, pix+$3D
                waitvid pal+$3E, pix+$3E
                waitvid pal+$3F, pix+$3F        ' chars 48..63

                waitpne $, #%00000000           ' start second half
                mov     vscl, #512 - 8          ' remainder of line
                cmp     zero, #0                ' |
                cmp     zero, #0                ' idle for remainder of line

                shr     pix+$00, #8
                shr     pix+$01, #8
                shr     pix+$02, #8
                shr     pix+$03, #8
                shr     pix+$04, #8
                shr     pix+$05, #8
                shr     pix+$06, #8
                shr     pix+$07, #8
                shr     pix+$08, #8
                shr     pix+$09, #8
                shr     pix+$0A, #8
                shr     pix+$0B, #8
                shr     pix+$0C, #8
                shr     pix+$0D, #8
                shr     pix+$0E, #8
                shr     pix+$0F, #8             ' chars 0..15

                shr     pix+$10, #8
                shr     pix+$11, #8
                shr     pix+$12, #8
                shr     pix+$13, #8
                shr     pix+$14, #8
                shr     pix+$15, #8
                shr     pix+$16, #8
                shr     pix+$17, #8
                shr     pix+$18, #8
                shr     pix+$19, #8
                shr     pix+$1A, #8
                shr     pix+$1B, #8
                shr     pix+$1C, #8
                shr     pix+$1D, #8
                shr     pix+$1E, #8
                shr     pix+$1F, #8             ' chars 16..23

                shr     pix+$20, #8
                shr     pix+$21, #8
                shr     pix+$22, #8
                shr     pix+$23, #8
                shr     pix+$24, #8
                shr     pix+$25, #8
                shr     pix+$26, #8
                shr     pix+$27, #8
                shr     pix+$28, #8
                shr     pix+$29, #8
                shr     pix+$2A, #8
                shr     pix+$2B, #8
                shr     pix+$2C, #8
                shr     pix+$2D, #8
                shr     pix+$2E, #8
                shr     pix+$2F, #8             ' chars 24..47

                shr     pix+$30, #8
                shr     pix+$31, #8
                shr     pix+$32, #8
                shr     pix+$33, #8
                shr     pix+$34, #8
                shr     pix+$35, #8
                shr     pix+$36, #8
                shr     pix+$37, #8
                shr     pix+$38, #8
                shr     pix+$39, #8
                shr     pix+$3A, #8
                shr     pix+$3B, #8
                shr     pix+$3C, #8
                shr     pix+$3D, #8
                shr     pix+$3E, #8
                shr     pix+$3F, #8             ' chars 48..63

                mov     vscl, slow              ' horizontal sync
                waitvid sync, slow_pixels
'-----------------------------------------------
                djnz    vier, #:emit
                djnz    lcnt, #:line
                
        if_c    mov     ecnt, #4                ' secondary finishes early so
        if_c    call    #blank                  ' let him do some blank lines
        if_c    djnz    ecnt, #$-1              ' before restarting

                jmp     #:vsync


blank           mov     vscl, line              ' (in)visible line
                waitvid sync, #%0000
                
' This is where we can update screen buffer, font definition and palette.
' With the setup used we have about 78 hub windows available per line.

                jmpret  do_v, do_v

                mov     vscl, slow              ' horizontal sync
                waitvid sync, slow_pixels
                
blank_ret       ret


load_pixels     movd    :one, #pix+0            ' |
                movd    :two, #pix+1            ' restore initial settings
                
                mov     frqb, zwei              ' current screen base
                shr     frqb, #1{/2}            ' frqb is added twice     
                mov     phsb, #64 -1            ' byte count -1
                
:loop           rdbyte  temp, phsb              ' get character
                shl     temp, #2                ' long index
                add     temp, eins              ' add current font base
:one            rdlong  0-0, temp               ' read 4 scan lines of character
                add     $-1, dst2               ' advance destination
                sub     phsb, #1 wz

                rdbyte  temp, phsb              ' get character
                shl     temp, #2                ' long index
                add     temp, eins              ' add current font base
:two            rdlong  0-0, temp               ' read 4 scan lines of character
                add     $-1, dst2               ' advance destination
        if_nz   djnz    phsb, #:loop

load_pixels_ret ret


load_colour     shr     plte, #31 wz,nr         ' monochrome or colour buffer
        if_nz   jmp     load_colour_ret         ' early return

                movd    :one, #pal+63           ' |
                movd    :two, #pal+62           ' restore initial settings
                
                mov     frqb, drei              ' current colour buffer base
                shr     frqb, #1{/2}            ' frqb is added twice
                mov     phsb, #64 * 2 -1        ' byte count -1

:loop           rdword  temp, phsb              ' get colour
                and     temp, mask_import       ' |
                or      temp, idle              ' clean-up
:one            mov     0-0, temp
                sub     $-1, dst2               ' advance destination
                sub     phsb, #3 wz

                rdword  temp, phsb              ' get colour
                and     temp, mask_import       ' |
                or      temp, idle              ' clean-up
:two            mov     0-0, temp
                sub     $-1, dst2               ' advance destination
        if_nz   djnz    phsb, #:loop

load_colour_ret ret

' Stuff to do during vertical blank.

pointer         neg     vref, cnt               ' waitvid reference
                wrlong  vref, fcnt_             ' announce vertical blank
                add     vref, cnt               ' add hub window reference

                shr     vref, #1                ' PL: -
                min     vref, miss              ' SL: 6
                cmp     vref, miss wz

                mov     cnt, #5{18} + 6         ' |
        if_e    add     cnt, #16                ' |
                add     cnt, cnt                ' |
                waitcnt cnt, #0                 ' bring primary/secondary back in line


                rdlong  temp, scrn_ wz          ' |
        if_nz   mov     scrn, temp              ' |
        if_nz   wrlong  zero, scrn_             ' update and acknowledge screen buffer setup
        
                rdlong  temp, font_ wz          ' |
        if_nz   mov     font, temp              ' |
        if_nz   wrlong  zero, font_             ' update and acknowledge font definition setup

                rdlong  temp, plte_ wz          ' |
        if_nz   mov     plte, temp              ' |
        if_nz   wrlong  zero, plte_             ' update and acknowledge colour buffer setup

        if_nz   shr     plte, #31 wz,nr         ' |
        if_nz   call    #palette                ' optionally update palette

{split}         jmpret  do_v, do_v nr           ' End Of Chain (no more tasks for this frame)


palette         and     plte, mask_import       ' |
                or      plte, idle              ' insert idle sync bits

                movd    :one, #pal+0            ' |
                movd    :two, #pal+1            ' restore initial settings

                mov     temp, #64/2             ' can't use ecnt here
                
:one            mov     0-0, plte               ' |
                add     $-1, dst2               ' |
:two            mov     0-0, plte               ' |
                add     $-1, dst2               ' |
                djnz    temp, #$-4              ' initialise (line) palette

palette_ret     ret

' initialised data and/or presets
                
idle            long    hv_idle
sync            long    hv_idle ^ $0200

slow_pixels     long    $000FFFF8               ' 3/17/20 (LSB first)
slow            long    8 << 12 | 320           '   8/320
fast            long    1 << 12 | 8             '   1/8
line            long    0 << 12 | 1024          ' 256/1024
lots            long    0 << 12 | 2688          ' 256/2688 (206 hub windows)

mask_import     long    hv_mask                 ' stay clear of sync bits
mask            long    vpin << (vgrp * 8)      ' pin I/O setup

dst1            long    1 << 9                  ' dst +/-= 1
dst2            long    2 << 9                  ' dst +/-= 2

scrn_           long    +0              -12     ' |
font_           long    +4              -12     ' |
plte_           long    +8              -12     ' |
fcnt_           long    12              -12     ' mailbox addresses (local copy)

plte            long    dcolour | NEGX          ' colour [buffer]

hram            long    $00007FFF               ' hub RAM mask  
addr            long    $FFFF8000       +12
miss            long    5

setup           add     addr, par wc            ' carry set -> secondary
                and     addr, hram              ' confine to hub RAM

                add     scrn_, addr             ' @long[par][0]
                add     font_, addr             ' @long[par][1]
                add     plte_, addr             ' @long[par][2]
                add     fcnt_, addr             ' @long[par][3]

                addx    miss, #0                ' required for hub sync

                rdlong  addr, addr              ' release lock location
                addx    addr, #%00              ' add secondary offset
                wrbyte  hram, addr              ' up and running

                rdlong  temp, addr wz           ' |
        if_nz   jmp     #$-1                    ' synchronized start

'   primary(L/R): cnt + 0/4       
' secondary(L/R): cnt + 2/6

                rdlong  scrn, scrn_             ' get screen address (2n)
                rdlong  font, font_             ' get font address   (2n)

                wrlong  zero, scrn_             ' acknowledge screen buffer setup
                wrlong  zero, font_             ' acknowledge font definition setup

                cmp     scrn, #0 wz             ' if either one is null during
        if_nz   cmp     font, #0 wz             ' initialisation set default colour
        if_z    shl     plte, #(>| ((NEGX | dcolour) >< 32) -1) ' to black-on-black

' Upset video h/w ... using the freezer approach.

                rdlong  vref, #0                ' clkfreq
                shr     vref, #10               ' ~1ms
        if_nc   waitpne $, #0                   ' adjust primary
                nop                             ' adjust LHS

'   primary(L): cnt + 0 + 6 + 4 (+10)
' secondary(L): cnt + 2 + 4 + 4 (+10)

'   primary(R): cnt + 4 + 6     (+10)
' secondary(R): cnt + 6 + 4     (+10)

                add     vref, cnt

                movi    ctrb, #%0_11111_000     ' LOGIC always (loader support)
                movi    ctra, #%0_00001_110     ' PLL, VCO / 2
                movi    frqa, #%0001_1010_0     ' 8.125MHz * 16 / 2 = 65MHz

                mov     vscl, #1                ' reload as fast as possible
                
                movd    vcfg, #vgrp             ' pin group
                movs    vcfg, #vpin             ' pins
                movi    vcfg, #%0_01_0_00_000   ' VGA, 2 colour mode

                waitcnt vref, #0                ' PLL settled
                                                ' frame counter flushed
                ror     vcfg, #1                ' freeze video h/w
                mov     vscl, slow              ' transfer user value
                rol     vcfg, #1                ' unfreeze
'{n/a}          nop                             ' get some distance
'{n/a}          waitvid zero, #0                ' latch user value

' Setup complete, do the heavy lifting upstairs ...

' This is the first time we call palette() so its ret insn is a jmp #0. We can't
' come back here (res overlay) so we simply jump.

                jmp     #palette                ' initialise default (line) palette

                fit

                org     setup
                
' uninitialised data and/or temporaries

ecnt            res     1                       ' element/character count
lcnt            res     1                       ' line count
slot            res     1                       ' character line part [0..2]
vref            res     1                       ' waitvid reference

do_v            res     1                       ' task index (vertical)

scrn            res     1                       ' screen buffer
font            res     1                       ' font definition
                
pal             res     64                      ' palette buffer
pix             res     64                      ' pattern buffer

temp            res     1
eins            res     1
zwei            res     1
drei            res     1
vier            res     1

tail            fit

CON             
  zero    = $1F0                                ' par (dst only)
  vpin    = $0FF                                ' pin group mask
  vgrp    = 2                                   ' pin group
  hv_idle = $01010101 * %11 {%hv}               ' h/v sync inactive
  hv_mask = $FCFCFCFC                           ' colour mask
  dcolour = %%0220_0010 & hv_mask | hv_idle     ' default colour

  res_x   = 1024                                ' |
  res_y   = 768                                 ' |
  res_m   = 4                                   ' UI support
  
DAT