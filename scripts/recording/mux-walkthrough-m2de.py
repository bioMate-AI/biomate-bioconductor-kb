#!/usr/bin/env python3
"""Per-language aligned audio track muxed onto the shared T1 webm.
Adapted from mux-walkthrough-t0.py (audio dirs t1-en / t1-zh, meta t1-shared)."""
import json, sys, pathlib, subprocess, tempfile, wave, struct

SR = 24000
ROOT = pathlib.Path('/Users/kky/biomate-review')
META = json.loads((ROOT/'recording/audio/m2de-shared/record_meta.json').read_text())

def read_pcm(p):
    with wave.open(str(p),'rb') as w:
        assert w.getframerate()==SR, f'{p} {w.getframerate()}Hz != {SR}'
        return w.readframes(w.getnframes()), w.getnframes()
def sil(nframes): return struct.pack('<'+'h'*nframes, *([0]*nframes))

def build(lang):
    audio_dir = ROOT/f'recording/audio/m2de-{lang}'
    tl = META['timeline']
    track = bytearray(); cur = 0
    for i, start_s in enumerate(tl):
        wavp = audio_dir/f'step-{i+1:03d}.wav'
        target = int(start_s*SR)
        if target > cur:
            track.extend(sil(target-cur)); cur = target
        pcm, n = read_pcm(wavp); track.extend(pcm); cur += n
        print(f'  scene {i+1:2d}: start={start_s:6.1f}s dur={n/SR:5.1f}s')
    return bytes(track), cur/SR

def mux(lang, out):
    pcm, dur = build(lang)
    t0 = META['t_scene0_ms']/1000.0
    webm = META['video']
    with tempfile.TemporaryDirectory() as td:
        awav = pathlib.Path(td)/'a.wav'
        with wave.open(str(awav),'wb') as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm)
        out.parent.mkdir(parents=True, exist_ok=True)
        cmd = ['ffmpeg','-y','-i',webm,'-i',str(awav),
               '-filter_complex',f'[0:v]trim=start={t0:.3f},setpts=PTS-STARTPTS[v]',
               '-map','[v]','-map','1:a:0',
               '-c:v','libopenh264','-b:v','10000k','-pix_fmt','yuv420p',
               '-c:a','aac','-b:a','192k','-ar','48000','-ac','2',
               '-movflags','+faststart','-shortest',str(out)]
        print('ffmpeg:',' '.join(cmd))
        subprocess.run(cmd, check=True)
    print(f'{lang}: audio {dur:.1f}s -> {out}')

if __name__=='__main__':
    lang = sys.argv[1]
    out = pathlib.Path(sys.argv[2])
    mux(lang, out)
