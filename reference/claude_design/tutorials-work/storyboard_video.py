"""Local storyboard assembly for make_video.py. Never calls a speech service.

Narration mode requires step-NNN.wav + step-NNN.json containing narrationSha256.
Silent previews are explicitly named and watermarked by the reviewed source deck.
"""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path
import subprocess
import tempfile
import textwrap
import wave


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for b in iter(lambda: f.read(1024 * 1024), b''):
            h.update(b)
    return h.hexdigest()


def plan(storyboard, frames, lang, audio=None, silent=False, hold=6.0):
    data = json.loads(Path(storyboard).read_text())
    scenes = data['scenes']
    if not scenes or [s['id'] for s in scenes] != list(range(1, len(scenes)+1)):
        raise ValueError('Scene IDs must be sequential, starting at one')
    if not math.isfinite(hold) or hold <= 0:
        raise ValueError('Preview hold must be finite and positive')
    result = []
    for s in scenes:
        text = s[lang]['narration']
        if not text.strip():
            raise ValueError(f'Empty narration: scene {s["id"]}')
        frame = Path(frames) / f'{lang}-{s["id"]:02d}.png'
        if not frame.is_file():
            raise ValueError(f'Missing reviewed frame: {frame}')
        item = {'scene': s['id'], 'title': s[lang]['title'], 'frame': str(frame.resolve()),
                'frameSha256': sha(frame), 'narration': text, 'seconds': hold}
        if not silent:
            if audio is None:
                raise ValueError('Narration required. Use --silent-preview only for a review draft.')
            clip = Path(audio) / f'step-{s["id"]:03d}.wav'
            receipt = clip.with_suffix('.json')
            if not clip.is_file() or not receipt.is_file():
                raise ValueError(f'Missing narration or receipt: {clip}')
            proof = json.loads(receipt.read_text())
            if proof.get('narrationSha256') != hashlib.sha256(text.encode()).hexdigest():
                raise ValueError(f'Stale narration: {clip}')
            if proof.get('audioSha256') != sha(clip):
                raise ValueError(f'Audio hash mismatch: {clip}')
            with wave.open(str(clip)) as w:
                if (w.getframerate(), w.getnchannels(), w.getsampwidth()) != (24000, 1, 2):
                    raise ValueError('Narration must be 24kHz mono 16-bit PCM')
                duration = w.getnframes()/24000
                if duration < 0.5:
                    raise ValueError(f'Narration too short: {clip}')
            item.update(audio=str(clip.resolve()), audioSha256=sha(clip), seconds=duration+0.8)
        result.append(item)
    return result


def caption_cues(scenes, lang):
    """Draft sentence/phrase captions. Timing is proportional, not forced alignment."""
    cues=[]; offset=0.0
    for scene in scenes:
        text=scene['narration']
        sentences=re.split(r'(?<=[.!?。！？])\s*',text)
        chunks=[]
        for sentence in sentences:
            if not sentence.strip():continue
            width=32 if lang=='zh' else 76
            chunks.extend(textwrap.wrap(sentence,width=width,break_long_words=True,break_on_hyphens=False))
        duration=scene['seconds']-0.8
        weights=[len(c) for c in chunks]; total=sum(weights); elapsed=0.0
        for chunk,weight in zip(chunks,weights):
            end=elapsed+duration*weight/total
            wrapped='\n'.join(textwrap.wrap(chunk,width=16 if lang=='zh' else 38,break_long_words=True,break_on_hyphens=False))
            cues.append((offset+elapsed,offset+end,wrapped));elapsed=end
        offset+=scene['seconds']
    return cues


def caption_text(cues, vtt=False):
    def stamp(t):
        ms=round(t*1000); hours,ms=divmod(ms,3600000);minutes,ms=divmod(ms,60000);seconds,ms=divmod(ms,1000)
        return f'{hours:02d}:{minutes:02d}:{seconds:02d}{"." if vtt else ","}{ms:03d}'
    return ('WEBVTT\n\n' if vtt else '')+'\n\n'.join(f'{i+1}\n{stamp(start)} --> {stamp(end)}\n{text}' for i,(start,end,text) in enumerate(cues))+'\n'


