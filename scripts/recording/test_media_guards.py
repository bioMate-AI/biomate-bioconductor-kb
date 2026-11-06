"""Prevent silent TTS failures and narration/scene drift from reaching a render."""
import importlib.util
import pathlib
import tempfile
import unittest
import wave
from unittest.mock import patch

HERE = pathlib.Path(__file__).parent


def module(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + '.py'))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


class MediaGuards(unittest.TestCase):
    def test_failed_gemini_never_becomes_silence(self):
        m = module('gemini-tts')
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td); n = p / 'n.md'; n.write_text('## Step 1 — Title\n\nReal narration.\n')
            with patch('sys.argv', ['tts', '--narration', str(n), '--out', str(p/'out')]), patch.object(m, 'tts', side_effect=RuntimeError('provider error')):
                with self.assertRaisesRegex(RuntimeError, 'render aborted'): m.main()
            self.assertFalse((p/'out/step-001.wav').exists())
            self.assertFalse((p/'out/timing.json').exists())

    def test_failed_edge_never_becomes_silence(self):
        m = module('edge-tts-gen')
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td); n = p / 'n.md'; n.write_text('## Step 1 — Title\n\nReal narration.\n')
            with patch('sys.argv', ['tts', '--narration', str(n), '--out', str(p/'out')]), patch.object(m, 'to_wav', side_effect=RuntimeError('provider error')):
                with self.assertRaisesRegex(RuntimeError, 'render aborted'): m.main()
            self.assertFalse((p/'out/step-001.wav').exists())

    def test_overlong_clip_is_rejected(self):
        self.check_mux(2, 1, raises=True)

    def test_short_clip_keeps_last_scene_hold(self):
        self.check_mux(1, 3, raises=False)

    def check_mux(self, duration, scene_duration, raises):
        m = module('mux-walkthrough')
        with tempfile.TemporaryDirectory() as td:
            m.ROOT = pathlib.Path(td); m.META = {'timeline': [0], 'total_seconds': scene_duration}
            folder=m.ROOT/'recording/audio/drug-dev-en'; folder.mkdir(parents=True)
            with wave.open(str(folder/'step-001.wav'), 'wb') as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); w.writeframes(b'\1\0' * (24000*duration))
            if raises:
                with self.assertRaisesRegex(ValueError, 'exceeds visual duration'): m.build('en')
            else:
                pcm, seconds=m.build('en'); self.assertEqual(seconds, scene_duration); self.assertEqual(len(pcm), 48000*scene_duration)


if __name__ == '__main__': unittest.main()
