#!/usr/bin/env bash
# De-hardcode committed API keys (ElevenLabs VO + Gemini TTS/subtitle scripts).
# Pattern-anchored: replaces the KEY LINES by matching the variable name, so it
# never reads or prints the secret value. Idempotent and safe to re-run.
#
# AFTER running this you MUST:
#   1. Stash the ElevenLabs key locally (matches the openrouter.key pattern):
#        echo '<sk_... key>' > ~/.config/biomate/elevenlabs.key && chmod 600 ~/.config/biomate/elevenlabs.key
#   2. export GEMINI_API_KEY=<key>   (or add to ~/.zshrc) for the Gemini scripts.
#   3. ROTATE both keys — the old values are in git history and are compromised.
#
# Review the diff before committing:  git -C "$REPO" diff -- <files>
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

changed=0

# --- ElevenLabs VO scripts -------------------------------------------------
for f in \
  reference/claude_design/biomate_story/generate_vo.py \
  reference/claude_design/tutorials-work/generate_vo.py \
  reference/claude_design/biomate-intro-v3/generate_vo.py
do
  [ -f "$f" ] || continue
  # API key -> env, fallback to ~/.config/biomate/elevenlabs.key
  perl -0pi -e 's{^API_KEY\s*=\s*"[^"]*"}{API_KEY  = os.environ.get("ELEVENLABS_API_KEY") or open(os.path.expanduser("~/.config/biomate/elevenlabs.key")).read().strip()}m' "$f"
  # Voice id -> env with the public Rachel default (not a secret)
  perl -0pi -e 's{^VOICE_ID\s*=\s*"[^"]*"}{VOICE_ID = os.environ.get("ELEVENLABS_VOICE_ID", "21m00Tcm4TlvDq8ikWAM")}m' "$f"
  # ensure `import os` is present (the env/open calls need it)
  grep -qE '^[[:space:]]*import os' "$f" || perl -0pi -e 's{\A}{import os\n}' "$f"
  echo "de-hardcoded: $f"
  changed=1
done

# --- Gemini TTS / subtitle scripts ----------------------------------------
for g in \
  scripts/recording/condense-zh-subs.py \
  scripts/recording/compress-en-narration.py \
  scripts/recording/gemini-tts.py
do
  [ -f "$g" ] || continue
  # strip the hardcoded literal fallback from os.environ.get('GEMINI_API_KEY', '<literal>')
  perl -0pi -e "s{os\.environ\.get\('GEMINI_API_KEY',\s*'[^']*'\)}{os.environ.get('GEMINI_API_KEY')}g" "$g"
  echo "de-hardcoded (gemini fallback): $g"
  changed=1
done

if [ "$changed" = 1 ]; then
  echo
  echo "Done. Review:  git diff -- reference/claude_design scripts/recording"
  echo "Remember: create ~/.config/biomate/elevenlabs.key, export GEMINI_API_KEY, and ROTATE both keys."
else
  echo "No target files found."
fi
