#!/bin/bash
# No-op bootstrap for CPU data-build boxes: the literature builder is stdlib-only (no torch/pip needed).
echo "[noop_bootstrap] python3=$(python3 --version 2>&1) aws=$(aws --version 2>&1 | head -1) nproc=$(nproc 2>/dev/null)"
