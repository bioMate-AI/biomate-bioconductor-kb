#!/usr/bin/env python3
"""
Generate per-step WAV audio from a narration .md file using Gemini TTS.

Usage:
  python3 scripts/recording/gemini-tts.py \
    --narration reference/claude_design/biomate/cryosparc-narration.md \
    --out recording/audio/cryosparc/

The script writes:
  - recording/audio/cryosparc/step-001.wav ... step-019.wav
  - recording/audio/cryosparc/full-narration.wav  (concatenated)
  - recording/audio/cryosparc/timing.json          (step durations for playwright-record.py)
"""

import re, wave, struct, pathlib, argparse, os, json, time

GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY', 'AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI')
TTS_MODEL      = 'gemini-2.5-flash-preview-tts'
SAMPLE_RATE    = 24000
SILENCE_MS     = 800   # pause between steps in the concatenated track

# Voices: Aoede (neutral/clear), Charon (warm), Fenrir (energetic),
#         Kore (soft), Orbit (confident), Puck (lively), Zephyr (bright)
VOICE_NAME     = os.environ.get('TTS_VOICE', 'Aoede')


def parse_narration(path: str) -> list[dict]:
    """Parse '## Step N — title\n\ntext\n---' blocks from a narration .md file."""
    text = pathlib.Path(path).read_text()
    blocks = re.split(r'\n---\n', text.strip())
    steps = []
    for block in blocks:
        # Match: ## Step N — Title\n\nBody text
        m = re.match(r'##\s+Step\s+(\d+)\s+[—-]\s+(.+?)\n+(.+)', block.strip(), re.DOTALL)
        if m:
            body = m.group(3).strip()
            # Strip any markdown bold/italic for clean TTS
            body = re.sub(r'\*+([^*]+)\*+', r'\1', body)
            body = re.sub(r'`([^`]+)`', r'\1', body)
            steps.append({
                'num':   int(m.group(1)),
                'title': m.group(2).strip(),
                'text':  body,
            })
    return steps


def tts(text: str) -> bytes:
    """Call Gemini TTS and return raw PCM bytes (24 kHz, 16-bit mono)."""
    from google import genai
    from google.genai import types

    client = genai.Client(api_key=GEMINI_API_KEY)
    resp = client.models.generate_content(
        model=TTS_MODEL,
        contents=text,
        config=types.GenerateContentConfig(
            response_modalities=['AUDIO'],
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(
                        voice_name=VOICE_NAME
                    )
                )
            ),
        ),
    )
    return resp.candidates[0].content.parts[0].inline_data.data


def pcm_to_wav(pcm: bytes, path: str):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)   # 16-bit
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm)


def silence_pcm(ms: int) -> bytes:
    n = int(SAMPLE_RATE * ms / 1000)
    return struct.pack('<' + 'h' * n, *([0] * n))


def duration_ms(pcm: bytes) -> int:
    n_samples = len(pcm) // 2
    return int(n_samples / SAMPLE_RATE * 1000)


def main():
    parser = argparse.ArgumentParser(description='Generate TTS audio from narration .md')
    parser.add_argument('--narration', required=True, help='Path to narration .md file')
    parser.add_argument('--out',       required=True, help='Output directory for WAV files')
    parser.add_argument('--voice',     default=None, help='Gemini TTS voice name')
    args = parser.parse_args()

    global VOICE_NAME
    if args.voice:
        VOICE_NAME = args.voice

    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    steps = parse_narration(args.narration)
    if not steps:
        print('ERROR: no steps parsed from', args.narration)
        return

    print(f'Generating TTS for {len(steps)} steps  (voice: {VOICE_NAME})')
    print(f'Output dir: {out_dir}\n')

    silence = silence_pcm(SILENCE_MS)
    pcm_parts = []
    timing = []

    for step in steps:
        print(f'  [{step["num"]:02d}] {step["title"][:55]}')
        try:
            pcm = tts(step['text'])
        except Exception as e:
            print(f'       ERROR: {e} — skipping')
            pcm = silence_pcm(2000)

        wav_path = out_dir / f'step-{step["num"]:03d}.wav'
        pcm_to_wav(pcm, str(wav_path))
        dur = duration_ms(pcm)
        print(f'       → {wav_path.name}  ({dur / 1000:.1f}s)')

        timing.append({'step': step['num'], 'title': step['title'], 'duration_ms': dur})
        pcm_parts.append(pcm)
        pcm_parts.append(silence)

        time.sleep(0.2)   # stay well under rate limits

    # Concatenated track
    all_pcm = b''.join(pcm_parts)
    concat_path = out_dir / 'full-narration.wav'
    pcm_to_wav(all_pcm, str(concat_path))
    total_s = sum(t['duration_ms'] for t in timing) / 1000
    print(f'\nConcatenated: {concat_path}')
    print(f'Total narration: {total_s:.1f}s  ({total_s / 60:.1f} min)')

    # Timing JSON
    timing_path = out_dir / 'timing.json'
    timing_path.write_text(json.dumps(timing, indent=2))
    print(f'Timing file:  {timing_path}')


if __name__ == '__main__':
    main()
