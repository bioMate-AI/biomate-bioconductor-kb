#!/usr/bin/env python3
"""
Generate per-step WAV audio using gTTS (Google TTS, free, no quota).
Produces the same timing.json + per-step WAVs as gemini-tts.py.

Usage:
  python3 scripts/recording/gtts-gen.py \
    --narration reference/claude_design/biomate/cryosparc-narration.md \
    --out recording/audio/cryosparc-main/
"""

import re, wave, struct, pathlib, argparse, json, subprocess, tempfile, os

SAMPLE_RATE = 24000
SILENCE_MS  = 600   # pause between steps in concatenated track


def parse_narration(path: str) -> list[dict]:
    text = pathlib.Path(path).read_text()
    blocks = re.split(r'\n---\n', text.strip())
    steps = []
    for block in blocks:
        m = re.match(r'##\s+Step\s+(\d+)\s+[—-]\s+(.+?)\n+(.+)', block.strip(), re.DOTALL)
        if m:
            body = m.group(3).strip()
            body = re.sub(r'\*+([^*]+)\*+', r'\1', body)
            body = re.sub(r'`([^`]+)`', r'\1', body)
            steps.append({'num': int(m.group(1)), 'title': m.group(2).strip(), 'text': body})
    return steps


def gtts_to_wav(text: str, wav_path: str):
    """Generate speech via gTTS → mp3 → wav (24kHz mono 16-bit)."""
    from gtts import gTTS
    with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as f:
        mp3_path = f.name
    try:
        gTTS(text=text, lang='en', slow=False).save(mp3_path)
        # Convert mp3 → wav at 24kHz mono 16-bit using ffmpeg
        subprocess.run([
            'ffmpeg', '-y', '-i', mp3_path,
            '-ar', str(SAMPLE_RATE), '-ac', '1', '-sample_fmt', 's16',
            wav_path
        ], check=True, capture_output=True)
    finally:
        os.unlink(mp3_path)


def wav_duration_ms(wav_path: str) -> int:
    with wave.open(wav_path, 'rb') as w:
        return int(w.getnframes() / w.getframerate() * 1000)


def silence_pcm(ms: int) -> bytes:
    n = int(SAMPLE_RATE * ms / 1000)
    return struct.pack('<' + 'h' * n, *([0] * n))


def wav_to_pcm(wav_path: str) -> bytes:
    with wave.open(wav_path, 'rb') as w:
        return w.readframes(w.getnframes())


def pcm_to_wav(pcm: bytes, path: str):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--narration', required=True)
    parser.add_argument('--out',       required=True)
    args = parser.parse_args()

    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    steps = parse_narration(args.narration)
    if not steps:
        print('ERROR: no steps parsed'); return

    print(f'Generating TTS (gTTS) for {len(steps)} steps')

    silence = silence_pcm(SILENCE_MS)
    pcm_parts = []
    timing = []

    for step in steps:
        print(f'  [{step["num"]:02d}] {step["title"][:55]}')
        wav_path = str(out_dir / f'step-{step["num"]:03d}.wav')
        try:
            gtts_to_wav(step['text'], wav_path)
            dur = wav_duration_ms(wav_path)
            pcm = wav_to_pcm(wav_path)
            print(f'       → {dur/1000:.1f}s')
        except Exception as e:
            print(f'       ERROR: {e}')
            dur = 2000
            pcm = silence_pcm(dur)
            pcm_to_wav(pcm, wav_path)

        timing.append({'step': step['num'], 'title': step['title'], 'duration_ms': dur})
        pcm_parts.append(pcm)
        pcm_parts.append(silence)

    all_pcm = b''.join(pcm_parts)
    concat_path = out_dir / 'full-narration.wav'
    pcm_to_wav(all_pcm, str(concat_path))
    total_s = sum(t['duration_ms'] for t in timing) / 1000
    print(f'\nConcatenated: {concat_path}  ({total_s:.1f}s = {total_s/60:.1f} min)')

    timing_path = out_dir / 'timing.json'
    timing_path.write_text(json.dumps(timing, indent=2))
    print(f'Timing: {timing_path}')


if __name__ == '__main__':
    main()
