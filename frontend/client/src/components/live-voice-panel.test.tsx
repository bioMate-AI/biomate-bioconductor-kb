import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { LiveVoicePanel } from './live-voice-panel';

const toast = vi.fn();
vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast }) }));

const sdk = vi.hoisted(() => ({ handlers: {} as Record<string, (x?: any) => void>, close: vi.fn(), mute: vi.fn(), unmute: vi.fn() }));
vi.mock('@elevenlabs/client', () => ({
  Scribe: { connect: () => ({ on: (name: string, fn: any) => { sdk.handlers[name] = fn; }, close: sdk.close, mute: sdk.mute, unmute: sdk.unmute }) },
  CommitStrategy: { VAD: 'vad' }, RealtimeEvents: { SESSION_STARTED: 'start', PARTIAL_TRANSCRIPT: 'partial', COMMITTED_TRANSCRIPT: 'committed', ERROR: 'error', AUTH_ERROR: 'auth', CLOSE: 'close' },
}));

function setVoiceSettings(voiceEnabled: boolean, voiceHandsFree: boolean) {
  localStorage.setItem('biomate-user-settings', JSON.stringify({
    id: 'settings-test', voiceEnabled, voiceHandsFree, updatedAt: new Date().toISOString(),
  }));
  window.dispatchEvent(new Event('biomate-voice-settings-changed'));
}

beforeEach(() => {
  sdk.handlers = {};
  vi.clearAllMocks();
  setVoiceSettings(true, false);
  vi.stubGlobal('fetch', vi.fn(async (url: string) => ({
    ok: true,
    json: async () => url.endsWith('status') ? { liveAvailable: true } : { token: 'temporary' },
  })));
});
afterEach(() => { cleanup(); localStorage.clear(); vi.unstubAllGlobals(); });

async function start() {
  fireEvent.click(await screen.findByRole('button', { name: 'Start voice' }));
  await waitFor(() => expect(sdk.handlers.start).toBeDefined());
  act(() => sdk.handlers.start());
}

it('hides live voice when settings voice is off', async () => {
  setVoiceSettings(false, false);
  render(<LiveVoicePanel busy={false} onSend={vi.fn()} />);
  await act(async () => {});
  expect(screen.queryByRole('button', { name: 'Start voice' })).toBeNull();
});

it('shows partial speech and appends committed text to the composer for review', async () => {
  const send = vi.fn();
  const onTranscript = vi.fn();
  render(<LiveVoicePanel busy={false} onSend={send} onTranscript={onTranscript} />);
  await start();
  act(() => sdk.handlers.partial({ text: 'BRCA' }));
  expect(screen.getByText('BRCA')).toBeInTheDocument();
  act(() => sdk.handlers.committed({ text: 'BRCA1 and TP53' }));
  expect(send).not.toHaveBeenCalled();
  expect(onTranscript).toHaveBeenCalledWith('BRCA1 and TP53');
  expect(screen.queryByLabelText('Voice draft')).toBeNull();
});

it('hands-free sends one turn and never queues while busy', async () => {
  setVoiceSettings(true, true);
  const send = vi.fn();
  const onTranscript = vi.fn();
  const view = render(<LiveVoicePanel busy={false} onSend={send} onTranscript={onTranscript} />);
  await start();
  act(() => sdk.handlers.committed({ text: 'first turn' }));
  act(() => sdk.handlers.committed({ text: 'additional context' }));
  expect(send).toHaveBeenCalledTimes(1);
  expect(send).toHaveBeenCalledWith('first turn');
  expect(onTranscript).toHaveBeenCalledWith('additional context');
  view.rerender(<LiveVoicePanel busy onSend={send} onTranscript={onTranscript} />);
  act(() => sdk.handlers.committed({ text: 'wait for this' }));
  expect(send).toHaveBeenCalledTimes(1);
  expect(onTranscript).toHaveBeenCalledWith('wait for this');
});

it('stops audio on speech, mutes capture, and closes on unmount', async () => {
  const stopped = vi.fn(); window.addEventListener('biomate-voice-stop', stopped);
  const send = vi.fn();
  const onTranscript = vi.fn();
  const view = render(<LiveVoicePanel busy={false} onSend={send} onTranscript={onTranscript} />);
  await start();
  act(() => sdk.handlers.partial({ text: 'interrupt' })); expect(stopped).toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Mute' })); expect(sdk.mute).toHaveBeenCalled();
  act(() => sdk.handlers.committed({ text: 'discard muted text' })); expect(onTranscript).not.toHaveBeenCalled();
  view.unmount(); expect(sdk.close).toHaveBeenCalled(); window.removeEventListener('biomate-voice-stop', stopped);
});

it('ignores late events after ending and toasts on disconnect', async () => {
  const send = vi.fn();
  const onTranscript = vi.fn();
  render(<LiveVoicePanel busy={false} onSend={send} onTranscript={onTranscript} />);
  await start();
  act(() => sdk.handlers.committed({ text: 'retained draft' }));
  expect(onTranscript).toHaveBeenCalledWith('retained draft');
  act(() => sdk.handlers.close());
  expect(toast).toHaveBeenCalled();
  onTranscript.mockClear();
  act(() => sdk.handlers.committed({ text: 'stale words' }));
  expect(onTranscript).not.toHaveBeenCalled(); expect(send).not.toHaveBeenCalled();
});

it('renders a compact toolbar control without stacked disclaimer chrome', async () => {
  render(<LiveVoicePanel busy={false} onSend={vi.fn()} />);
  const start = await screen.findByRole('button', { name: 'Start voice' });
  expect(start.closest('[data-testid="composer-voice-live"]')).toBeTruthy();
  expect(screen.queryByText(/Audio is sent/i)).toBeNull();
  expect(screen.queryByText(/ElevenLabs/i)).toBeNull();
  expect(screen.queryByText(/AI-generated voice/i)).toBeNull();
  expect(screen.queryByText(/Hands-free/i)).toBeNull();
  expect(start.getAttribute('title') || '').not.toMatch(/ElevenLabs|AI-generated voice|Audio is sent/i);
});
