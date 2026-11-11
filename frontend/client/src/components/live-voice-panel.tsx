import scribeWorkletURL from '@elevenlabs/client/worklets/scribeAudioProcessor.js?url';
import { useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { locale } from '@/lib/i18n';
import type { RealtimeConnection } from '@elevenlabs/client';
const zh = locale === 'zh';
const label = (en: string, cn: string) => zh ? cn : en;
interface Props {
  busy: boolean;
  reply?: { id: string; content: string };
  onSend: (text: string) => void;
}
/** Mounted with the chat ID as key: connection and pending callbacks belong to one chat. */
export function LiveVoicePanel({ busy, reply, onSend }: Props) {
  const [available, setAvailable] = useState(false);
  const [state, setState] = useState<'off' | 'connecting' | 'listening'>('off');
  const [draft, setDraft] = useState('');
  const [partial, setPartial] = useState('');
  const [muted, setMuted] = useState(false);
  const [autoSend, setAutoSend] = useState(false);
  const [notice, setNotice] = useState('');
  const [speaking, setSpeaking] = useState(false);
  const connection = useRef<RealtimeConnection>();
  const generation = useRef(0);
  const abort = useRef<AbortController>();
  const speechAbort = useRef<AbortController>();
  const audio = useRef<HTMLAudioElement>();
  const objectURL = useRef<string>();
  const timer = useRef<ReturnType<typeof setTimeout>>();
  const seenReply = useRef<string>();
  const props = useRef({ busy, onSend, autoSend, muted }); props.current = { busy, onSend, autoSend, muted };
  const draftRef = useRef(draft); draftRef.current = draft;
  const awaiting = useRef(false);
  const wasBusy = useRef(busy);
  useEffect(() => { if (wasBusy.current && !busy) awaiting.current = false; wasBusy.current = busy; }, [busy]);
  function stopAudio() {
    speechAbort.current?.abort();
    const player = audio.current; audio.current = undefined;
    if (player) { player.onended = null; player.onerror = null; player.pause(); }
    if (objectURL.current) URL.revokeObjectURL(objectURL.current);
    objectURL.current = undefined;
  }
  function teardown() {
    generation.current++; clearTimeout(timer.current); abort.current?.abort();
    const current = connection.current; connection.current = undefined; current?.close(); stopAudio();
  }
  function end() { teardown(); setState('off'); setMuted(false); setPartial(''); setSpeaking(false); awaiting.current = false; }
  useEffect(() => {
    const controller = new AbortController();
    fetch('/api/voice/status', { credentials: 'include', signal: controller.signal })
      .then(r => r.ok ? r.json() : { liveAvailable: false }).then(data => setAvailable(data.liveAvailable === true)).catch(() => {});
    return () => { controller.abort(); teardown(); };
  }, []);
  useEffect(() => {
    const hide = () => { if (document.hidden) end(); };
    const stop = () => { stopAudio(); setSpeaking(false); };
    document.addEventListener('visibilitychange', hide);
    const otherInput = () => end();
    window.addEventListener('biomate-batch-voice-start', otherInput);
    window.addEventListener('biomate-voice-stop', stop);
    return () => { document.removeEventListener('visibilitychange', hide); window.removeEventListener('biomate-batch-voice-start', otherInput); window.removeEventListener('biomate-voice-stop', stop); };
  }, []);
  useEffect(() => {
    if (state !== 'listening' || busy || !reply || reply.id === seenReply.current) return;
    seenReply.current = reply.id; awaiting.current = false;
    if (!reply.content.trim()) return;
    if (reply.content.length > 5000) { setNotice(label('Reply is ready on screen. Ask for a short spoken summary.', '回复已显示。可要求简短总结后朗读。')); return; }
    const id = generation.current;
    window.dispatchEvent(new Event('biomate-voice-stop'));
    const controller = new AbortController(); speechAbort.current = controller;
    (async () => {
      try {
        const r = await fetch('/api/voice/speak', { method: 'POST', credentials: 'include', signal: controller.signal,
          headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text: reply.content }) });
        if (!r.ok) throw new Error('Speech unavailable');
        const blob = await r.blob();
        if (generation.current !== id || controller.signal.aborted) return;
        objectURL.current = URL.createObjectURL(blob);
        const player = new Audio(objectURL.current); audio.current = player;
        player.onended = () => { if (generation.current === id) { stopAudio(); setSpeaking(false); } };
        player.onerror = () => { if (generation.current === id) { stopAudio(); setSpeaking(false); setNotice(label('Audio could not play. Your reply is on screen.', '无法播放语音，请查看文字回复。')); } };
        await player.play();
        if (!controller.signal.aborted) setSpeaking(true);
      } catch { if (!controller.signal.aborted && generation.current === id) { stopAudio(); setSpeaking(false); setNotice(label('Audio unavailable. Your reply is on screen.', '语音暂不可用，请查看文字回复。')); } }
    })();
    return () => { stopAudio(); };
  }, [busy, reply?.id, reply?.content, state]);
  async function start() {
    if (state !== 'off') return;
    window.dispatchEvent(new Event('biomate-live-voice-start'));
    setState('connecting'); setNotice(''); seenReply.current = reply?.id;
    const id = ++generation.current;
    const controller = new AbortController(); abort.current = controller;
    try {
      const { Scribe, CommitStrategy, RealtimeEvents } = await import('@elevenlabs/client');
      if (generation.current !== id) return;
      const response = await fetch('/api/voice/live-token', { method: 'POST', credentials: 'include', signal: controller.signal });
      if (!response.ok) throw new Error('Unavailable');
      const { token } = await response.json();
      if (generation.current !== id) return;
      const live = Scribe.connect({ token, modelId: 'scribe_v2_realtime', commitStrategy: CommitStrategy.VAD,
        vadSilenceThresholdSecs: 1.5, microphone: { echoCancellation: true, noiseSuppression: true, workletPaths: { scribeAudioProcessor: scribeWorkletURL } } });
      connection.current = live;
      live.on(RealtimeEvents.SESSION_STARTED, () => { if (generation.current === id) setState('listening'); });
      live.on(RealtimeEvents.PARTIAL_TRANSCRIPT, event => {
        if (generation.current !== id || props.current.muted) return;
        setPartial(event.text);
        if (event.text.trim()) { window.dispatchEvent(new Event('biomate-voice-stop')); }
      });
      live.on(RealtimeEvents.COMMITTED_TRANSCRIPT, event => {
        if (generation.current !== id || props.current.muted || !event.text.trim()) return;
        setPartial('');
        if (props.current.autoSend && !props.current.busy && !awaiting.current && !draftRef.current.trim()) {
          awaiting.current = true; props.current.onSend(event.text.trim());
        } else setDraft(text => text ? `${text}\n${event.text.trim()}` : event.text.trim());
      });
      const failed = () => { if (generation.current === id) { end(); setNotice(label('Voice disconnected. Your draft is kept; reconnect to continue.', '语音连接已断开。草稿已保留，请重新连接。')); } };
      live.on(RealtimeEvents.ERROR, failed); live.on(RealtimeEvents.AUTH_ERROR, failed); live.on(RealtimeEvents.CLOSE, failed);
      // UI session cap is a usability bound, not a server-enforced billing quota.
      timer.current = setTimeout(() => { if (generation.current === id) { end(); setNotice(label('Voice session ended after five minutes. Start again to continue.', '五分钟语音会话已结束，可重新开始。')); } }, 5 * 60_000);
    } catch { if (generation.current === id) { end(); setNotice(label('Could not start voice. Check microphone access and try again.', '无法启动语音。请检查麦克风权限后重试。')); } }
  }
  if (!available) return null;
  return <section aria-label={label('Live voice conversation', '实时语音对话')} className="max-w-[660px] mx-auto mb-3 rounded-lg border p-3 space-y-2">
    <div className="flex gap-2 items-center flex-wrap">
      {state === 'off' ? <Button type="button" variant="outline" onClick={() => void start()}>{label('Start voice', '开始语音')}</Button>
        : <><Button type="button" variant="outline" onClick={end}>{label('End voice', '结束语音')}</Button>
          <Button type="button" variant="ghost" disabled={state === 'connecting'} aria-pressed={muted} onClick={() => {
            try { muted ? connection.current?.unmute() : connection.current?.mute(); setMuted(!muted); setPartial(''); }
            catch { end(); setNotice(label('Microphone unavailable. Please reconnect.', '麦克风不可用，请重新连接。')); }
          }}>{muted ? label('Unmute', '取消静音') : label('Mute', '静音')}</Button></>}
      {speaking && <Button type="button" variant="ghost" onClick={() => { stopAudio(); setSpeaking(false); }}>{label('Stop speaking', '停止朗读')}</Button>}
      <span role="status" className="text-sm">{state === 'connecting' ? label('Connecting…', '连接中…') : state === 'listening' ? muted ? label('Muted', '已静音') : label('Listening', '正在聆听') : ''}</span>
    </div>
    <label className="flex gap-2 text-sm items-center"><input type="checkbox" checked={autoSend} onChange={e => setAutoSend(e.target.checked)} />{label('Hands-free: send when I pause', '免手动模式：停顿后自动发送')}</label>
    <p className="text-xs text-muted-foreground">{label('Audio is sent to ElevenLabs. Replies use an AI-generated voice. Review scientific names and settings before running an analysis. Use headphones to reduce echo.', '音频将发送至 ElevenLabs，回复使用 AI 生成语音。运行分析前请核对科学名称和设置。建议使用耳机减少回声。')}</p>
    {partial && <p aria-live="polite" className="text-sm text-muted-foreground">{partial}</p>}
    {draft && <><textarea aria-label={label('Voice draft', '语音草稿')} className="w-full rounded border p-2 text-sm" value={draft} onChange={e => setDraft(e.target.value)} />
      <Button type="button" disabled={busy || !draft.trim()} onClick={() => { awaiting.current = true; onSend(draft.trim()); setDraft(''); }}>{label('Send reviewed text', '发送已核对文字')}</Button></>}
    {notice && <p role="alert" className="text-sm">{notice}</p>}
  </section>;
}
