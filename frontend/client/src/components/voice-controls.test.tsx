import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { VoiceInput, ReadAloud } from './voice-controls';

let recorder: FakeRecorder;
class FakeRecorder {
  static isTypeSupported = () => true;
  state = 'inactive'; mimeType = 'audio/webm';
  onstop: (() => void) | null = null;
  ondataavailable: ((event: { data: Blob }) => void) | null = null;
  onerror: (() => void) | null = null;
  constructor() { recorder = this; }
  start() { this.state = 'recording'; }
  stop() { this.state = 'inactive'; this.ondataavailable?.({ data: new Blob(['audio']) }); this.onstop?.(); }
}
let stopTrack = vi.fn();
beforeEach(() => {
  vi.stubGlobal('MediaRecorder', FakeRecorder);
  stopTrack = vi.fn();
  Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: { getUserMedia: vi.fn().mockResolvedValue({ getTracks: () => [{ stop: stopTrack }] }) } });
  vi.stubGlobal('fetch', vi.fn(async (url: string) => url.endsWith('/status')
    ? { ok: true, json: async () => ({ available: true }) }
    : { ok: true, json: async () => ({ text: '检查 BRCA1' }) }));
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
it('releases recording on page hide without submitting audio', async () => {
  const callback = vi.fn(); render(<VoiceInput onTranscript={callback} />);
  fireEvent.click(await screen.findByRole('button', { name: 'Speak' }));
  await screen.findByRole('button', { name: 'Stop' });
  const hidden = vi.spyOn(document, 'hidden', 'get').mockReturnValue(true);
  try {
    fireEvent(document, new Event('visibilitychange'));
    expect(stopTrack).toHaveBeenCalled();
    expect(callback).not.toHaveBeenCalled();
    expect(vi.mocked(fetch).mock.calls.some(c => String(c[0]).includes('/transcribe'))).toBe(false);
    expect(screen.getByRole('button', { name: 'Speak' })).toBeInTheDocument();
  } finally { hidden.mockRestore(); }
});

it('detaches callbacks from stopped audio before another reply plays', async () => {
  const players: any[] = [];
  vi.stubGlobal('Audio', class {
    onended: (() => void) | null = null;
    onerror: (() => void) | null = null;
    pause = vi.fn(); play = vi.fn().mockResolvedValue(undefined);
    constructor() { players.push(this); }
  });
  const OriginalURL = URL;
  vi.stubGlobal('URL', class extends OriginalURL {
    static createObjectURL = vi.fn(() => 'blob:test');
    static revokeObjectURL = vi.fn();
  });
  vi.stubGlobal('fetch', vi.fn(async (url: string) => url.endsWith('/status')
    ? { ok: true, json: async () => ({ available: true }) }
    : { ok: true, blob: async () => new Blob(['audio'], { type: 'audio/mpeg' }) }));
  try {
    render(<ReadAloud text="Review TP53" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Read aloud' }));
    await waitFor(() => expect(players[0]?.play).toHaveBeenCalled());
    fireEvent.click(screen.getByRole('button', { name: 'Stop' }));
    expect(players[0].onended).toBeNull();
    expect(players[0].onerror).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Read aloud' }));
    await waitFor(() => expect(players[1]?.play).toHaveBeenCalled());
    expect(players[1].pause).not.toHaveBeenCalled();
  } finally { cleanup(); vi.stubGlobal('URL', OriginalURL); }
});
describe('voice controls', () => {
  it('returns an editable transcript only after recording stops and releases the microphone', async () => {
    const callback = vi.fn(); render(<VoiceInput onTranscript={callback} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Speak' }));
    await screen.findByRole('button', { name: 'Stop' });
    expect(callback).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Stop' }));
    await waitFor(() => expect(callback).toHaveBeenCalledWith('检查 BRCA1'));
    expect(stopTrack).toHaveBeenCalled();
    expect(screen.getByRole('status')).toHaveTextContent('Review the transcript');
  });
  it('releases the microphone on unmount without submitting audio', async () => {
    const callback = vi.fn(); const view = render(<VoiceInput onTranscript={callback} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Speak' }));
    await screen.findByRole('button', { name: 'Stop' });
    view.unmount();
    expect(stopTrack).toHaveBeenCalled(); expect(callback).not.toHaveBeenCalled();
    expect(vi.mocked(fetch).mock.calls.some(c => String(c[0]).includes('/transcribe'))).toBe(false);
  });
  it('discards a microphone permission result after the conversation is closed', async () => {
    let resolve!: (stream: MediaStream | PromiseLike<MediaStream>) => void;
    vi.mocked(navigator.mediaDevices.getUserMedia).mockReturnValue(new Promise(r => { resolve = r; }));
    const callback = vi.fn(); const view = render(<VoiceInput onTranscript={callback} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Speak' })); view.unmount();
    await act(async () => resolve({ getTracks: () => [{ stop: stopTrack }] } as unknown as MediaStream));
    expect(stopTrack).toHaveBeenCalled(); expect(callback).not.toHaveBeenCalled();
  });
  it('shows a useful microphone-permission error', async () => {
    vi.mocked(navigator.mediaDevices.getUserMedia).mockRejectedValue(new Error('denied'));
    render(<VoiceInput onTranscript={vi.fn()} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Speak' }));
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Microphone unavailable'));
  });
  it('does not silently truncate a long scientific answer for read-aloud', async () => {
    render(<ReadAloud text={'a'.repeat(5001)} />);
    fireEvent.click(await screen.findByRole('button', { name: 'Read aloud' }));
    expect(screen.getByRole('status')).toHaveTextContent('Ask for a short summary');
    expect(vi.mocked(fetch).mock.calls.some(c => String(c[0]).includes('/speak'))).toBe(false);
  });
});
