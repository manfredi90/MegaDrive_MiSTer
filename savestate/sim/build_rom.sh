#!/bin/sh
# Build the test ROM (needs z80asm and binutils-m68k-linux-gnu).
set -e
cd "$(dirname "$0")"
z80asm -o z80prog.bin z80prog.asm
m68k-linux-gnu-as -m68000 -o testrom.o testrom.s
m68k-linux-gnu-ld -e 0 -Ttext=0 -Tbss=0xFFF000 --oformat binary -o testrom.bin testrom.o
rm -f testrom.o
python3 -c "
import sys
d=open('testrom.bin','rb').read()
d+=bytes(len(d)&1)
open('testrom.hex','w').write('\n'.join('%04x'%(d[i]<<8|d[i+1]) for i in range(0,len(d),2))+'\n')"
# Master System mode program for tb.sv -DSMS: each byte twice, read on the low byte lane
z80asm -o smsprog.bin smsprog.asm
python3 -c "
d=open('smsprog.bin','rb').read()
open('smsrom.hex','w').write('\n'.join('%04x'%(b<<8|b) for b in d)+'\n')"
