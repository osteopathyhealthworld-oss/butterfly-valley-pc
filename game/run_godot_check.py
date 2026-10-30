"""Godot can exit zero after script errors. Make them fatal before export."""
import re
import subprocess
import sys

result = subprocess.run(sys.argv[1:], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=240)
print(result.stdout, end="")
bad = re.search(r"(?m)(?:SCRIPT ERROR:|Parse Error:|^ERROR:|Assertion failed)", result.stdout)
sys.exit(result.returncode or (1 if bad else 0))
