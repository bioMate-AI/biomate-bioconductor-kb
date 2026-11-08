#!/usr/bin/env python3
"""Build a narration-timed tutorial episode from a live-UI screencast take.

Input:  recording/video/series-actions/<episode>-<take>/<lang>/{timeline.json,frames/}
        (written by frontend/e2e/tutorial-live-episodes.e2e.ts) + the narration clips
        whose hashes the recorder checked.
Output: recording/output/series-live-<take>/<episode>/<episode>-<lang>-LIVE-REVIEW.{mp4,srt,vtt,json}
        plus chapters and downsized audit frames (one per logged action and mid-scene).

Close-ups are crops of the device-pixel frames along the recorder's logged focus
regions (eased 0.5 s transitions). Captions are timed from speech-recognition word
timestamps of each narration clip, not proportional estimates; the transcript is
also compared with the script to flag omissions or mispronunciations for review.

Run with the media venv:  recording/.venv-media/bin/python scripts/recording/build-live-episode.py ...
"""
import argparse, bisect, difflib, hashlib, json, re, subprocess, tempfile, unicodedata, wave
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
STORYBOARDS = {
    'result-downloads': 'reference/claude_design/tutorials/series/episodes/result-downloads/storyboard.json',
    'reproducibility-record': 'reference/claude_design/tutorials/series/episodes/reproducibility-record/storyboard.json',
    'admet-evidence': 'reference/claude_design/tutorials/review-pilot/storyboard.json',
}
FPS = 25
OUT_W, OUT_H = 1920, 1080
SCENE_PAD = 0.8
EASE = 0.5
MIN_CROP_CSS_W = 900
CUE_CHARS = {'en': 84, 'zh': 32}
LINE_CHARS = {'en': 42, 'zh': 16}


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def load(episode, lang, take):
    src = ROOT / 'recording/video/series-actions' / f'{episode}-{take}' / lang
    timeline = json.loads((src / 'timeline.json').read_text())
    frames = json.loads((src / 'frames/frames.json').read_text())['frames']
    board = json.loads((ROOT / STORYBOARDS[episode]).read_text())
    clips = []
    for s, t in zip(board['scenes'], timeline['scenes'], strict=True):
        wav = ROOT / f'recording/audio/series/{episode}/{lang}/step-{s["id"]:03d}.wav'
        receipt = json.loads(wav.with_suffix('.json').read_text())
        text = s[lang]['narration']
        h = hashlib.sha256(text.encode()).hexdigest()
        if not (h == t['narrationSha256'] == receipt['narrationSha256']) or sha(wav) != receipt['audioSha256']:
            raise ValueError(f'Scene {s["id"]}: narration text, audio and recorded timing disagree')
        with wave.open(str(wav)) as w:
            if (w.getframerate(), w.getnchannels(), w.getsampwidth()) != (24000, 1, 2):
                raise ValueError('Unexpected narration format')
            seconds = w.getnframes() / 24000 + SCENE_PAD
        if abs(seconds - t['seconds']) > 0.001:
            raise ValueError(f'Scene {s["id"]}: recorded slot does not match narration length')
        clips.append({'scene': s['id'], 'title': s[lang]['title'], 'narration': text, 'seconds': seconds,
                      'audio': str(wav), 'audioSha256': receipt['audioSha256']})
    total = sum(c['seconds'] for c in clips)
    if timeline['duration'] < total - 0.05:
        raise ValueError('Capture is shorter than the narration')
    return src, timeline, frames, clips, total


def focus_track(timeline):
    """[(t, rect_device_px | None)] — None means the whole viewport."""
    dpr = timeline['deviceScaleFactor']
    vw, vh = timeline['viewport']['width'] * dpr, timeline['viewport']['height'] * dpr
    track = [(0.0, None)]
    for e in timeline['events']:
        if 'focus' not in e:
            continue
        f = e['focus']
        if f is None:
            track.append((e['seconds'], None))
            continue
        x, y, w, h = (f[k] * dpr for k in ('x', 'y', 'w', 'h'))
        cx, cy = x + w / 2, y + h / 2
        w = max(w, MIN_CROP_CSS_W * dpr, h * 16 / 9)
        w = min(w, vw)
        h = w * 9 / 16
        if h > vh:
            h, w = vh, vh * 16 / 9
        x0 = min(max(cx - w / 2, 0), vw - w)
        y0 = min(max(cy - h / 2, 0), vh - h)
        track.append((e['seconds'], (x0, y0, w, h)))
    return track, (vw, vh)


