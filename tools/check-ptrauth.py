import struct
import sys
from pathlib import Path

root = Path(sys.argv[1])
for name in ('CCShortcutLauncherProvider', 'CCShortcutLauncherPrefs', 'cslresolved'):
    binaries = [p for p in root.rglob(name) if p.is_file()]
    assert len(binaries) == 1, (name, binaries)
    data = binaries[0].read_bytes()
    magic, = struct.unpack_from('>I', data)
    found = False
    if magic in (0xCAFEBABE, 0xCAFEBABF):
        count, = struct.unpack_from('>I', data, 4)
        width = 20 if magic == 0xCAFEBABE else 32
        for i in range(count):
            start = 8 + width * i
            cpu, sub = struct.unpack_from('>II', data, start)
            offset, = struct.unpack_from('>I' if width == 20 else '>Q', data, start + 8)
            thin_cpu, thin_sub = struct.unpack_from('<II', data, offset + 4)
            assert (cpu, sub) == (thin_cpu, thin_sub)
            if cpu == 0x100000C and sub & 0xFFFFFF == 2:
                assert sub & 0x80000000, f'{name}: obsolete arm64e ABI'
                found = True
    assert found, f'{name}: no validated arm64e ABI slice'
    print(name, 'arm64e ptrauth ABI verified')
