#!/usr/bin/env python3
"""Exercise the real child protocol without dimming or restoring any display."""
import select
import subprocess
from pathlib import Path
binary = Path(__file__).resolve().parents[1] / 'build/Shade.app/Contents/MacOS/Shade'
for i in range(20):
    child = subprocess.Popen([str(binary), '--restore-guard', '0', '0.5'], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        assert select.select([child.stdout], [], [], 3)[0], 'No ready acknowledgment'
        assert child.stdout.read(1) == b'\x01'
        # Disarm must work even while the parent keeps its write descriptor open.
        child.stdin.write(b'C')
        child.stdin.flush()
        assert child.wait(timeout=3) == 0
    finally:
        child.stdin.close()
        child.stdout.close()
        if child.poll() is None:
            child.kill()
            child.wait()
print('Restore guard: 20 disarm/exit cycles passed (no display changes)')