def build(args, lang):
    audio = Path(args.audio_root) / lang if args.audio_root else None
    scenes = plan(args.storyboard, args.frames_dir, lang, audio, args.silent_preview, args.hold)
    out = Path(args.out_dir); out.mkdir(parents=True, exist_ok=True)
    data = json.loads(Path(args.storyboard).read_text())
    key = data.get('id', '')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]*', key):
        raise ValueError('Storyboard requires a safe lowercase id')
    name = f'{key}-{lang}-' + ('SILENT-REVIEW' if args.silent_preview else 'NARRATED-REVIEW')
    destination = out / (name + '.mp4')
    if destination.exists() and not args.overwrite:
        raise ValueError(f'Output exists: {destination}; specify --overwrite intentionally')
    total = sum(s['seconds'] for s in scenes)
    with tempfile.TemporaryDirectory(prefix='biomate-storyboard-') as td:
        tmp = Path(td); concat = tmp/'frames.txt'
        # Copy references into our temp directory as safe numeric filenames.
        for i, s in enumerate(scenes):
            (tmp/f'{i:03d}.png').symlink_to(s['frame'])
        concat.write_text(''.join(f"file '{i:03d}.png'\nduration {s['seconds']:.6f}\n" for i,s in enumerate(scenes)) + f"file '{len(scenes)-1:03d}.png'\n")
        cmd = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', str(concat)]
        if not args.silent_preview:
            with wave.open(str(tmp/'narration.wav'), 'wb') as track:
                track.setnchannels(1); track.setsampwidth(2); track.setframerate(24000)
                for s in scenes:
                    with wave.open(s['audio']) as clip:
                        track.writeframes(clip.readframes(clip.getnframes()))
                    track.writeframes(b'\0\0'*19200)
            cmd += ['-i', str(tmp/'narration.wav')]
        cmd += ['-vf', 'scale=1920:1080:flags=lanczos,format=yuv420p', '-r', '25',
                '-c:v', args.encoder, '-b:v', '6M', '-t', f'{total:.6f}', '-movflags', '+faststart']
        if not args.silent_preview:
            cmd += ['-af', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2']
        # Encode to temporary output; never leave a broken final MP4 after failure.
        temporary = tmp/'render.mp4'
        subprocess.run(cmd+[str(temporary)], check=True)
        probe = json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(temporary)]))
        video = next(s for s in probe['streams'] if s['codec_type']=='video')
        if (video['width'],video['height']) != (1920,1080) or abs(float(probe['format']['duration'])-total)>0.2:
            raise ValueError('Rendered dimensions or duration failed verification')
        has_audio = any(s['codec_type']=='audio' for s in probe['streams'])
        if has_audio == args.silent_preview:
            raise ValueError('Unexpected audio stream state')
        import shutil
        shutil.copyfile(temporary, destination)
    if not args.silent_preview:
        cues = caption_cues(scenes, lang)
        (out/(name+'-captions-DRAFT.srt')).write_text(caption_text(cues))
        (out/(name+'-captions-DRAFT.vtt')).write_text(caption_text(cues, vtt=True))
    receipt = {'visualFormat':'STATIC_STORYBOARD_NOT_ACTION_TUTORIAL', 'captionTiming':None if args.silent_preview else 'PROPORTIONAL_DRAFT_REQUIRES_REVIEW', 'audioLoudnessTargetLUFS':None if args.silent_preview else -16, 'status':'INTERNAL_REVIEW_NOT_RELEASED','silent':args.silent_preview,'language':lang,
               'storyboardSha256':sha(args.storyboard),'seconds':total,'videoSha256':sha(destination),'scenes':scenes}
    (out/(name+'.json')).write_text(json.dumps(receipt,ensure_ascii=False,indent=2))
    start=0; chapters=[]
    for s in scenes:
        chapters.append(f'{int(start)//60:02d}:{int(start)%60:02d} {s["title"]}')
        start += s['seconds']
    (out/(name+'-chapters.txt')).write_text('\n'.join(chapters)+'\n')
    print(f'{destination} ({total:.1f}s; internal review only)', flush=True)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--storyboard',required=True);p.add_argument('--frames-dir',required=True)
    p.add_argument('--out-dir',required=True);p.add_argument('--audio-root')
    p.add_argument('--language',choices=['en','zh','both'],default='both')
    p.add_argument('--silent-preview',action='store_true');p.add_argument('--hold',type=float,default=6)
    p.add_argument('--encoder',default='libopenh264');p.add_argument('--overwrite',action='store_true')
    args=p.parse_args()
    for lang in (['en','zh'] if args.language=='both' else [args.language]):
        build(args,lang)


if __name__=='__main__': main()
