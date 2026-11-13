#!/bin/bash
# Free disk on this Mac for BioMate deploy work. Safe/rebuildable targets only.
# Run in YOUR Terminal (not Cursor's agent): bash scripts/free_disk_20261112.sh
set -u
LOG=/tmp/biomate_free_disk_20261112.log
exec > >(tee "$LOG") 2>&1

BEFORE=$(df -k /System/Volumes/Data | awk 'NR==2{print $4}')
echo "START avail=$(df -h /System/Volumes/Data | awk 'NR==2{print $4}')"

echo "== 1) Downloads installers (~900MB) =="
rm -f /Users/kky/Downloads/Cursor-darwin-arm64.dmg \
      /Users/kky/Downloads/qwenworkcn-darwin-arm64.dmg
rm -rf "/Users/kky/Downloads/Visual Studio Code.app"

echo "== 2) App / package caches =="
rm -rf \
  "/Users/kky/Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt" \
  "/Users/kky/Library/Caches/Google" \
  "/Users/kky/Library/Caches/us.zoom.xos" \
  "/Users/kky/Library/Caches/Codex" \
  "/Users/kky/Library/Caches/pip" \
  "/Users/kky/Library/Caches/node-gyp" \
  "/Users/kky/Library/Caches/ms-playwright" \
  "/Users/kky/Library/Caches/com.apple.python" \
  /Users/kky/.npm/_cacache /Users/kky/.npm/_logs /Users/kky/.npm/_npx \
  /Users/kky/.cache/pip /Users/kky/.cache/huggingface \
  /Users/kky/.nextflow/cache \
  "/Users/kky/Library/Application Support/Cursor/Cache" \
  "/Users/kky/Library/Application Support/Cursor/CachedData" \
  "/Users/kky/Library/Application Support/Cursor/GPUCache" \
  "/Users/kky/Library/Application Support/Cursor/Code Cache" \
  "/Users/kky/Library/Application Support/Cursor/CachedExtensionVSIXs"

echo "== 3) Huge Claude transcripts (>50MB) =="
# NOTE: this permanently deletes large agent transcripts (not just caches) and is irreversible.
find /Users/kky/.claude/projects -name '*.jsonl' -size +50M -print -delete

echo "== 4) Claude debug / snapshots =="
rm -rf /Users/kky/.claude/debug /Users/kky/.claude/shell-snapshots \
  /Users/kky/.claude/chrome /Users/kky/.claude/cache

echo "== 5) Vite / turbo / nextflow junk in biomate trees =="
# Use -delete / -exec + to avoid ARG_MAX
find /Users/kky/biomate /Users/kky/biomate-* -type d \( -name '.vite' -o -name '.turbo' -o -name '.nextflow' \) -prune -exec rm -rf {} + 2>/dev/null || true
find /Users/kky/biomate /Users/kky/biomate-* \( -name '*.tsbuildinfo' -o -name 'vitest.config.ts.timestamp-*.mjs' \) -delete 2>/dev/null || true

MID=$(df -k /System/Volumes/Data | awk 'NR==2{print $4}')
echo "AFTER_CACHES avail=$(df -h /System/Volumes/Data | awk 'NR==2{print $4}') freed_mb=$(( (MID-BEFORE)/1024 ))"

echo "== 6) Remove clean detached worktrees =="
MAIN_GIT=/Users/kky/biomate
for wt in \
  /Users/kky/biomate-conflictfix \
  /Users/kky/biomate-syncdeploy \
  /Users/kky/biomate-voicedeploy
do
  if [ ! -d "$wt" ]; then
    echo "skip missing $wt"
    continue
  fi
  dirty=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if [ "$dirty" != "0" ]; then
    echo "SKIP dirty worktree ($dirty changes): $wt"
    continue
  fi
  echo "Removing clean worktree: $wt"
  if ! git -C "$MAIN_GIT" worktree remove --force "$wt"; then
    echo "worktree remove failed; rm -rf + prune"
    rm -rf "$wt"
    git -C "$MAIN_GIT" worktree prune || true
  fi
done

# panelfix is dirty=1 — leave it unless only .last_dev_sync or similar
if [ -d /Users/kky/biomate-deploy-panelfix ]; then
  echo "Leaving biomate-deploy-panelfix (has local changes):"
  git -C /Users/kky/biomate-deploy-panelfix status -sb | head -8
fi

AFTER=$(df -k /System/Volumes/Data | awk 'NR==2{print $4}')
echo "DONE avail=$(df -h /System/Volumes/Data | awk 'NR==2{print $4}') total_freed_mb=$(( (AFTER-BEFORE)/1024 ))"
df -h /System/Volumes/Data | head -2
echo "FREE_DISK_OK" > /tmp/biomate_free_disk_DONE
