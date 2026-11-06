import { useEffect, useRef, useState } from 'react';
import { Mic, Square, Volume2, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { locale } from '@/lib/i18n';

const zh = locale === 'zh';
const labels = {
  speak: zh ? '语音输入' : 'Speak', stop: zh ? '停止' : 'Stop',
  read: zh ? '朗读回复' : 'Read aloud', working: zh ? '正在处理语音…' : 'Processing audio…',
  recording: zh ? '正在录音，点击停止（最长 60 秒）' : 'Recording. Press Stop when finished (up to 60 seconds).',
  review: zh ? '请检查转写内容，尤其是基因名称和样本编号，再发送。' : 'Review the transcript, especially gene names and sample IDs, before sending.',
  notice: zh ? '录音将发送至 ElevenLabs 进行转写；朗读使用 AI 生成语音。' : 'Recordings are sent to ElevenLabs for transcription. Read-aloud uses an AI-generated voice.',
  unavailable: zh ? '语音服务暂时不可用，请使用文字输入。' : 'Voice is unavailable. Please use text for now.',
  microphone: zh ? '无法使用麦克风。请检查浏览器权限。' : 'Microphone unavailable. Check your browser permissions.',
  noSpeech: zh ? '未识别到语音，请重新录制。' : 'No speech detected. Please record again.',
  tooLong: zh ? '此回复过长，无法朗读。请先要求简短总结。' : 'This reply is too long to read aloud. Ask for a short summary first.',
};
let statusRequest: Promise<boolean> | undefined;
let statusCheckedAt = 0;
function useVoiceAvailable() {
  const [available, setAvailable] = useState(false);
  useEffect(() => {
    let mounted = true;
    if (!statusRequest || Date.now() - statusCheckedAt > 60_000) {
      statusCheckedAt = Date.now();
      statusRequest = fetch('/api/voice/status', { credentials: 'include' })
        .then(async r => r.ok && (await r.json()).available === true).catch(() => false);
    }
    statusRequest.then(value => { if (mounted) setAvailable(value); });
    return () => { mounted = false; };
  }, []);
  return available;
}
async function requestVoice(path: string, body: BodyInit, type: string, signal: AbortSignal) {
  const r = await fetch(`/api/voice/${path}`, { method: 'POST', credentials: 'include', headers: { 'Content-Type': type }, body, signal });
  if (!r.ok) { const error = await r.json().catch(() => ({})); throw new Error(error.error === 'voice_no_speech' ? labels.noSpeech : labels.unavailable); }
  return r;
}
export function VoiceInput({ onTranscript, disabled }: { onTranscript: (text: string) => void; disabled?: boolean }) {
  const available = useVoiceAvailable();
  const [state, setState] = useState<'idle' | 'recording' | 'busy'>('idle');
  const [notice, setNotice] = useState('');
  const recorder = useRef<MediaRecorder>();
  const stream = useRef<MediaStream>();
  const abort = useRef<AbortController>();
  const timeout = useRef<ReturnType<typeof setTimeout>>();
  const generation = useRef(0);
  const callback = useRef(onTranscript); callback.current = onTranscript;
  const cleanup = () => {
    generation.current++;
    clearTimeout(timeout.current); abort.current?.abort();
    if (recorder.current && recorder.current.state !== 'inactive') { recorder.current.onstop = null; recorder.current.stop(); }
    stream.current?.getTracks().forEach(track => track.stop());
  };
  useEffect(() => {
    const stop = () => { cleanup(); setState('idle'); };
    window.addEventListener('biomate-live-voice-start', stop);
    return () => { cleanup(); window.removeEventListener('biomate-live-voice-start', stop); };
  }, []);
  useEffect(() => { if (disabled) { cleanup(); setState('idle'); } }, [disabled]);
  async function start() {
    if (state !== 'idle') return;
    window.dispatchEvent(new Event('biomate-batch-voice-start'));
    // Stop any read-aloud before capturing so its audio is not transcribed.
    window.dispatchEvent(new Event('biomate-voice-stop'));
    const id = ++generation.current;
    setNotice(''); setState('busy');
    try {
      if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') throw new Error(labels.microphone);
      const media = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } });
      if (generation.current !== id) { media.getTracks().forEach(track => track.stop()); return; }
      stream.current = media;
      const mimeType = ['audio/webm;codecs=opus', 'audio/mp4', 'audio/ogg;codecs=opus'].find(t => MediaRecorder.isTypeSupported(t));
      const rec = new MediaRecorder(media, mimeType ? { mimeType } : undefined);
      recorder.current = rec;
      const chunks: Blob[] = []; let bytes = 0; let oversized = false;
      rec.ondataavailable = e => { if (e.data.size) { bytes += e.data.size; if (bytes > 6 * 1024 * 1024) { oversized = true; if (rec.state !== 'inactive') rec.stop(); } else chunks.push(e.data); } };
      rec.onerror = () => { cleanup(); setState('idle'); setNotice(labels.microphone); };
      rec.onstop = async () => {
        clearTimeout(timeout.current); media.getTracks().forEach(track => track.stop());
        if (generation.current !== id) return;
        setState('busy');
        const controller = new AbortController(); abort.current = controller;
        try {
          if (oversized) throw new Error(labels.unavailable);
          const audio = new Blob(chunks, { type: rec.mimeType || mimeType || 'audio/webm' });
          if (!audio.size) throw new Error(labels.noSpeech);
          const r = await requestVoice('transcribe', audio, audio.type, controller.signal);
          const result = await r.json();
          if (generation.current === id) { callback.current(result.text); setNotice(labels.review); }
        } catch (error) { if (generation.current === id) setNotice(error instanceof Error ? error.message : labels.unavailable); }
        finally { if (generation.current === id) setState('idle'); }
      };
      rec.start(1000); setState('recording');
      timeout.current = setTimeout(() => { if (rec.state !== 'inactive') rec.stop(); }, 60_000);
    } catch { if (generation.current === id) { cleanup(); setState('idle'); setNotice(labels.microphone); } }
  }
  if (!available) return null;
  return <div className="flex flex-wrap items-center gap-2">
    <Button type="button" variant="ghost" size="sm" disabled={disabled || state === 'busy'} title={labels.notice}
      aria-label={state === 'recording' ? labels.stop : labels.speak} aria-pressed={state === 'recording'}
      onClick={() => state === 'recording' ? recorder.current?.stop() : void start()}>
      {state === 'busy' ? <Loader2 className="h-4 w-4 animate-spin" /> : state === 'recording' ? <Square className="h-4 w-4" /> : <Mic className="h-4 w-4" />}
      <span className="ml-1">{state === 'recording' ? labels.stop : labels.speak}</span>
    </Button>
    <span role="status" className="text-xs text-muted-foreground">{state === 'recording' ? labels.recording : state === 'busy' ? labels.working : notice}</span>
    <span className="w-full text-xs text-muted-foreground">{labels.notice}</span>
  </div>;
}
export function ReadAloud({ text, disabled }: { text: string; disabled?: boolean }) {
  const available = useVoiceAvailable();
  const [state, setState] = useState<'idle' | 'busy' | 'playing'>('idle');
  const [error, setError] = useState('');
  const audio = useRef<HTMLAudioElement>();
  const url = useRef<string>();
  const abort = useRef<AbortController>();
  const stop = () => { abort.current?.abort(); audio.current?.pause(); if (url.current) URL.revokeObjectURL(url.current); url.current = undefined; };
  useEffect(() => {
    const listener = () => { stop(); setState('idle'); };
    window.addEventListener('biomate-voice-stop', listener);
    return () => { stop(); window.removeEventListener('biomate-voice-stop', listener); };
  }, []);
  useEffect(() => { stop(); setState('idle'); }, [text, disabled]);
  async function play() {
    if (state !== 'idle') { stop(); setState('idle'); return; }
    window.dispatchEvent(new Event('biomate-voice-stop'));
    if (text.length > 5000) { setError(labels.tooLong); return; }
    setError(''); setState('busy');
    const controller = new AbortController(); abort.current = controller;
    try {
      const response = await requestVoice('speak', JSON.stringify({ text }), 'application/json', controller.signal);
      const blob = await response.blob();
      if (controller.signal.aborted) return;
      url.current = URL.createObjectURL(blob);
      const player = new Audio(url.current); audio.current = player;
      player.onended = () => { stop(); setState('idle'); };
      player.onerror = () => { stop(); setState('idle'); setError(labels.unavailable); };
      await player.play();
      if (!controller.signal.aborted) setState('playing');
    } catch { if (!controller.signal.aborted) { stop(); setState('idle'); setError(labels.unavailable); } }
  }
  if (!available) return null;
  return <><Button type="button" variant="ghost" size="sm" disabled={disabled} onClick={() => void play()}
    title={zh ? 'ElevenLabs AI 生成语音' : 'AI-generated voice by ElevenLabs'} aria-label={state === 'idle' ? labels.read : labels.stop}>
    {state === 'busy' ? <Loader2 className="h-4 w-4 animate-spin" /> : state === 'playing' ? <Square className="h-4 w-4" /> : <Volume2 className="h-4 w-4" />}
    <span className="ml-1">{state === 'idle' ? labels.read : labels.stop}</span>
  </Button>{error && <span role="status" className="text-xs text-muted-foreground">{error}</span>}</>;
}
