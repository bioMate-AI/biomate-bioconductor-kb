#!/usr/bin/env python3
"""
Align per-step narration WAVs against the actual wall-clock moment each tour
step appeared on screen (from step_timestamps.json), trim the raw video to
start at the first step (skips the tour-picker frames), and merge.

Inputs:
  --raw-video        recording/video/<demo>-raw.webm
  --audio-dir        recording/audio/<demo>/                  (contains step-001.wav … step-NNN.wav)
  --timestamps       recording/audio/<demo>/step_timestamps.json
  --out              recording/output/<demo>-tutorial.mp4
  --srt              (optional) burn-in subtitle path

Behaviour:
  - Trim video from t_first_step_ms to end.
  - Build aligned audio track: for each step i, place step-NNN.wav at
    (arrivals[i].t_visible_ms - t_first_step_ms) seconds in the audio timeline.
  - Pad with silence between steps.
  - Output is one MP4, length ≈ video length.
"""
import json, argparse, pathlib, subprocess, tempfile, wave, struct

SAMPLE_RATE = 24000

def read_wav_pcm(p):
    with wave.open(p, 'rb') as w:
        assert w.getframerate() == SAMPLE_RATE, f'{p} not {SAMPLE_RATE}Hz'
        return w.readframes(w.getnframes()), w.getnframes()

def silence_pcm_frames(n_frames):
    return struct.pack('<' + 'h' * n_frames, *([0] * n_frames))

def write_wav(pcm, path):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--raw-video',   required=True)
    ap.add_argument('--audio-dir',   required=True)
    ap.add_argument('--timestamps',  required=True)
    ap.add_argument('--out',         required=True)
    ap.add_argument('--srt',         default=None)
    ap.add_argument('--title',       default=None,
                    help='Use-case title shown at top of every frame')
    args = ap.parse_args()

    ts = json.loads(pathlib.Path(args.timestamps).read_text())
    t0 = ts['t_first_step_ms']
    arrivals = ts['arrivals']
    audio_dir = pathlib.Path(args.audio_dir)

    print(f'First step at t={t0}ms; {len(arrivals)} steps')

    # Build aligned audio track
    track = bytearray()
    current_frames = 0
    for a in arrivals:
        wav_path = audio_dir / f'step-{a["step"]:03d}.wav'
        if not wav_path.exists():
            print(f'  step {a["step"]}: WAV missing ({wav_path})'); continue
        # Target start frame (relative to t0)
        target_ms = a['t_visible_ms'] - t0
        target_frames = int(target_ms * SAMPLE_RATE / 1000)
        if target_frames < current_frames:
            print(f'  step {a["step"]}: WARNING wanted t={target_ms}ms but already at '
                  f'{current_frames*1000/SAMPLE_RATE:.0f}ms — appending immediately')
        else:
            pad = target_frames - current_frames
            track.extend(silence_pcm_frames(pad))
            current_frames += pad
        pcm, n = read_wav_pcm(str(wav_path))
        track.extend(pcm)
        current_frames += n
        print(f'  step {a["step"]:>2}: start={target_ms:>6}ms  dur={n/SAMPLE_RATE*1000:.0f}ms')

    total_s = current_frames / SAMPLE_RATE
    print(f'Aligned audio: {total_s:.1f}s')

    with tempfile.TemporaryDirectory() as td:
        aligned_wav = pathlib.Path(td) / 'aligned.wav'
        write_wav(bytes(track), str(aligned_wav))

        # Build ffmpeg cmd:
        #   - trim video: -ss <t0/1000>
        #   - mix in aligned audio
        #   - optional burn-in subtitles
        t0_s = t0 / 1000.0
        cmd = [
            'ffmpeg', '-y',
            '-ss', f'{t0_s:.3f}', '-i', args.raw_video,
            '-i', str(aligned_wav),
        ]
        # ffmpeg drawtext has a bug where the last character of `text=` is
        # clipped from the rendered glyph (Pango advance-width calc). Workaround:
        # write the text to a sidecar file padded with trailing spaces and use textfile=.
        wm_text_path = pathlib.Path(td) / 'wm.txt'
        wm_text_path.write_text('biomate.ai · contact@biomate.ai   ')
        FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
        FONT_CJK = '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'

        watermark = (
            f"drawtext=textfile={wm_text_path}:fontfile={FONT}:"
            f"fontcolor=yellow:fontsize=22:box=1:boxcolor=black@0.45:"
            f"boxborderw=8:x=w-tw-24:y=h-th-24"
        )

        title_overlay = ""
        if args.title:
            title_path = pathlib.Path(td) / 'title.txt'
            title_path.write_text(args.title + '   ')  # trailing-space workaround
            title_overlay = (
                f"drawtext=textfile={title_path}:fontfile={FONT_CJK}:"
                f"fontcolor=white:fontsize=28:box=1:boxcolor=black@0.55:"
                f"boxborderw=10:x=(w-tw)/2:y=22,"
            )

        vf = title_overlay + watermark
        if args.srt:
            esc = args.srt.replace(':', '\\:')
            vf = (f"subtitles='{esc}':force_style='FontName=Noto Sans CJK SC,"
                  f"FontSize=14,PrimaryColour=&H00FFFFFF,OutlineColour=&H80000000,"
                  f"BorderStyle=3,Outline=1,Shadow=0,Alignment=2,"
                  f"MarginV=60,MarginL=120,MarginR=120',"
                  f"{watermark}")
        cmd += ['-vf', vf]
        cmd += [
            '-map', '0:v:0', '-map', '1:a:0',
            '-c:v', 'libx264', '-preset', 'fast', '-crf', '18',
            '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2',
            '-movflags', '+faststart',   # moov atom at front — required by browsers/QuickTime/etc.
            '-shortest',
            args.out,
        ]
        print('Running ffmpeg merge...')
        subprocess.run(cmd, check=True)

    print(f'Wrote {args.out}')

if __name__ == '__main__':
    main()
