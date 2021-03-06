''
'' VGA display 50xN (single cog) - demo
''
''        Author: Marko Lukat
'' Last modified: 2012/02/25
''       Version: 0.3
''
CON
  _clkmode = client#_clkmode
  _xinfreq = client#_xinfreq

OBJ
  client: "core.con.client.demoboard"
     vga: "waitvid.50xN.ui"
    
VAR
  long  palette[256]
  byte  c
  
PUB selftest

  vga.init

  vga.str(string(vga#ESC, "s"))                         ' page mode
  
  repeat vga#bcnt                                       ' fill screen
    vga.putc(c++)

  waitcnt(clkfreq*3 + cnt)

  repeat                                                ' cycle palette
    longfill(@palette{0}, %%0220_0010, 256)             ' reset to default colour
    palette[c++] := %%3000_0000                         ' |
    palette[c++] := %%0300_0000                         ' |
    palette[c--] := %%0030_0000                         ' add RGB triple
    vga.setn(2, @palette{0})                            ' update palette
    waitcnt(clkfreq/30 + cnt)
  
DAT