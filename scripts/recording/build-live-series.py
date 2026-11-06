#!/usr/bin/env python3
"""Mux narration-timed, verified real UI recording; never repeats a still frame."""
import argparse,hashlib,json,subprocess,sys,tempfile,wave
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'reference/claude_design/tutorials-work'))
from storyboard_video import caption_cues,caption_text,sha

def build(lang,take):
    source=ROOT/('recording/video/series-actions/result-downloads'+('-'+take if take else ''))/lang
    timeline=json.loads((source/'timeline.json').read_text())
    storyboard=json.loads((ROOT/'reference/claude_design/tutorials/series/episodes/result-downloads/storyboard.json').read_text())
    expected=['Open Outputs','Download toxicity report','Downloaded content verified','Open Reproducibility record']
    actions=[e['action'] for e in timeline['events']]
    if not all(a in actions for a in expected):raise ValueError('Missing real workflow actions')
    clips=[]
    for s,t in zip(storyboard['scenes'],timeline['scenes'],strict=True):
        clip=ROOT/f'recording/audio/series/result-downloads/{lang}/step-{s["id"]:03d}.wav'
        receipt=json.loads(clip.with_suffix('.json').read_text());text=s[lang]['narration'];h=hashlib.sha256(text.encode()).hexdigest()
        if h!=t['narrationSha256'] or h!=receipt['narrationSha256'] or sha(clip)!=receipt['audioSha256']:raise ValueError('Stale audio or recorded timing')
        with wave.open(str(clip)) as w:
            if (w.getframerate(),w.getnchannels(),w.getsampwidth())!=(24000,1,2):raise ValueError('Wrong voice format')
            seconds=w.getnframes()/24000+.8
        if abs(seconds-t['seconds'])>.001:raise ValueError('Timing mismatch')
        clips.append({'scene':s['id'],'title':s[lang]['title'],'narration':text,'seconds':seconds,'audio':str(clip),'audioSha256':sha(clip)})
    total=sum(c['seconds'] for c in clips)
    if abs(timeline['duration']-total)>.2:raise ValueError('Capture does not match narration duration')
    raw=source/'raw.webm';raw_seconds=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(raw)]))
    trim=raw_seconds-timeline['duration']
    if trim<0:raise ValueError('Recording shorter than capture timeline')
    out=ROOT/('recording/output/series-live'+('-'+take if take else ''));out.mkdir(parents=True,exist_ok=True);name=f'result-downloads-{lang}-LIVE-REVIEW';destination=out/(name+'.mp4')
    if destination.exists():raise ValueError('Refusing to overwrite a review master')
    with tempfile.TemporaryDirectory(prefix='biomate-live-') as td:
        audio=Path(td)/'voice.wav'
        with wave.open(str(audio),'wb') as w:
            w.setnchannels(1);w.setsampwidth(2);w.setframerate(24000)
            for c in clips:
                with wave.open(c['audio']) as r:w.writeframes(r.readframes(r.getnframes()))
                w.writeframes(b'\0\0'*19200)
        subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-ss',str(trim),'-i',str(raw),'-i',str(audio),'-t',str(total),'-vf','scale=1920:1080:flags=lanczos,format=yuv420p','-r','25','-c:v','libopenh264','-b:v','8M','-af','loudnorm=I=-16:TP=-1.5:LRA=11','-c:a','aac','-b:a','192k','-ar','48000','-ac','2','-movflags','+faststart',str(destination)],check=True)
    cues=caption_cues(clips,lang)
    for ext in ['srt','vtt']:(out/(name+'-captions-DRAFT.'+ext)).write_text(caption_text(cues,vtt=ext=='vtt'))
    (out/(name+'.json')).write_text(json.dumps({'status':'INTERNAL_REVIEW_NOT_RELEASED','visualFormat':'REAL_UI_SCREEN_RECORDING','language':lang,'seconds':total,'videoSha256':sha(destination),'sourceVideoSha256':sha(raw),'trimStartSeconds':trim,'scenes':clips,'events':timeline['events'],'captionTiming':'PROPORTIONAL_DRAFT_REQUIRES_REVIEW'},ensure_ascii=False,indent=2)+'\n')
    at=0;chapters=[]
    for clip in clips:
        chapters.append(f'{int(at)//60:02d}:{int(at)%60:02d} {clip["title"]}');at+=clip['seconds']
    (out/(name+'-chapters.txt')).write_text('\n'.join(chapters)+'\n')
    print(str(destination),flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--language',choices=['en','zh','both'],default='both');p.add_argument('--take',default='v2');a=p.parse_args()
    for lang in (['en','zh'] if a.language=='both' else [a.language]):build(lang,a.take)
