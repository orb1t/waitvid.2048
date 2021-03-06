''
'' VGA display 400x300 (single cog, monochrome) - video driver and pixel generator
''
''        Author: Marko Lukat
'' Last modified: 2015/12/07
''       Version: 0.3
''
'' long[par][0]: screen: [!Z]:addr = 16:16 -> zero (accepted), 2n
'' long[par][3]: frame indicator
''
'' 20131206: initial version (800x600@60Hz timing, %00 sync locked)
''
OBJ
  system: "core.con.system"
  
PUB null
'' This is not a top level object.
  
PUB init(ID, mailbox)

  return system.launch(ID, @driver, mailbox)
  
DAT             org     0                       ' video driver

driver          jmpret  $, #setup               '  -4   once

                mov     dira, mask              ' drive outputs

' horizontal timing 400(800) 5(40) 16(128) 11(88)
'   vertical timing 300(600) 1(1)   4(4)   23(23)

'               mov     ecnt, #1
vsync           call    #blank                  ' front porch
'               djnz    ecnt, #$-1

                xor     sync, #$0101            ' active

                mov     ecnt, #4
                call    #blank                  ' vertical sync
                djnz    ecnt, #$-1

                xor     sync, #$0101            ' inactive

                mov     ecnt, #23
                call    #blank                  ' back porch
                djnz    ecnt, #$-1

' Vertical sync chain done, do visible area.

                mov     scnt, #res_y            ' scan line count
                mov     eins, scrn              ' screen buffer

:scan           call    #emit                   ' scan line 0
                call    #hsync

                call    #emit                   ' scan line 1
                call    #hsync

                add     eins, #50               ' next line
                djnz    scnt, #:scan            ' repeat for font size

                wrlong  cnt, fcnt_              ' announce vertical blank
                
                jmp     #vsync                  ' next frame


blank           mov     vscl, #res_x            ' 256/400
                waitvid sync, #%00              ' latch blank line

hsync           mov     vscl, wrap              '   4/128
                waitvid sync, wrap_value

                mov     vcfg, vcfg_sync         ' switch back to sync mode              (&&)

                mov     cnt, cnt                ' |
                add     cnt, #9{14}+340         ' |
                waitcnt cnt, #0                 ' record sync point and cover hsync     (&&)
hsync_ret
blank_ret       ret


emit            mov     vscl, hvis              ' 1/16
                mov     ecnt, #25               ' word count

                mov     vcfg, vcfg_norm         ' disconnect sync from video h/w        (&&)

:loop           rdword  zwei, eins              ' get 16 pixels
                add     eins, #2                ' advance address
                waitvid cols, zwei
                djnz    ecnt, #:loop            ' next 16px

                sub     eins, #50               ' rewind
emit_ret        ret                             ' done

' initialised data and/or presets

sync            long    $0200                   ' locked to %00 {%hv}

wrap_value      long    $001FFFE0               ' 5/16/11 (LSB first)
wrap            long    4 << 12 | 128           '   4/128
hvis            long    1 << 12 | 16            '   1/16

vcfg_norm       long    %0_01_0_00_000 << 23 | vgrp << 9 | vpin
vcfg_sync       long    %0_01_0_00_000 << 23 | sgrp << 9 | %11

mask            long    vpin << (vgrp * 8) | %11 << (sgrp * 8)

scrn_           long    +0                      ' |
fcnt_           long    12                      ' mailbox addresses (local copy)

cols            long    dcolour

' Stuff below is re-purposed for temporary storage.

setup           add     scrn_, par              ' @long[par][0]
                add     fcnt_, par              ' @long[par][3]

                rdlong  scrn, scrn_ wz          ' get screen address (2n)               (%%)
        if_nz   wrlong  zero, scrn_             ' acknowledge screen buffer setup
        
' Upset video h/w and relatives.

                movi    ctra, #%0_00001_101     ' PLL, VCO/4
                movi    frqa, #%0001_00000      ' 5MHz * 16 / 4 = 20MHz
                
                mov     vscl, hvis              ' 1/16
                mov     vcfg, vcfg_sync         ' VGA, 2 colour mode

                jmp     %%0                     ' return

                fit
                
' uninitialised data and/or temporaries

                org     setup

scrn            res     1                       ' screen buffer         < setup +2      (%%)
ecnt            res     1                       ' element count
scnt            res     1                       ' scanlines

eins            res     1
zwei            res     1

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

  alias   = 0
  
DAT
