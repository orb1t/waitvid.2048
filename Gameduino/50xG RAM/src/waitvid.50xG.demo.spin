''
'' VGA display 50xG (single cog) - demo
''
''        Author: Marko Lukat
'' Last modified: 2012/09/09
''       Version: 0.4
''
CON
  _clkmode = client#_clkmode
  _xinfreq = client#_xinfreq

OBJ
  client: "core.con.client.demoboard"
     vga: "waitvid.50xG.ui"
    font: "fourCol8x8-1font"
    
VAR
  long  palette[256]
  byte  c
  
PUB selftest | p

  vga.init

  vga.str(string(vga#ESC, "s"))                         ' page mode
  
  repeat vga#bcnt                                       ' fill screen
    vga.putc(c++)

  waitcnt(clkfreq*3 + cnt)

  repeat 150                                            ' cycle palette
    longfill(@palette{0}, %%0220_0010, 256)             ' reset to default colour
    palette[c++] := %%3000_0000                         ' |
    palette[c++] := %%0300_0000                         ' |
    palette[c--] := %%0030_0000                         ' add RGB triple
    vga.setn(2, @palette{0})                            ' update palette
    waitcnt(clkfreq/30 + cnt)

  longfill(@palette{0}, %%2220_0000, 256)               ' black background
  vga.setn(2, @palette{0})                              ' update palette
  vga.out(vga#FF)                                       ' clear screen

  print(10, 10, string(10, 14, 14, 11))                 '
  print(10, 11, string(15, 20, 23, 15))                 '
  print(10, 12, string(15, 21, 22, 15))                 '
  print(10, 13, string(12, 14, 14, 13))                 ' frame with redefine target

  waitcnt(clkfreq + cnt)

  redefine(20, @trgt_0)
  redefine(21, @trgt_1)
  redefine(22, @trgt_2)
  redefine(23, @trgt_3)

  waitcnt(clkfreq + cnt)

  p := %%3330_0300_0100_0000
  repeat                                                ' animate palette
    palette[20] := p <-= 8
    palette[21] := p
    palette[22] := p
    palette[23] := p
    vga.setn(2, @palette{0})                            ' update palette, sync'd to vblank
    repeat 3
      vga.setn(2, %11)                                  ' skip 3 frames
  
DAT

trgt_0  word    %%01230123, %%30321030, %%21012321, %%12303012, %%03212103, %%30103230, %%21230121, %%10321032
trgt_1  word    %%10321032, %%21230121, %%30103230, %%03212103, %%12303012, %%21012321, %%30321030, %%01230123
trgt_2  word    %%23012301, %%12103212, %%03230103, %%30121230, %%21030321, %%12321012, %%03012303, %%32103210
trgt_3  word    %%32103210, %%03012303, %%12321012, %%21030321, %%30121230, %%03230103, %%12103212, %%23012301

PRI redefine(char, data) : base

  base := font.addr
  repeat 8
    word[base][char] := word[data]
    base += 512
    data += 2

PRI print(x, y, s)

  vga.str(string(vga#ESC, "="))
  vga.out(x)
  vga.out(y)
  repeat strsize(s)
    vga.putc(byte[s++])
  
DAT