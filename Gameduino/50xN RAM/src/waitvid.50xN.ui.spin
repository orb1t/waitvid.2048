''
'' VGA display 50xN (single cog) - user interface
''
''        Author: Marko Lukat
'' Last modified: 2014/09/21
''       Version: 0.7
''
'' acknowledgements
'' - conversion and output methods are based on FullDuplexSerial code (except dec)
'' - mikronauts font object(s) are copyright William Henning
''
'' 20120106: sync'd with 50xH.ui
'' 20120225: sync'd with 50xH.ui, added dec method
'' 20120909: colour clean-up now done at driver level
'' 20140921: adjusted font name to new format
''
CON
  columns  = driver#res_x / 8
  rows     = driver#res_y / font#height
  bcnt     = columns * rows

  rows_raw = (driver#res_y + font#height - 1) / font#height
  bcnt_raw = columns * rows_raw

CON
  #8, BS, TAB, LF, VT, FF, CR, ESC = 27
  
OBJ
  driver: "waitvid.50xN.driver.2048"
    font: "generic8x12-1font"
    
VAR
  long  link[driver#res_m]                              ' driver mailbox
  word  scrn[bcnt_raw / 2]                              ' screen buffer (2n aligned)

  byte  x, y, page                                      ' cursor position, page mode
  word  flag
  
PUB null
'' This is not a top level object.

PUB init

  out(FF)                                               ' clear screen
  
  link{0} := @scrn.byte[constant(bcnt_raw - columns)]   ' initial screen buffer and
  link[1] := font#height << 24 | font.addr              ' font definition (default palette)

  return driver.init(-1, @link{0})                      ' video driver and pixel generator

PUB setn(n, addr)

  link[n] := addr
  repeat
  while link[n]

  return @link{0}
  
PUB putc(c)

  scrn.byte[bcnt_raw - y * columns - ++x] := c          ' pre-increment resolves (bcnt_raw -1)
  if x == columns
    x := newline                                        ' CR/LF

PRI newline

  if ++y == rows
    if page                                             ' page/scroll?
      y := 0
      return
    y--
    wordmove(@scrn.byte[columns], @scrn{0}, constant((bcnt_raw - columns) / 2))
    if rows_raw == rows
      wordfill(@scrn{0}, $2020, constant(columns / 2))

PUB str(addr)

  repeat strsize(addr)
    out(byte[addr++])

PUB hex(value, digits)

  value <<= (8 - digits) << 2
  repeat digits
    putc(lookupz((value <-= 4) & %1111 : "0".."9", "A".."F"))

PUB bin(value, digits)

  value <<= 32 - digits
  repeat digits
    putc((value <-= 1) & 1 + "0")

PUB dec(value) | s[4], p

  s{0} := value < 0                                     ' remember sign

  p := @p                                               ' initialise string pointer
  byte[--p] := 0                                        ' terminate string
  
  repeat
    byte[--p] := ||(value // 10) + "0"                  ' |
    value /= 10                                         ' |
  while value                                           ' create decimal representation

  if s{0}                                               ' optionally
    byte[--p] := "-"                                    ' prepend sign

  repeat strsize(p)
    putc(byte[p++])                                     ' emit string
  
PUB out(c) : succ
'' Output a character
''
''     $00 = NUL   clear screen
''     $01 = SOH   home
''     $08 = BS  * backspace
''     $09 = TAB * tab
''     $0A = LF    set X position (X follows)
''     $0B = VT    set Y position (Y follows)
''     $0C = FF  * clear screen
''     $0D = CR  * return
''     $1B = ESC   sequence(s)
''  others = printable characters

  case flag.byte{0}
    $00: case c                                             
           $00..$01,FF:                            
             if c <> $01                           
               wordfill(@scrn{0}, $2020, constant(bcnt_raw / 2))
             x := y := 0                           
           $08: x := (x - 1) #> 0                  
           TAB: repeat 8 - (x & 7)                    
                  putc(" ")                         
           $0A..$0B: flag := c << 8 | "="               ' emulate head/tail of ESC=<x><y>
           $0D: x := newline                            ' CR/LF
           ESC: flag := c                           
           other: putc(c)                            
    ESC: case c
           "s", "S": page := c & $20                    ' page (ESC+s) and scroll mode (ESC+S)
           "=":      succ := constant($0200 | "=")      ' ESC=<x><y>
         flag := succ~
    "=": case flag.byte[1]--
           2..10: flag &= tr(c, @x, columns, flag >> 11)
           other: flag := tr(c, @y, rows, TRUE)
    
PRI tr(c, addr, limit, response)

  if c.byte{0} < 255
    byte[addr] := c.byte{0} // limit

  return not response

DAT