#!/usr/bin/env python3
"""Generate user-authorized Gemini narration from catalog storyboards only.

No credentials, screenshots, source code or client data are sent. Successful
clips are cached by exact text/model/voice hashes. Failures stop the batch.
"""
import argparse,base64,hashlib,json,os,sys,urllib.request,urllib.error,wave
from pathlib import Path
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parents[2]
MODEL='gemini-2.5-flash-preview-tts'
def digest(data):return hashlib.sha256(data).hexdigest()
def synthesize(text,voice):
    key=os.environ.get('GEMINI_API_KEY') or os.environ.get('GOOGLE_API_KEY')
    if not key:raise RuntimeError('Missing Gemini credential')
    body={'contents':[{'parts':[{'text':text}]}], 'generationConfig':{'responseModalities':['AUDIO'],'speechConfig':{'voiceConfig':{'prebuiltVoiceConfig':{'voiceName':voice}}}}}
    req=urllib.request.Request(f'https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent',data=json.dumps(body).encode(),headers={'Content-Type':'application/json','x-goog-api-key':key})
    try:
        with urllib.request.urlopen(req,timeout=150) as r:data=json.load(r)
    except urllib.error.HTTPError as e:
        error=json.loads(e.read()).get('error',{})
        # Do not log request headers, keys or the submitted payload.
        raise RuntimeError(f'Gemini HTTP {e.code}: {error.get("status","unknown")}') from None
    parts=data.get('candidates',[{}])[0].get('content',{}).get('parts',[])
    audio=[p['inlineData'] for p in parts if 'inlineData' in p]
    if len(audio)!=1:raise RuntimeError('Expected exactly one audio response')
    mime=audio[0].get('mimeType','').lower()
    if not mime.startswith('audio/l16') or 'rate=24000' not in mime:raise RuntimeError(f'Unexpected audio format: {mime}')
    pcm=base64.b64decode(audio[0]['data'],validate=True)
    if len(pcm)%2 or len(pcm)<24000:raise RuntimeError('Missing or truncated PCM audio')
    return pcm

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--only',required=True);p.add_argument('--language',choices=['en','zh','both'],default='both');p.add_argument('--voice',default='Aoede');p.add_argument('--limit',type=int)
    args=p.parse_args(); catalog=json.loads((ROOT/'reference/claude_design/tutorials/series/catalog.json').read_text())
    ids=args.only.split(','); byid={e['id']:e for e in catalog['episodes']}
    if set(ids)-byid.keys():p.error('Unknown episode ID')
    generated=0
    for key in ids:
        episode=byid[key];data=json.loads((ROOT/episode['production']['storyboard']).read_text())
        for lang in (['en','zh'] if args.language=='both' else [args.language]):
            out=ROOT/'recording/audio/series'/key/lang;out.mkdir(parents=True,exist_ok=True)
            for scene in data['scenes']:
                text=scene[lang]['narration'];clip=out/f'step-{scene["id"]:03d}.wav';receipt=clip.with_suffix('.json')
                identity={'narrationSha256':digest(text.encode()),'model':MODEL,'voice':args.voice}
                if clip.exists() and receipt.exists():
                    cached=json.loads(receipt.read_text())
                    if all(cached.get(k)==v for k,v in identity.items()) and cached.get('audioSha256')==digest(clip.read_bytes()):
                        print(f'CACHED {key}/{lang}/{clip.name}',flush=True);continue
                print(f'GENERATING {key}/{lang}/{clip.name}',flush=True)
                pcm=synthesize(text,args.voice);temp=clip.with_suffix('.tmp.wav')
                with wave.open(str(temp),'wb') as w:
                    w.setnchannels(1);w.setsampwidth(2);w.setframerate(24000);w.writeframes(pcm)
                temp.replace(clip)
                receipt.write_text(json.dumps({**identity,'audioSha256':digest(clip.read_bytes()),'seconds':len(pcm)/48000,'generatedAt':datetime.now(timezone.utc).isoformat(),'reviewStatus':'UNREVIEWED'},indent=2)+'\n')
                print(f'WROTE {len(pcm)/48000:.2f}s',flush=True);generated+=1
                if args.limit and generated>=args.limit:return
if __name__=='__main__':main()
