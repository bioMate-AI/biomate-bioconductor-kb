#!/usr/bin/env python3
"""Decode narrated review masters and measure audio; never grants release approval."""
import argparse,hashlib,json,math,re,subprocess
from pathlib import Path

def audit(path):
    manifest=json.loads(path.with_suffix('.json').read_text())
    failures=[]
    if hashlib.sha256(path.read_bytes()).hexdigest()!=manifest['videoSha256']:failures.append('MP4 differs from render receipt')
    probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
    video=next(s for s in probe['streams'] if s['codec_type']=='video');audio=next(s for s in probe['streams'] if s['codec_type']=='audio')
    duration=float(probe['format']['duration'])
    if abs(duration-manifest['seconds'])>.2:failures.append('Duration mismatch')
    if (video['width'],video['height'],video['codec_name'])!=(1920,1080,'h264'):failures.append('Video format mismatch')
    if (audio['codec_name'],audio['sample_rate'],audio['channels'])!=('aac','48000',2):failures.append('Audio format mismatch')
    decoded=subprocess.run(['ffmpeg','-hide_banner','-v','info','-i',str(path),'-af','loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json','-f','null','-'],capture_output=True,text=True)
    if decoded.returncode:raise RuntimeError(decoded.stderr[-2000:])
    measurement=json.loads(decoded.stderr[decoded.stderr.rfind('{'):])
    loudness=float(measurement['input_i']);peak=float(measurement['input_tp'])
    if not math.isfinite(loudness) or abs(loudness+16)>1.5:failures.append('Loudness outside review target')
    if not math.isfinite(peak) or peak>-.9:failures.append('True peak outside review target')
    motion=None
    if manifest.get('visualFormat')=='REAL_UI_SCREEN_RECORDING':
        decoded_frames=subprocess.check_output(['ffmpeg','-hide_banner','-loglevel','error','-i',str(path),'-an','-vf',"scale=320:180,select='gt(scene,0.015)'",'-vsync','vfr','-f','framemd5','-'],text=True)
        hashes=[line.split(',')[-1].strip() for line in decoded_frames.splitlines() if line and not line.startswith('#')]
        motion={'significantSceneChanges':len(hashes),'distinctChangedFrames':len(set(hashes)),'recordedEvents':len(manifest.get('events',[]))}
        if motion['significantSceneChanges']<6 or motion['recordedEvents']<10:failures.append('Insufficient evidence of recorded actions or changing frames')
    cps=[]
    for s in manifest['scenes']:
        cps.append(round(len(s['narration'])/(s['seconds']-.8),1))
    return {'motionCheck':motion,'file':str(path),'seconds':duration,'integratedLUFS':loudness,'truePeakDBTP':peak,
      'sceneCharactersPerSecond':cps,'technicalChecksPassed':not failures,'failures':failures,
      'releaseStatus':'HOLD: pronunciation, caption alignment, editorial and final visual review required'}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--directory',required=True);p.add_argument('--report',required=True);a=p.parse_args()
    files=sorted(set(Path(a.directory).rglob('*-NARRATED-REVIEW.mp4')) | set(Path(a.directory).rglob('*-LIVE-REVIEW.mp4')))
    if not files:raise SystemExit('No narrated masters found')
    rows=[audit(f) for f in files];Path(a.report).write_text(json.dumps(rows,indent=2)+'\n')
    print(json.dumps({'masters':len(rows),'technicalPasses':sum(r['technicalChecksPassed'] for r in rows),'releaseApproved':0}))
    if any(not r['technicalChecksPassed'] for r in rows):raise SystemExit(1)
if __name__=='__main__':main()
