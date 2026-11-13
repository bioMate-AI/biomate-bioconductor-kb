# Voice composer placement fix (2026-11-13)

## User report

After deploy of voice slim tip `5a82125ac8`, live still showed bulky stacked panels above the composer (Start voice banner + Hands-free checkbox + Speak disclaimer bar). Expected: Settings-gated compact Speak/Live icons **inside** the chatbox toolbar only; long vendor copy removed.

## Root cause

1. **Live tip tree ≠ slim UI.** Public `build-info.json` tip `23036f10` is an ancestry-gate merge that **kept the FDR tree** (bulky `LiveVoicePanel` with Hands-free checkbox + “Audio is sent to ElevenLabs…”). Slim sources existed on a merge parent (`5a82125ac8`) but were not the deployed file tree — so live JS still contained the old panels.
2. **Incomplete dual-composer fix on the PR398/feat tree.** Even the slimmed components left a second `<LiveVoicePanel>` mount in `chat-interface.tsx` **above** `<ChatInput>`, while `chat-input.tsx` already hosts Speak + Live in the toolbar. That reintroduces above-composer chrome whenever Settings → Voice is on.

## Fix

- Remove above-composer `LiveVoicePanel` from `chat-interface.tsx` (toolbar-only via `ChatInput`).
- Drop ElevenLabs / AI-generated-voice disclaimer strings from voice UI, hover titles, and Settings copy (SDK import may remain).
- Add `chat-interface.voice-placement.test.ts` so a regression re-mounting LiveVoicePanel above the composer fails CI.

## Verify

1. Settings → Chat → Voice **off** (default): no mic/Live in composer.
2. Voice **on**: Speak + Live icons appear next to Data inside the input card; no panels stacked above.
3. Hover tips have no ElevenLabs / “AI-generated voice” sentence.
4. Live `build-info.json` commit is an ancestor of this fix tip and the frontend bundle lacks `Hands-free: send when I pause`.
