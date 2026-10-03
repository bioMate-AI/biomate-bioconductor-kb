"""Regression guards for bilingual batch reporting and stale narration."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
import wave
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'reference/claude_design/tutorials-work'))
import storyboard_video as video
import series_video as series


class SeriesGuards(unittest.TestCase):
    def test_captions_stay_inside_their_scene_and_pause(self):
        scenes=[{'narration':'Inspect the real output. Keep the run record.', 'seconds':10.8},
                {'narration':'核对真实输出。保留运行记录。', 'seconds':8.8}]
        for lang in ['en','zh']:
            cues=video.caption_cues(scenes,lang)
            self.assertEqual(cues[0][0],0)
            self.assertAlmostEqual(cues[-1][1],18.8)
            for start,end,text in cues:
                self.assertGreater(end,start)
                self.assertLessEqual(len(text.splitlines()),2)
                self.assertFalse(start<10.8 and end>10.0)
            self.assertTrue(video.caption_text(cues,True).startswith('WEBVTT'))

    def test_catalog_covers_both_languages_of_every_tutorial(self):
        data=series.load_catalog(series.ROOT/'reference/claude_design/tutorials/series/catalog.json')
        self.assertEqual(sum(e['kind']=='chapter' for e in data['episodes']),28)

    def test_missing_assets_fail_render_and_report_every_edition(self):
        with tempfile.TemporaryDirectory() as td:
            report=Path(td)/'report.json'
            args=['series','--catalog',str(series.ROOT/'reference/claude_design/tutorials/series/catalog.json'),
                  '--action','render','--only','t0-getting-started','--report',str(report)]
            with patch.object(sys,'argv',args), self.assertRaises(SystemExit) as err:
                series.main()
            self.assertEqual(err.exception.code,1)
            result=json.loads(report.read_text())
            self.assertEqual(result['summary'],{'BLOCKED':2})
            self.assertEqual({r['language'] for r in result['editions']},{'en','zh'})

    def test_changed_narration_or_audio_cannot_reuse_receipt(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td); (root/'en-01.png').write_bytes(b'frame')
            text='Reviewed narration.'
            storyboard=root/'storyboard.json'
            storyboard.write_text(json.dumps({'scenes':[{'id':1,'en':{'title':'Title','narration':text}}]}))
            audio=root/'step-001.wav'
            with wave.open(str(audio),'wb') as w:
                w.setparams((1,2,24000,0,'NONE','not compressed'));w.writeframes(b'\1\0'*24000)
            receipt={'narrationSha256':hashlib.sha256(text.encode()).hexdigest(),'audioSha256':video.sha(audio)}
            audio.with_suffix('.json').write_text(json.dumps(receipt))
            self.assertAlmostEqual(video.plan(storyboard,root,'en',root)[0]['seconds'],1.8)
            receipt['narrationSha256']='old'
            audio.with_suffix('.json').write_text(json.dumps(receipt))
            with self.assertRaisesRegex(ValueError,'Stale narration'): video.plan(storyboard,root,'en',root)
            receipt['narrationSha256']=hashlib.sha256(text.encode()).hexdigest();receipt['audioSha256']='old'
            audio.with_suffix('.json').write_text(json.dumps(receipt))
            with self.assertRaisesRegex(ValueError,'Audio hash mismatch'): video.plan(storyboard,root,'en',root)

if __name__=='__main__': unittest.main()
