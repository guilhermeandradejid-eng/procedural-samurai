"""Writes input.txt (one prompt per line, the order gives the output ids) from prompts.json."""
import json
import sys

d = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "prompts.json"))
for c in d["clips"]:
    sys.stdout.write(c["prompt"].replace("\n", " ") + "\n")
