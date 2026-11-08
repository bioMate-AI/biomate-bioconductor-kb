#!/usr/bin/env python3
"""Build the zh voiceover from a v4 narration .md, align it to the recorded webm via
the deck's __timeline, and mux to a 1080p mp4 (libopenh264 + AAC).

Usage: render_audio_mux.py --rec rec.json --narr narration.md --webm in.webm --out out.mp4 [--rate +0%]
rec.json = {video, t_scene0_ms, timeline:[{scene,start,seconds}], total}
"""
import argparse, asyncio, json, re, subprocess, tempfile, pathlib, os, sys
import numpy as np

SR = 24000
VOICE = os.environ.get('TTS_VOICE', 'zh-CN-XiaoxiaoNeural')

def parse_offset(s):
    s = s.strip()
    m = re.match(r'(\d+):(\d+(?:\.\d+)?)', s)
    if m: return int(m.group(1))*60 + float(m.group(2))
    return 0.0

def parse_narration(path):
    """-> list of (scene_index0, offset_sec, text)."""
    lines = pathlib.Path(path).read_text(encoding='utf-8').splitlines()
    out = []; scene = None
    for ln in lines:
        hm = re.match(r'^##\s*0*(\d+)\s*[·.]', ln)
        if hm:
            scene = int(hm.group(1)) - 1
            continue
        if scene is None: continue
        if not ln.strip().startswith('|'): continue
        cells = [c.strip() for c in ln.strip().strip('|').split('|')]
        if len(cells) < 3: continue
        if cells[0] in ('起点','---') or set(cells[0]) <= set('-:'): continue
        off = parse_offset(cells[0])
        text = cells[2].strip()
        # strip markdown emphasis/code but keep Chinese punctuation
        text = re.sub(r'[*`]', '', text)
        if text and re.search(r'[一-鿿]', text):
            out.append((scene, off, text))
    return out

async def synth(text, mp3):
    import edge_tts
    await edge_tts.Communicate(text, VOICE, rate=RATE).save(mp3)

def mp3_to_pcm(mp3):
    raw = subprocess.run(['ffmpeg','-nostdin','-v','quiet','-i',mp3,'-ac','1','-ar',str(SR),
                          '-f','s16le','-'], capture_output=True).stdout
    return np.frombuffer(raw, dtype='<i2').astype(np.float32)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rec', required=True); ap.add_argument('--narr', required=True)
    ap.add_argument('--webm', required=True); ap.add_argument('--out', required=True)
    ap.add_argument('--rate', default=os.environ.get('TTS_RATE','+0%'))
    a = ap.parse_args()
    global RATE; RATE = a.rate
    rec = json.load(open(a.rec))
    tl = {e['scene']-1: e for e in rec['timeline']}
    t0 = rec['t_scene0_ms']/1000.0
    # video duration
    dur = float(subprocess.run(['ffprobe','-v','quiet','-show_entries','format=duration',
            '-of','csv=p=0', a.webm], capture_output=True, text=True).stdout.strip() or '0')
    track = np.zeros(int((dur+2)*SR), dtype=np.float32)
    items = parse_narration(a.narr)
    tmp = tempfile.mkdtemp()
    placed = overflow = 0
    nxt_by_scene = {}
    for sc, off, text in items:
        if sc not in tl: continue
        abs_s = t0 + tl[sc]['start'] + off
        mp3 = os.path.join(tmp, f'{sc}_{off}.mp3')
        asyncio.run(synth(text, mp3))
        pcm = mp3_to_pcm(mp3)
        i = int(abs_s*SR)
        end = i+len(pcm)
        if end > len(track):
            track = np.concatenate([track, np.zeros(end-len(track)+1, dtype=np.float32)])
        track[i:end] += pcm
        placed += 1
    # normalize to avoid clipping from overlaps
    peak = np.max(np.abs(track)) or 1.0
    track = (track/peak*0.95*32767).astype('<i2')
    wav = os.path.join(tmp,'voice.wav')
    import wave
    with wave.open(wav,'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(track.tobytes())
    # mux
    subprocess.run(['ffmpeg','-nostdin','-y','-i',a.webm,'-i',wav,
        '-c:v','libopenh264','-b:v','10M','-pix_fmt','yuv420p','-r','30','-s','1920x1080',
        '-c:a','aac','-b:a','192k','-map','0:v:0','-map','1:a:0','-shortest', a.out],
        check=True)
    sz = os.path.getsize(a.out)/1e6
    print(f'OK {a.out}  {sz:.1f} MB  voice-lines={placed}  video_dur={dur:.1f}s')

if __name__ == '__main__':
    main()
