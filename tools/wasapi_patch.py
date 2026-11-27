"""Godot 4.7.2's Windows export template with the WASAPI audio fix (26 Nov; docs/release.md, "Crackling").

Godot's WASAPI driver takes IAudioClient3 (low-latency shared mode) for output, with a buffer of exactly one engine
period (10 ms) on a thread without audio priority: on a USB audio interface it crackled. This turns that mode off,
so the driver takes the plain IAudioClient path it already falls back to (Windows' own buffer, about 47 ms):
`using_audio_client_3 = !p_input` compiles to `mov eax,r12d; xor eax,1; mov [rsi+0x104],al`, and `xor eax,1`
(83 f0 01) becomes `xor eax,eax; nop` (31 c0 90). An optional second patch sets the buffer Godot asks for
(Initialize's hnsBufferDuration, 0 = Windows' least) to a number of milliseconds.

    python tools/wasapi_patch.py <windows_release_x86_64.exe> <out.exe> <buffer ms, 0 to leave it>
"""
import sys
src,dst,buf=sys.argv[1],sys.argv[2],sys.argv[3]
d=bytearray(open(src,'rb').read())
a=bytes.fromhex('4489e083f001888604010000')
assert d.count(a)==1, "client3 pattern"
i=d.find(a)+3; d[i:i+3]=bytes.fromhex('31c090')
if buf!='0':
    b=bytes.fromhex('4c89e94181e180969800')
    assert d.count(b)==1, "buffer pattern"
    j=d.find(b)+3; v=int(buf)*10000
    d[j:j+7]=bytes.fromhex('41b9')+v.to_bytes(4,'little')+b'\x90'
open(dst,'wb').write(d)
print("ok")
