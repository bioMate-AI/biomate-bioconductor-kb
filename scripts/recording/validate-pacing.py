#!/usr/bin/env python3
"""
Validate that each TTS cue duration fits within its target tour beat duration
BEFORE running the (expensive) browser recording. Iteratively recompress any
step whose audio is too long.

Usage:
  python3 validate-pacing.py \
    --narration-md  reference/claude_design/research_agents/narration/ra-drugscreen.en.short.md \
    --targets-json  /tmp/drugscreen_targets.json \
    --audio-dir     recording/audio/ra-drugscreen/

Exit code 0 = all cues fit; 1 = still overflowing after max retries.
"""
import json, argparse, pathlib, subprocess, sys, re, time

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--narration-md', required=True)
    ap.add_argument('--targets-json', required=True)
    ap.add_argument('--audio-dir',    required=True)
    ap.add_argument('--narration-src', required=True,
                    help='original (uncompressed) narration .md — used to recompress')
    ap.add_argument('--max-retries', type=int, default=2)
    args = ap.parse_args()

    targets = json.loads(pathlib.Path(args.targets_json).read_text())
    audio_dir = pathlib.Path(args.audio_dir)

    # Generate TTS once first
    print(f'[validate] Generating TTS for {args.narration_md}')
    audio_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        'python3', 'scripts/recording/edge-tts-gen.py',
        '--narration', args.narration_md, '--out', str(audio_dir)
    ], check=True)

    for attempt in range(args.max_retries + 1):
        timing = json.loads((audio_dir / 'timing.json').read_text())
        overflows = []  # (idx, step_num, dur_s, target_s)
        for i, t in enumerate(timing):
            dur_s = t['duration_ms'] / 1000.0
            tgt = float(targets[i]) if i < len(targets) else 10.0
            margin = tgt - dur_s
            status = '✓' if dur_s <= tgt else 'OVERFLOW'
            print(f'  step {t["step"]:>2}: dur={dur_s:5.1f}s  target={tgt:5.1f}s  margin={margin:+5.1f}s  {status}')
            if dur_s > tgt:
                overflows.append((i, t['step'], dur_s, tgt))

        if not overflows:
            print(f'[validate] All {len(timing)} cues fit. ✓')
            return 0

        if attempt == args.max_retries:
            print(f'[validate] {len(overflows)} cues still overflow after {attempt+1} attempts')
            return 1

        # Recompress steps that overflowed, using a tighter per-step target
        tighter = []
        for i in range(len(timing)):
            t = float(targets[i]) if i < len(targets) else 10.0
            # If this step overflowed last attempt, halve its narration target
            over = next((o for o in overflows if o[0] == i), None)
            if over:
                # Pick new target that the model SHOULD speak within
                ratio = t / over[2]            # what fraction of dur fits
                # Aim 0.6× actual duration → solidly within beat
                new_target = max(2.0, t * 0.6)
                tighter.append(new_target)
            else:
                tighter.append(t * 0.7)        # default already 0.7
        tight_path = pathlib.Path('/tmp/tighter_targets.json')
        tight_path.write_text(json.dumps(tighter))

        print(f'[validate] Retry {attempt+1}: recompressing with tighter targets...')
        subprocess.run([
            'python3', '-u', 'scripts/recording/compress-en-narration.py',
            '--in',  args.narration_src,
            '--out', args.narration_md,
            '--per-step-seconds', str(tight_path),
        ], check=True)
        subprocess.run([
            'python3', 'scripts/recording/edge-tts-gen.py',
            '--narration', args.narration_md, '--out', str(audio_dir),
        ], check=True)

    return 1


if __name__ == '__main__':
    sys.exit(main())
