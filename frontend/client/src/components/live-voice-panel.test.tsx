import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { LiveVoicePanel } from './live-voice-panel';
const sdk = vi.hoisted(() => ({ handlers: {} as Record<string, (x?: any) => void>, close: vi.fn(), mute: vi.fn(), unmute: vi.fn() }));
vi.mock('@elevenlabs/client', () => ({
  Scribe: { connect: () => ({ on: (name: string, fn: any) => { sdk.handlers[name] = fn; }, close: sdk.close, mute: sdk.mute, unmute: sdk.unmute }) },
  CommitStrategy: { VAD: 'vad' }, RealtimeEvents: { SESSION_STARTED: 'start', PARTIAL_TRANSCRIPT: 'partial', COMMITTED_TRANSCRIPT: 'committed', ERROR: 'error', AUTH_ERROR: 'auth', CLOSE: 'close' },
}));
beforeEach(() => { sdk.handlers = {}; vi.clearAllMocks(); vi.stubGlobal('fetch', vi.fn(async (url: string) => ({ ok: true, json: async () => url.endsWith('status') ? { liveAvailable: true } : { token: 'temporary' } }))); });
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
async function start() {
  fireEvent.click(await screen.findByRole('button', { name: 'Start voice' }));
  await waitFor(() => expect(sdk.handlers.start).toBeDefined());
  act(() => sdk.handlers.start());
}
it('shows partial speech but requires review by default', async () => {
  const send = vi.fn(); render(<LiveVoicePanel busy={false} onSend={send} />); await start();
  act(() => sdk.handlers.partial({ text: 'BRCA' })); expect(screen.getByText('BRCA')).toBeInTheDocument();
  act(() => sdk.handlers.committed({ text: 'BRCA1 and TP53' }));
  expect(send).not.toHaveBeenCalled();
  fireEvent.change(screen.getByLabelText('Voice draft'), { target: { value: 'Review BRCA1' } });
  fireEvent.click(screen.getByRole('button', { name: 'Send reviewed text' })); expect(send).toHaveBeenCalledWith('Review BRCA1');
});
it('hands-free sends one turn, retains further speech, and never queues while busy', async () => {
  const send = vi.fn(); const view = render(<LiveVoicePanel busy={false} onSend={send} />); await start();
  fireEvent.click(screen.getByRole('checkbox'));
  act(() => sdk.handlers.committed({ text: 'first turn' }));
  act(() => sdk.handlers.committed({ text: 'additional context' }));
  expect(send).toHaveBeenCalledTimes(1); expect(screen.getByLabelText('Voice draft')).toHaveValue('additional context');
  view.rerender(<LiveVoicePanel busy onSend={send} />);
  act(() => sdk.handlers.committed({ text: 'wait for this' })); expect(send).toHaveBeenCalledTimes(1);
});
it('stops audio on speech, mutes capture, and closes on unmount', async () => {
  const stopped = vi.fn(); window.addEventListener('biomate-voice-stop', stopped);
  const send = vi.fn(); const view = render(<LiveVoicePanel busy={false} onSend={send} />); await start();
  act(() => sdk.handlers.partial({ text: 'interrupt' })); expect(stopped).toHaveBeenCalled();
  fireEvent.click(screen.getByRole('button', { name: 'Mute' })); expect(sdk.mute).toHaveBeenCalled();
  act(() => sdk.handlers.committed({ text: 'discard muted text' })); expect(screen.queryByLabelText('Voice draft')).toBeNull();
  view.unmount(); expect(sdk.close).toHaveBeenCalled(); window.removeEventListener('biomate-voice-stop', stopped);
});
it('ignores late events after ending and preserves a draft on disconnect', async () => {
  const send = vi.fn(); render(<LiveVoicePanel busy={false} onSend={send} />); await start();
  act(() => sdk.handlers.committed({ text: 'retained draft' }));
  act(() => sdk.handlers.close());
  expect(screen.getByLabelText('Voice draft')).toHaveValue('retained draft');
  act(() => sdk.handlers.committed({ text: 'stale words' }));
  expect(screen.getByLabelText('Voice draft')).toHaveValue('retained draft'); expect(send).not.toHaveBeenCalled();
});