def rect_at(track, full, t):
    i = bisect.bisect_right([p[0] for p in track], t) - 1
    start, target = track[i]
    prev = track[i - 1][1] if i > 0 else None
    full_rect = (0.0, 0.0, full[0], full[1])
    a, b = prev or full_rect, target or full_rect
    k = min(max((t - start) / EASE, 0.0), 1.0)
    k = k * k * (3 - 2 * k)
    return tuple(a[j] + (b[j] - a[j]) * k for j in range(4))


def render(src, timeline, frames, total, out_mp4, audio_wav):
    track, full = focus_track(timeline)
    times = [f['seconds'] for f in frames]
    cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
           '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{OUT_W}x{OUT_H}', '-r', str(FPS), '-i', '-',
           '-i', str(audio_wav), '-t', f'{total:.3f}',
           '-c:v', 'libopenh264', '-b:v', '10M', '-pix_fmt', 'yuv420p',
           '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2',
           '-movflags', '+faststart', str(out_mp4)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    cache = {}
    n = int(round(total * FPS))
    for i in range(n):
        t = i / FPS
        j = max(bisect.bisect_right(times, t) - 1, 0)
        name = frames[j]['file']
        if name not in cache:
            cache.clear()
            cache[name] = Image.open(src / 'frames' / name).convert('RGB')
        x, y, w, h = rect_at(track, full, t)
        img = cache[name].resize((OUT_W, OUT_H), Image.LANCZOS, box=(x, y, x + w, y + h))
        proc.stdin.write(img.tobytes())
    proc.stdin.close()
    if proc.wait():
        raise RuntimeError('ffmpeg encode failed')


def narration_audio(clips, path):
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000)
        for c in clips:
            with wave.open(c['audio']) as r:
                w.writeframes(r.readframes(r.getnframes()))
            w.writeframes(b'\0\0' * int(24000 * SCENE_PAD))


def norm(text, lang):
    text = unicodedata.normalize('NFKC', text).lower()
    return ''.join(ch for ch in text if ch.isalnum()) if lang == 'zh' else re.sub(r'[^a-z0-9]', '', text)


def split_cues(text, lang):
    limit = CUE_CHARS[lang]
    sentences = [s for s in re.split(r'(?<=[.!?。！？])\s*', text) if s.strip()]
    cues = []
    for s in sentences:
        while len(s) > limit:
            cut = max((m.end() for m in re.finditer(r'[,;:，；：、]\s*', s[:limit])), default=0)
            if cut < limit // 3:
                cut = s.rfind(' ', 0, limit) + 1 if lang == 'en' else limit
            cues.append(s[:cut].strip()); s = s[cut:]
        if s.strip():
            cues.append(s.strip())
    return cues


def wrap(text, lang):
    width = LINE_CHARS[lang]
    if len(text) <= width:
        return text
    if lang == 'zh':
        # Break after punctuation when possible, never inside a Latin/number run, never before punctuation.
        import jieba
        punct = '，、。；：！？）”'
        bounds, at = set(), 0
        for tok in jieba.cut(text):
            at += len(tok); bounds.add(at)
        ok = [i for i in sorted(bounds) if 0 < i < len(text)
              and text[i] not in punct and max(i, len(text) - i) <= width + 2]
        if not ok:
            return text
        mid = len(text) / 2
        best = min(ok, key=lambda i: (text[i - 1] not in punct, abs(i - mid)))
        return text[:best] + '\n' + text[best:].lstrip()
    words, lines, cur = text.split(), [], ''
    for w in words:
        if cur and len(cur) + 1 + len(w) > width and len(lines) == 0:
            lines.append(cur); cur = w
        else:
            cur = f'{cur} {w}'.strip()
    return '\n'.join(lines + [cur])


def align(clips, lang, model):
    """Caption cues timed by ASR word timestamps; returns cues and per-scene transcript similarity."""
    cues, review, offset = [], [], 0.0
    for c in clips:
        pcm = subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', c['audio'], '-ac', '1', '-ar', '16000',
                              '-f', 'f32le', '-'], check=True, capture_output=True).stdout
        # No script text in the prompt: it would bias recognition towards the script and hide omissions.
        segments, _ = model.transcribe(np.frombuffer(pcm, dtype=np.float32), language=lang, word_timestamps=True,
                                       beam_size=5, initial_prompt='以下是普通话的句子。' if lang == 'zh' else None)
        words = [w for s in segments for w in s.words]
        transcript = ''.join(w.word for w in words)
        script_n, heard_n = norm(c['narration'], lang), norm(transcript, lang)
        ratio = difflib.SequenceMatcher(None, script_n, heard_n, autojunk=False).ratio()
        review.append({'scene': c['scene'], 'transcript': transcript.strip(), 'similarity': round(ratio, 3)})
        if not words:
            raise ValueError(f'Scene {c["scene"]}: no speech recognised')
        cum, acc = [], 0
        for w in words:
            acc += len(norm(w.word, lang)); cum.append(acc)
        parts = split_cues(c['narration'], lang)
        total_chars = sum(len(norm(p, lang)) for p in parts) or 1
        start, done = words[0].start, 0
        for k, p in enumerate(parts):
            done += len(norm(p, lang))
            if k == len(parts) - 1:
                end = words[-1].end
                cues.append((offset + start, offset + max(end, start + 0.6), wrap(p, lang)))
                break
            idx = min(bisect.bisect_left(cum, done / total_chars * acc), len(words) - 2)
            end = words[idx].end
            cues.append((offset + start, offset + max(end, start + 0.6), wrap(p, lang)))
            start = words[idx + 1].start
        offset += c['seconds']
    return cues, review


