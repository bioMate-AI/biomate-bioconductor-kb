#!/usr/bin/env python3
"""Build a per-language aligned audio track and mux it onto the shared webm.
Each scene i's narration clip (step-(i+1).wav) is placed at timeline[i] seconds
(relative to scene-0-active), silence-padded. Video is trimmed to start at
scene-0-active so audio and visuals share t=0. Encodes with libopenh264 + AAC."""
import json, sys, os, pathlib, subprocess, tempfile, wave, struct

SR = 24000
ROOT = pathlib.Path('/Users/kky/biomate-review')
# Per-language recordings use their own meta (RECORD_META env). Falls back to the
# legacy shared meta for the single-recording pipeline.
_meta_path = os.environ.get('RECORD_META', str(ROOT/'recording/audio/drug-dev-shared/record_meta.json'))
META = json.loads(pathlib.Path(_meta_path).read_text())

def read_pcm(p):
    with wave.open(str(p),'rb') as w:
        if (w.getframerate(), w.getnchannels(), w.getsampwidth()) != (SR, 1, 2):
            raise ValueError(f'{p}: expected 24kHz mono 16-bit PCM')
        return w.readframes(w.getnframes()), w.getnframes()
def sil(nframes): return b'\0\0' * nframes

def build(lang):
    audio_dir = ROOT/f'recording/audio/drug-dev-{lang}'
    tl = META['timeline']                      # scene start seconds (rel scene0)
    if not tl or tl[0] != 0 or any(b <= a for a, b in zip(tl, tl[1:])):
        raise ValueError('Scene timeline must begin at zero and increase strictly')
    expected = {f'step-{i+1:03d}.wav' for i in range(len(tl))}
    if {p.name for p in audio_dir.glob('step-*.wav')} != expected:
        raise ValueError('Narration clip set does not match the scene timeline')
    script = ROOT/f'reference/claude_design/tutorials/narration/drug-dev.{lang}.md'
    track = bytearray(); cur = 0
    for i, start_s in enumerate(tl):
        wavp = audio_dir/f'step-{i+1:03d}.wav'
        if script.exists() and wavp.stat().st_mtime < script.stat().st_mtime:
            raise ValueError(f'{wavp}: narration script changed; regenerate audio')
        target = int(start_s*SR)
        if cur > target:
            raise ValueError(f'Scene {i+1}: previous narration overruns this scene')
        if target > cur:
            track.extend(sil(target-cur)); cur = target
        pcm, n = read_pcm(wavp); track.extend(pcm); cur += n
        end = tl[i+1] if i+1 < len(tl) else META['total_seconds']
        if cur > round(end*SR):
            raise ValueError(f'Scene {i+1}: narration exceeds visual duration')
        print(f'  scene {i+1:2d}: start={start_s:6.1f}s dur={n/SR:5.1f}s')
    total_frames = round(META['total_seconds']*SR)
    track.extend(sil(total_frames-cur))
    return bytes(track), total_frames/SR

def mux(lang, out):
    pcm, dur = build(lang)
    t0 = META['t_scene0_ms']/1000.0
    webm = META['video']
    with tempfile.TemporaryDirectory() as td:
        awav = pathlib.Path(td)/'a.wav'
        with wave.open(str(awav),'wb') as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm)
        out.parent.mkdir(parents=True, exist_ok=True)
        # The system-Chrome screencast renders content at 1920x992 and the
        # recorder pads the bottom 88px gray; crop to the content and re-pad with
        # the page background so the master stays a clean 1920x1080 (no gray band).
        cmd = ['ffmpeg','-y','-i',webm,'-i',str(awav),
               '-filter_complex',f'[0:v]trim=start={t0:.3f},setpts=PTS-STARTPTS,crop=1920:992:0:0,pad=1920:1080:0:0:color=0xFBFCFD[v]',
               '-map','[v]','-map','1:a:0',
               '-c:v','libopenh264','-b:v','6000k','-pix_fmt','yuv420p',
               '-c:a','aac','-b:a','192k','-ar','48000','-ac','2',
               '-movflags','+faststart','-shortest',str(out)]
        print('ffmpeg:',' '.join(cmd))
        subprocess.run(cmd, check=True)
    print(f'{lang}: audio {dur:.1f}s -> {out}')

if __name__=='__main__':
    lang = sys.argv[1]
    out = pathlib.Path(sys.argv[2])
    mux(lang, out)
