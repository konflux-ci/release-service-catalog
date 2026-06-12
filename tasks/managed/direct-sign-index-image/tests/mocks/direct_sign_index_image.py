#!/usr/bin/env python3
import sys

args = " ".join(sys.argv[1:])
print(f"Mock direct_sign_index_image.py called with: {args}")

with open("$(params.dataDir)/mock_direct_sign_index_image.txt", "a") as f:
    f.write(args + "\n")