def stamp(t, vtt):
    ms = round(t * 1000); h, ms = divmod(ms, 3600000); m, ms = divmod(ms, 60000); s, ms = divmod(ms, 1000)
    return f'{h:02d}:{m:02d}:{s:02d}{"." if vtt else ","}{ms:03d}'


def caption_file(cues, vtt):
    body = '\n\n'.join(f'{i + 1}\n{stamp(a, vtt)} --> {stamp(b, vtt)}\n{t}' for i, (a, b, t) in enumerate(cues))
    return ('WEBVTT\n\n' if vtt else '') + body + '\n'


def audit_frames(out_mp4, timeline, clips, dest):
    dest.mkdir(parents=True, exist_ok=True)
    marks, at = [], 0.0
    for c in clips:
        marks.append((at + c['seconds'] / 2, f'scene{c["scene"]:02d}-mid')); at += c['seconds']
    for i, e in enumerate(timeline['events']):
        if e['action'] != 'Scene start':
            marks.append((e['seconds'] + 1.2, f'event{i:03d}'))
    for t, label in marks:
        if t < at:
            subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-ss', f'{t:.2f}', '-i', str(out_mp4),
                            '-frames:v', '1', '-q:v', '3', str(dest / f'{t:07.2f}-{label}.jpg')], check=True)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--episode', required=True, choices=sorted(STORYBOARDS))
    p.add_argument('--language', required=True, choices=['en', 'zh'])
    p.add_argument('--take', default='v3')
    p.add_argument('--asr-model', default='base')
    a = p.parse_args()
    src, timeline, frames, clips, total = load(a.episode, a.language, a.take)
    out = ROOT / f'recording/output/series-live-{a.take}' / a.episode
    out.mkdir(parents=True, exist_ok=True)
    name = f'{a.episode}-{a.language}-LIVE-REVIEW'
    mp4 = out / f'{name}.mp4'
    if mp4.exists():
        raise SystemExit(f'Refusing to overwrite {mp4}')
    from faster_whisper import WhisperModel
    model = WhisperModel(a.asr_model, device='cpu', compute_type='int8')
    cues, review = align(clips, a.language, model)
    with tempfile.TemporaryDirectory(prefix='biomate-episode-') as td:
        voice = Path(td) / 'voice.wav'
        narration_audio(clips, voice)
        render(src, timeline, frames, total, mp4, voice)
    for ext in ('srt', 'vtt'):
        (out / f'{name}-captions.{ext}').write_text(caption_file(cues, ext == 'vtt'))
    at, chapters = 0.0, []
    for c in clips:
        chapters.append(f'{int(at) // 60:02d}:{int(at) % 60:02d} {c["title"]}'); at += c['seconds']
    (out / f'{name}-chapters.txt').write_text('\n'.join(chapters) + '\n')
    audit_frames(mp4, timeline, clips, out / f'{name}-audit-frames')
    receipt = {'status': 'INTERNAL_REVIEW_NOT_RELEASED', 'visualFormat': 'REAL_UI_SCREENCAST', 'episode': a.episode,
               'language': a.language, 'take': a.take, 'seconds': total, 'videoSha256': sha(mp4),
               'captionTiming': f'ASR_WORD_ALIGNED (faster-whisper {a.asr_model})', 'speechReview': review,
               'uiLanguageSetting': timeline.get('uiLanguageSetting'), 'untranslatedLabels': timeline.get('untranslatedLabels'),
               'cursor': timeline.get('cursor'), 'runId': timeline.get('runId'), 'baseUrl': timeline.get('baseUrl'),
               'scenes': clips, 'events': timeline['events']}
    (out / f'{name}.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    print(mp4)
    for r in review:
        flag = '' if r['similarity'] >= (0.9 if a.language == 'en' else 0.75) else '  <-- REVIEW'
        print(f"scene {r['scene']}: transcript similarity {r['similarity']}{flag}")


if __name__ == '__main__':
    main()
