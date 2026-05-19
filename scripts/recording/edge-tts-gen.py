#!/usr/bin/env python3
"""
Generate per-step WAV audio using Microsoft edge-tts (free, no quota).
Drop-in replacement for gemini-tts.py — same per-step .wav + timing.json + full-narration.wav.

Default voice: en-US-AriaNeural (warm female, similar profile to Aoede).
Pick another with TTS_VOICE env var (e.g. en-US-JennyNeural, en-US-GuyNeural).
"""
import re, wave, struct, pathlib, argparse, json, subprocess, tempfile, os, asyncio

SAMPLE_RATE = 24000
SILENCE_MS  = int(os.environ.get('SILENCE_MS', '300'))
VOICE       = os.environ.get('TTS_VOICE', 'en-US-AriaNeural')
RATE        = os.environ.get('TTS_RATE', '+25%')  # speed up so narration fits tour beats


def parse_narration(path):
    text = pathlib.Path(path).read_text()
    blocks = re.split(r'\n---\n', text.strip())
    steps = []
    for b in blocks:
        m = re.search(r'##\s+Step\s+(\d+)\s+[—-]\s+(.+?)\n+(.+)', b.strip(), re.DOTALL)
        if m:
            body = m.group(3).strip()
            body = re.sub(r'\*+([^*]+)\*+', r'\1', body)
            body = re.sub(r'`([^`]+)`', r'\1', body)
            steps.append({'num': int(m.group(1)), 'title': m.group(2).strip(), 'text': body})
    return steps


async def synth_to_mp3(text, mp3_path):
    import edge_tts
    com = edge_tts.Communicate(text, VOICE, rate=RATE)
    await com.save(mp3_path)


def to_wav(text, wav_path):
    with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as f:
        mp3 = f.name
    try:
        asyncio.run(synth_to_mp3(text, mp3))
        subprocess.run(['ffmpeg', '-y', '-i', mp3,
                        '-ar', str(SAMPLE_RATE), '-ac', '1', '-sample_fmt', 's16',
                        wav_path], check=True, capture_output=True)
    finally:
        os.unlink(mp3)


def wav_duration_ms(p):
    with wave.open(p, 'rb') as w:
        return int(w.getnframes() / w.getframerate() * 1000)

def silence_pcm(ms):
    n = int(SAMPLE_RATE * ms / 1000)
    return struct.pack('<' + 'h' * n, *([0] * n))

def wav_to_pcm(p):
    with wave.open(p, 'rb') as w:
        return w.readframes(w.getnframes())

def pcm_to_wav(pcm, p):
    with wave.open(p, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--narration', required=True)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()

    out = pathlib.Path(args.out); out.mkdir(parents=True, exist_ok=True)
    steps = parse_narration(args.narration)
    print(f'edge-tts {VOICE}: {len(steps)} steps')

    silence = silence_pcm(SILENCE_MS)
    parts, timing = [], []
    for s in steps:
        wp = str(out / f'step-{s["num"]:03d}.wav')
        try:
            to_wav(s['text'], wp)
            dur = wav_duration_ms(wp)
            pcm = wav_to_pcm(wp)
            print(f'  [{s["num"]:02d}] {dur/1000:.1f}s  {s["title"][:50]}')
        except Exception as e:
            print(f'  [{s["num"]:02d}] ERROR {e} — silence placeholder')
            dur = 2000
            pcm = silence_pcm(dur)
            pcm_to_wav(pcm, wp)
        timing.append({'step': s['num'], 'title': s['title'], 'duration_ms': dur})
        parts.append(pcm); parts.append(silence)

    pcm_to_wav(b''.join(parts), str(out / 'full-narration.wav'))
    (out / 'timing.json').write_text(json.dumps(timing, indent=2))
    total = sum(t['duration_ms'] for t in timing) / 1000
    print(f'Total: {total:.1f}s = {total/60:.1f}min  ({out/"full-narration.wav"})')


if __name__ == '__main__':
    main()
