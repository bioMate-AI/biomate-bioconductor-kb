import scribeWorkletURL from '@elevenlabs/client/worklets/scribeAudioProcessor.js?url';
import { useEffect, useRef, useState } from 'react';
import { AudioLines, MicOff, Loader2, VolumeX } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useVoiceSettings } from '@/hooks/use-voice-settings';
import { composerVoiceIconStyle } from '@/components/voice-controls';
import { locale } from '@/lib/i18n';
import type { RealtimeConnection } from '@elevenlabs/client';

const zh = locale === 'zh';
const label = (en: string, cn: string) => zh ? cn : en;

interface Props {
  busy: boolean;
  reply?: { id: string; content: string };
  onSend: (text: string) => void;
  /** Append reviewed live transcript into the composer (non–hands-free). */
  onTranscript?: (text: string) => void;
}

const hint = label(
  'Live voice. Audio goes to ElevenLabs; replies use an AI voice. Review gene names before sending. Prefer headphones to reduce echo.',
  '实时语音。音频发送至 ElevenLabs，回复使用 AI 语音。发送前请核对基因名称。建议使用耳机减少回声。',
);

/** Compact live-voice control for the composer toolbar. Gated by Settings → Chat → Voice. */
export function LiveVoicePanel({ busy, reply, onSend, onTranscript }: Props) {
  const { voiceEnabled, voiceHandsFree } = useVoiceSettings();
  const { toast } = useToast();
  const [available, setAvailable] = useState(false);
  const [state, setState] = useState<'off' | 'connecting' | 'listening'>('off');
  const [partial, setPartial] = useState('');
  const [muted, setMuted] = useState(false);
  const [speaking, setSpeaking] = useState(false);
  const connection = useRef<RealtimeConnection>();
  const generation = useRef(0);
  const abort = useRef<AbortController>();
  const speechAbort = useRef<AbortController>();
  const audio = useRef<HTMLAudioElement>();
  const objectURL = useRef<string>();
  const timer = useRef<ReturnType<typeof setTimeout>>();
  const seenReply = useRef<string>();
  const props = useRef({ busy, onSend, onTranscript, autoSend: voiceHandsFree, muted });
  props.current = { busy, onSend, onTranscript, autoSend: voiceHandsFree, muted };
  const awaiting = useRef(false);
  const wasBusy = useRef(busy);

  useEffect(() => {
    if (wasBusy.current && !busy) awaiting.current = false;
    wasBusy.current = busy;
  }, [busy]);

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

  function end() {
    teardown(); setState('off'); setMuted(false); setPartial(''); setSpeaking(false); awaiting.current = false;
  }

  function notice(message: string, destructive = false) {
    toast({ title: message, variant: destructive ? 'destructive' : 'default' });
  }

  useEffect(() => {
    const controller = new AbortController();
    fetch('/api/voice/status', { credentials: 'include', signal: controller.signal })
      .then(r => r.ok ? r.json() : { liveAvailable: false })
      .then(data => setAvailable(data.liveAvailable === true))
      .catch(() => {});
    return () => { controller.abort(); teardown(); };
  }, []);

  useEffect(() => {
    const hide = () => { if (document.hidden) end(); };
    const stop = () => { stopAudio(); setSpeaking(false); };
    document.addEventListener('visibilitychange', hide);
    const otherInput = () => end();
    window.addEventListener('biomate-batch-voice-start', otherInput);
    window.addEventListener('biomate-voice-stop', stop);
    return () => {
      document.removeEventListener('visibilitychange', hide);
      window.removeEventListener('biomate-batch-voice-start', otherInput);
      window.removeEventListener('biomate-voice-stop', stop);
    };
  }, []);

  useEffect(() => {
    if (state !== 'listening' || busy || !reply || reply.id === seenReply.current) return;
    seenReply.current = reply.id; awaiting.current = false;
    if (!reply.content.trim()) return;
    if (reply.content.length > 5000) {
      notice(label('Reply is ready on screen. Ask for a short spoken summary.', '回复已显示。可要求简短总结后朗读。'));
      return;
    }
    const id = generation.current;
    window.dispatchEvent(new Event('biomate-voice-stop'));
    const controller = new AbortController(); speechAbort.current = controller;
    (async () => {
      try {
        const r = await fetch('/api/voice/speak', {
          method: 'POST', credentials: 'include', signal: controller.signal,
          headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text: reply.content }),
        });
        if (!r.ok) throw new Error('Speech unavailable');
        const blob = await r.blob();
        if (generation.current !== id || controller.signal.aborted) return;
        objectURL.current = URL.createObjectURL(blob);
        const player = new Audio(objectURL.current); audio.current = player;
        player.onended = () => { if (generation.current === id) { stopAudio(); setSpeaking(false); } };
        player.onerror = () => {
          if (generation.current === id) {
            stopAudio(); setSpeaking(false);
            notice(label('Audio could not play. Your reply is on screen.', '无法播放语音，请查看文字回复。'));
          }
        };
        await player.play();
        if (!controller.signal.aborted) setSpeaking(true);
      } catch {
        if (!controller.signal.aborted && generation.current === id) {
          stopAudio(); setSpeaking(false);
          notice(label('Audio unavailable. Your reply is on screen.', '语音暂不可用，请查看文字回复。'));
        }
      }
    })();
    return () => { stopAudio(); };
  }, [busy, reply?.id, reply?.content, state]);

  async function start() {
    if (state !== 'off') return;
    window.dispatchEvent(new Event('biomate-live-voice-start'));
    setState('connecting'); seenReply.current = reply?.id;
    const id = ++generation.current;
    const controller = new AbortController(); abort.current = controller;
    try {
      const { Scribe, CommitStrategy, RealtimeEvents } = await import('@elevenlabs/client');
      if (generation.current !== id) return;
      const response = await fetch('/api/voice/live-token', { method: 'POST', credentials: 'include', signal: controller.signal });
      if (!response.ok) throw new Error('Unavailable');
      const { token } = await response.json();
      if (generation.current !== id) return;
      const live = Scribe.connect({
        token, modelId: 'scribe_v2_realtime', commitStrategy: CommitStrategy.VAD,
        vadSilenceThresholdSecs: 1.5,
        microphone: {
          echoCancellation: true, noiseSuppression: true,
          workletPaths: { scribeAudioProcessor: scribeWorkletURL },
        },
      });
      connection.current = live;
      live.on(RealtimeEvents.SESSION_STARTED, () => { if (generation.current === id) setState('listening'); });
      live.on(RealtimeEvents.PARTIAL_TRANSCRIPT, event => {
        if (generation.current !== id || props.current.muted) return;
        setPartial(event.text);
        if (event.text.trim()) window.dispatchEvent(new Event('biomate-voice-stop'));
      });
      live.on(RealtimeEvents.COMMITTED_TRANSCRIPT, event => {
        if (generation.current !== id || props.current.muted || !event.text.trim()) return;
        setPartial('');
        const text = event.text.trim();
        if (props.current.autoSend && !props.current.busy && !awaiting.current) {
          awaiting.current = true;
          props.current.onSend(text);
        } else {
          props.current.onTranscript?.(text);
        }
      });
      const failed = () => {
        if (generation.current === id) {
          end();
          notice(label('Voice disconnected. Reconnect to continue.', '语音连接已断开。请重新连接。'), true);
        }
      };
      live.on(RealtimeEvents.ERROR, failed);
      live.on(RealtimeEvents.AUTH_ERROR, failed);
      live.on(RealtimeEvents.CLOSE, failed);
      // UI session cap is a usability bound, not a server-enforced billing quota.
      timer.current = setTimeout(() => {
        if (generation.current === id) {
          end();
          notice(label('Voice session ended after five minutes. Start again to continue.', '五分钟语音会话已结束，可重新开始。'));
        }
      }, 5 * 60_000);
    } catch {
      if (generation.current === id) {
        end();
        notice(label('Could not start voice. Check microphone access and try again.', '无法启动语音。请检查麦克风权限后重试。'), true);
      }
    }
  }

  if (!voiceEnabled || !available) return null;

  const active = state !== 'off';
  const statusText = state === 'connecting'
    ? label('Connecting…', '连接中…')
    : state === 'listening'
      ? (muted ? label('Muted', '已静音') : label('Listening', '正在聆听'))
      : '';

  return (
    <span
      className="inline-flex items-center gap-0.5"
      aria-label={label('Live voice conversation', '实时语音对话')}
      data-testid="composer-voice-live"
      data-voice-state={state}
    >
      <button
        type="button"
        title={active ? `${statusText || label('End voice', '结束语音')}. ${hint}` : `Start voice. ${hint}`}
        aria-label={state === 'off' ? label('Start voice', '开始语音') : label('End voice', '结束语音')}
        aria-pressed={active}
        onClick={() => { if (state === 'off') void start(); else end(); }}
        style={{
          ...composerVoiceIconStyle,
          color: active ? 'var(--bm-accent, oklch(0.45 0.14 245))' : composerVoiceIconStyle.color,
          background: active ? 'var(--bm-accent-soft, oklch(0.93 0.03 245))' : 'transparent',
        }}
      >
        {state === 'connecting'
          ? <Loader2 className="h-4 w-4 animate-spin" />
          : <AudioLines className="h-4 w-4" />}
      </button>
      {state === 'listening' && (
        <button
          type="button"
          title={muted ? label('Unmute', '取消静音') : label('Mute', '静音')}
          aria-label={muted ? label('Unmute', '取消静音') : label('Mute', '静音')}
          aria-pressed={muted}
          onClick={() => {
            try {
              muted ? connection.current?.unmute() : connection.current?.mute();
              setMuted(!muted);
              setPartial('');
            } catch {
              end();
              notice(label('Microphone unavailable. Please reconnect.', '麦克风不可用，请重新连接。'), true);
            }
          }}
          style={composerVoiceIconStyle}
        >
          <MicOff className="h-3.5 w-3.5" />
        </button>
      )}
      {speaking && (
        <button
          type="button"
          title={label('Stop speaking', '停止朗读')}
          aria-label={label('Stop speaking', '停止朗读')}
          onClick={() => { stopAudio(); setSpeaking(false); }}
          style={composerVoiceIconStyle}
        >
          <VolumeX className="h-3.5 w-3.5" />
        </button>
      )}
      <span role="status" className="sr-only">{statusText}{partial ? ` ${partial}` : ''}</span>
      {partial && !muted && (
        <span aria-live="polite" className="max-w-[120px] truncate text-xs text-muted-foreground" title={partial}>
          {partial}
        </span>
      )}
    </span>
  );
}
