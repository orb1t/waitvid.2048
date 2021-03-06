''
'' VGA display 50xH (single cog) - video driver and pixel generator
''
''        Author: Marko Lukat
'' Last modified: 2013/01/02
''       Version: 0.8.half.2
''
'' long[par][0]:  screen:       [!Z]:addr =     16:16 -> zero (accepted), required during startup
'' long[par][1]:    font:  size:[!Z]:addr =    8:8:16 -> zero (accepted), required during startup
'' long[par][2]: palette: c/a:Z:[!Z]:addr = 1:1:14:16 -> zero (accepted), optional colour [buffer]
'' long[par][3]: frame indicator
''
'' The colour buffer is either an address (%00-//-00) or a colour value (%10-//---).
''
'' acknowledgements
'' - loader and emitter code based on work done by Phil Pilgrim (PhiPi) and Ray Rodrick (Cluso99)
''
'' 20120506: cleaned up hsync code (now in sync with 100xH and 128xH)
'' 20130101: now capable of using 64/256 colours (RRGGBBHV / RRGGBBgr + xxxxxxHV)
''           -  64c: $FC/2/2 (vpin/vgrp/sgrp)
''           - 256c: $FF/2/3
''           patched for half range font (128 characters)
'' 20130102: customized mode change by (mis)using bit 0 of the startup screen address
''           - 0: $FC/2/2
''           - 1: $FF/2/3
''
OBJ
  system: "core.con.system"
  
PUB null
'' This is not a top level object.

PUB init(ID, mailbox)

  return system.launch(ID, @reader, mailbox)
  
DAT             org     0                       ' cog binary header

header_2048     long    system#ID_2             ' magic number for a cog binary
                word    header_size             ' header size
                word    %00000000_00000000      ' flags
                word    0, 0                    ' start register, register count

header_size     fit     16
                
DAT             org     0                       ' video driver and pixel generator

reader          neg     href, cnt               ' hub window reference (-4)
                
                movi    ctra, #%0_00001_101     ' PLL, VCO/4
                movi    frqa, #%0001_00000      ' 5MHz * 16 / 4 = 20MHz

' So far we didn't introduce funny timing, i.e. we are still at 4n relative to our
' hub window. The NCO we just started will have its rising edge at 4n+3 which is
' what the PLL uses as reference.
'
'                movi frqa
'            | S   D   e   R |               |               |               |               |
' clock  
'  phsa                    0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F   0
'   NCO  
'   PLL  
'
' The WHOPs happen with the falling edge of the PLL clock which places them at 4n+3
' as well (again, relative to the hub window). Which basically leaves us with four
' possible slots. For this driver we want to place the WHOP at 16h+11 (h as in hub).

                mov     vscl, hvis              ' 1/8
                mov     vcfg, vcfg_sync         ' VGA, 2 colour mode

                rdlong  cnt, #0
                shr     cnt, #10                ' ~1ms
                add     cnt, cnt               
                waitcnt cnt, #0                 ' PLL needs to settle

' The first issued waitvid is a bit of a gamble if we don't know where the WHOP
' is located. We could do some fancy math or simply issue a dummy waitvid.

                waitvid zero, #0                ' dummy (first one is unpredictable)
                waitvid zero, #0                ' point of reference

' We took a cnt reference at -4 cycles relative to hub sync (href). The requirement
' now is for the following code sequence to result in href == 19 (8+7+4) cycles.
'
'               neg     href, cnt ------------> neg     href, cnt       |
'               cogid   $ nr            8       add     href, cnt       4
'               waitvid zero, #0        7                 |
'               add     href, cnt ------------>-----------+
'
'               neg                    cogid                        waitvid                 add
'        | S   D   e   R | S   D   e   .   .   .   .   R | S   D   e   .   .   .   R | S   D   e
' clock  
'   cnt       +0                                                       |                  +19
'                                                                      WHOP
'
' As we are only interested in 16h timing we only consider the lower nibble of the
' cnt difference which gives us the following 4 deltas:
'
'       %1011   - 2 frame clocks early, adjust by +2
'       %1111   - 1 frame clock  early, adjust by +1
'       %0011   - sync, no adjustment
'       %0111   - 1 frame clock late, adjust by -1 or +3
'
' First we get rid of the lower 2 bits. Then we realise that in order to get from 
' the remaining 2 bits to the required offset we have to apply a NEG operation.
'
'       %--10   ->      %--10
'       %--11   ->      %--01
'       %--00   ->      %--00
'       %--01   ->      %--11
'
' This gets cleaned up and applied to our current vscl frame clock value as a one off
' adjustment.

                add     href, cnt               ' get current sync slot
                shr     href, #2                ' 4 system clocks per pixel
                neg     href, href              ' |
                and     href, #%11              ' calculate adjustment

                add     vscl, href              ' |
                waitvid zero, #0                ' stretch frame
                sub     vscl, href              ' |
                waitvid zero, #0                ' restore frame

' At this point all WHOPs are aligned to 16h+11. In fact they are aligned to 32h+11
' due to the frame counter covering 2 hub windows.

                movi    ctrb, #%0_11111_000     ' LOGIC always
                call    #palette                ' initialise default (line) palette

                add     fcnt_, par              ' @long[par][3]
                add     scrn_, par              ' @long[par][0]
                rdlong  scrn, scrn_ wz          ' |
        if_z    jmp     #$-1                    ' get non-zero screen address

                test    scrn, #1 wz

        if_z    mov     mask, #$FC|%11          '  64c
        if_z    shl     mask, #2 * 8
        if_z    movs    vcfg_norm, #$FC
        if_z    movd    vcfg_norm, #2
        if_z    movd    vcfg_sync, #2

        if_nz   mov     mask, #$1FF             ' 256c
        if_nz   movd    mask, #1
        if_nz   shl     mask, #2 * 8
        if_nz   movs    vcfg_norm, #$FF
        if_nz   movd    vcfg_norm, #2
        if_nz   movd    vcfg_sync, #3
        
                add     font_, par              ' @long[par][1]
                rdlong  font, font_ wz          ' |
        if_z    jmp     #$-1                    ' get non-zero font address

                add     plte_, par              ' @long[par][2]
                wrlong  zero, scrn_             ' acknowledge screen buffer setup
                mov     scan, font              ' |
                shr     scan, #24               ' extract font height
                wrlong  zero, font_             ' acknowledge font definition setup

' Setup complete, enter display loop.

                mov     dira, mask              ' drive outputs

' At this point the WHOP either happened during the last cycle of the mov insn (16h+11)
' or will happen during the next hub window (4th cycle of waitvid in blank).

' horizontal timing 400(800) 5(40) 16(128) 11(88)
'   vertical timing 300(600) 1(1)   4(4)   23(23)

vsync           mov     do_v, #pointer          ' reset task chain (vsync)

'               mov     ecnt, #1
                call    #blank                  ' front porch
'               djnz    ecnt, #$-1

                xor     sync, #$0101            ' active

                mov     ecnt, #4
                call    #blank                  ' vertical sync
                djnz    ecnt, #$-1
                
                xor     sync, #$0101            ' inactive

                mov     ecnt, #23 -3
                call    #blank                  ' back porch
                djnz    ecnt, #$-1

                mov     vier, plte              ' rewind
                
                call    #blank                  ' |
                call    #blank                  ' |
                call    #blank                  ' last 3 back porch lines

' Vertical sync chain done, do visible area.

                mov     frqb, scrn              ' screen base address
                shr     frqb, #1{/2}
                mov     drei, #res_y            ' max visible scan lines

:line           mov     eins, font              ' font base address
                mov     zwei, scan              ' font size
                max     zwei, drei              ' limit against what's left
                sub     drei, zwei              ' update what's left

:scan           call    #emit                   ' |
                call    #hsync                  ' 1st scan line

                cmp     zwei, #2 wz
        if_e    andn    vier, hide              ' enable colour fetch

                call    #emit                   ' |
                call    #hsync                  ' 2nd scan line

                add     eins, #128              ' next row in character definition(s)
                djnz    zwei, #:scan            ' repeat for font size

                sub     frqb, #50 / 2           ' next row
                tjnz    drei, #:line            ' repeat for all rows

                jmp     #vsync                  ' next frame


blank           mov     vscl, #400 wc           ' 256/400
                waitvid sync, #%00              ' latch blank line

' This is where we can update screen buffer, font definition and palette.
' With the setup used we have about 100 hub windows available per line.

                jmpret  do_v, do_v

hsync           mov     vscl, slow              ' horizontal sync
                waitvid sync, slow_pixels

                mov     cnt, cnt                ' record sync point                     (%%)
                add     cnt, #9{14} + 112 + 332 '                                       (%%)

                mov     vcfg, vcfg_sync         ' switch back to sync mode              (##)
                
                shr     vier, #30 wz,nr         ' check mode
        if_z    jmpret  do_h, do_h              ' fetch (0/1) and copy colours
hsync_ret
blank_ret       ret


emit            waitcnt cnt, #0                 ' (coarse) re-sync after back porch     (%%)

                movd    :one, #line-2           ' |
                movd    :two, #line-1           ' restore initial palette indices
                
                mov     vcfg, vcfg_norm         ' -12   disconnect sync from video h/w  (##)
                mov     vscl, hvis              '  -8   1/8
                mov     phsb, #50 -1            '  -4   column count -1

:line           rdbyte  char, phsb              '  +0 = get character
                add     :one, dst2              '       set colour index
                add     char, eins              '       add font base address
                rdbyte  temp, char              '  +0 = read font definition
:one            cmp     0-0, temp               '       WHOP
                sub     phsb, #1 wz

                rdbyte  char, phsb              '  +0 = get character
                add     :two, dst2              '       set colour index
                add     char, eins              '       add font base address
                rdbyte  temp, char              '  +0 = read font definition
:two            cmp     0-0, temp               '       WHOP
        if_nz   djnz    phsb, #:line

emit_ret        ret                             '  +0 =

' Stuff to do during vertical blank.

pointer         mov     cnt, cnt                ' |
                wrlong  cnt, fcnt_              ' announce vertical blank

                rdlong  temp, scrn_ wz          ' |
        if_nz   mov     scrn, temp              ' |
        if_nz   wrlong  zero, scrn_             ' update and acknowledge screen buffer setup
        
                rdlong  temp, font_ wz          ' |
        if_nz   mov     font, temp              ' |
        if_nz   mov     scan, font              ' |
        if_nz   shr     scan, #24               ' |
        if_nz   wrlong  zero, font_             ' update and acknowledge font definition setup

                rdlong  temp, plte_ wz          ' |
        if_nz   mov     plte, temp wc           ' |
        if_nz   wrlong  zero, plte_             ' update and acknowledge colour buffer setup
        if_c    call    #palette                ' carry is clear on entry

{split}         jmpret  do_v, do_v nr           ' End Of Chain (no more tasks for this frame)


palette         movd    :set, #line
                mov     ecnt, #50
                
:set            mov     0-0, plte               ' |
                add     :set, dst1              ' |
                djnz    ecnt, #$-2              ' initialise (line) palette

palette_ret     ret

' Stuff to do during horizontal blank.

{split}         jmpret  do_h, do_h              ' reset task chain (hsync)

fetch_c         rdlong  copy+0, vier            ' part 0, columns 0..25
                mov     copy+1, copy+0
                add     vier, #4

                rdlong  copy+2, vier
                mov     copy+3, copy+2
                add     vier, #4

                rdlong  copy+4, vier
                mov     copy+5, copy+4
                add     vier, #4

                rdlong  copy+6, vier
                mov     copy+7, copy+6
                add     vier, #4

                rdlong  copy+8, vier
                mov     copy+9, copy+8
                add     vier, #4

                rdlong  copy+10, vier
                mov     copy+11, copy+10
                add     vier, #4

                rdlong  copy+12, vier
                mov     copy+13, copy+12
                add     vier, #4

                rdlong  copy+14, vier
                mov     copy+15, copy+14
                add     vier, #4

                rdlong  copy+16, vier
                mov     copy+17, copy+16
                add     vier, #4

                rdlong  copy+18, vier
                mov     copy+19, copy+18
                add     vier, #4

                rdlong  copy+20, vier
                mov     copy+21, copy+20
                add     vier, #4

                rdlong  copy+22, vier
                mov     copy+23, copy+22
                add     vier, #4

                rdlong  copy+24, vier
                mov     copy+25, copy+24
                add     vier, #4

                shr     copy+$1, #16
                shr     copy+$3, #16
                shr     copy+$5, #16
                shr     copy+$7, #16
                shr     copy+$9, #16
                shr     copy+11, #16
                shr     copy+13, #16
                shr     copy+15, #16
                shr     copy+17, #16
                shr     copy+19, #16
                shr     copy+21, #16
                shr     copy+23, #16
                shr     copy+25, #16
                
{split}         jmpret  do_h, do_h

                rdlong  copy+26, vier           ' part 1, columns 26..49
                mov     copy+27, copy+26
                add     vier, #4

                rdlong  copy+28, vier
                mov     copy+29, copy+28
                add     vier, #4

                rdlong  copy+30, vier
                mov     copy+31, copy+30
                add     vier, #4

                rdlong  copy+32, vier
                mov     copy+33, copy+32
                add     vier, #4

                rdlong  copy+34, vier
                mov     copy+35, copy+34
                add     vier, #4

                rdlong  copy+36, vier
                mov     copy+37, copy+36
                add     vier, #4

                rdlong  copy+38, vier
                mov     copy+39, copy+38
                add     vier, #4

                rdlong  copy+40, vier
                mov     copy+41, copy+40
                add     vier, #4

                rdlong  copy+42, vier
                mov     copy+43, copy+42
                add     vier, #4

                rdlong  copy+44, vier
                mov     copy+45, copy+44
                add     vier, #4

                rdlong  copy+46, vier
                mov     copy+47, copy+46
                add     vier, #4

                rdlong  copy+48, vier
                mov     copy+49, copy+48
                add     vier, #4

                shr     copy+27, #16
                shr     copy+29, #16
                shr     copy+31, #16
                shr     copy+33, #16
                shr     copy+35, #16
                shr     copy+37, #16
                shr     copy+39, #16
                shr     copy+41, #16
                shr     copy+43, #16
                shr     copy+45, #16
                shr     copy+47, #16
                shr     copy+49, #16

{split}         jmpret  do_h, do_h

                mov     line+$0, copy+$0
                mov     line+$1, copy+$1
                mov     line+$2, copy+$2
                mov     line+$3, copy+$3
                mov     line+$4, copy+$4
                mov     line+$5, copy+$5
                mov     line+$6, copy+$6
                mov     line+$7, copy+$7
                mov     line+$8, copy+$8
                mov     line+$9, copy+$9
                mov     line+10, copy+10
                mov     line+11, copy+11
                mov     line+12, copy+12
                mov     line+13, copy+13
                mov     line+14, copy+14
                mov     line+15, copy+15
                mov     line+16, copy+16
                mov     line+17, copy+17
                mov     line+18, copy+18
                mov     line+19, copy+19
                mov     line+20, copy+20
                mov     line+21, copy+21
                mov     line+22, copy+22
                mov     line+23, copy+23
                mov     line+24, copy+24
                mov     line+25, copy+25
                mov     line+26, copy+26
                mov     line+27, copy+27
                mov     line+28, copy+28
                mov     line+29, copy+29
                mov     line+30, copy+30
                mov     line+31, copy+31
                mov     line+32, copy+32
                mov     line+33, copy+33
                mov     line+34, copy+34
                mov     line+35, copy+35
                mov     line+36, copy+36
                mov     line+37, copy+37
                mov     line+38, copy+38
                mov     line+39, copy+39
                mov     line+40, copy+40
                mov     line+41, copy+41
                mov     line+42, copy+42
                mov     line+43, copy+43
                mov     line+44, copy+44
                mov     line+45, copy+45
                mov     line+46, copy+46
                mov     line+47, copy+47
                mov     line+48, copy+48
                mov     line+49, copy+49

                or      vier, hide              ' disable colour fetch

                jmp     #fetch_c -1             ' done

' initialised data and/or presets

sync            long    $0200                   ' locked to %00 {%hv}

slow_pixels     long    $001FFFE0               ' 5/16/11 (LSB first)
slow            long    4 << 12 | 128           ' 4/128
hvis            long    1 << 12 | 8             ' 1/8

vcfg_norm       long    %0_01_0_00_000 << 23 | vgrp << 9 | vpin
vcfg_sync       long    %0_01_0_00_000 << 23 | sgrp << 9 | %11

mask            long    vpin << (vgrp * 8) | %11 << (sgrp * 8)

hide            long    $40000000               ' no colour fetch
do_v            long    pointer                 ' task index (vertical)
do_h            long    fetch_c                 ' task index (horizontal)
          
dst1            long    1 << 9                  ' dst +/-= 1
dst2            long    2 << 9                  ' dst +/-= 2

scrn_           long    +0                      ' |
font_           long    +4                      ' |
plte_           long    +8                      ' |
fcnt_           long    12                      ' mailbox addresses (local copy)

plte            long    NEGX | dcolour          ' colour [buffer]
vier            long    NEGX                    ' hidden

' uninitialised data and/or temporaries

line            res     50                      ' line colour buffer
copy            res     50                      ' line colour buffer

scan            res     1                       ' font height
scrn            res     1                       ' screen buffer
font            res     1                       ' font definition

char            res     1
ecnt            res     1
href            res     1

eins            res     1
zwei            res     1
drei            res     1

temp            res     1

tail            fit
                
CON
  zero    = $1F0                                ' par (dst only)
  vpin    = $0FC                                ' pin group mask
  vgrp    = 2                                   ' pin group
  sgrp    = 2                                   ' pin group sync
  dcolour = %%0220_0010                         ' default colour

  res_x   = 400                                 ' |
  res_y   = 300                                 ' |
  res_m   = 4                                   ' UI support
  
DAT