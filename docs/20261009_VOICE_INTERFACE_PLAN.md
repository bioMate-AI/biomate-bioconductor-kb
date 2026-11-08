# BioMate voice interface plan

## Product experience

Add voice to the existing BioMate conversation. Keep research context, visible messages, attached datasets, workflow review, and user permissions in the existing chat system. Use the existing ElevenLabs account for audio. Ship English and Chinese controls. Do not replace the scientific backend with a separate hosted assistant.

## Delivery stages

1. **Voice foundation — implemented locally.** Record up to 60 seconds, transcribe through ElevenLabs Scribe, insert an editable draft, and let the user review scientific terms before sending. Add explicit read-aloud/stop controls to completed replies using multilingual synthesis. No automatic workflow submission from recorded speech.
2. **Application integration gate — in progress.** Confirm authenticated endpoints, size/text limits, timeout/cancellation, provider failures, microphone denial/release, stale transcript suppression on chat switch, and bilingual audio. Configure credentials through the server deployment secret mechanism. Conduct real browser microphone/playback tests against the running application before enabling users.
3. **Continuous conversation.** Integrate ElevenLabs Speech Engine with an authenticated, short-lived session bridge to BioMate's existing chat. Preserve session ownership and workflow confirmation cards. Handle turn-taking, interruptions, reconnection, long-running analysis updates, and text/voice consistency. Speaking over a reply must stop playback, not cancel a submitted scientific run. Validate Speech Engine entitlement/configuration separately from basic STT/TTS access.
4. **Release.** Validate Chrome/Safari and mobile microphones, English/Chinese biomedical names, sample identifiers, numeric units, cancellation, expired sessions, latency, usage accounting and per-user budgets. Review screenshots and listen to sample outputs. Deploy to development only after the application gate and regression suite pass; update the user manual after the behavior works end to end.

## First implementation

- New authenticated voice status, transcription, and synthesis routes; server-only provider key and voice ID.
- Disabled by default. Requires `BIOMATE_VOICE_ENABLED=true`, `ELEVENLABS_API_KEY`, and `ELEVENLABS_VOICE_ID`. No key is copied from a tutorial into application source or client bundles.
- No microphone permission request until the user selects Speak. Explain that audio goes to ElevenLabs and playback is AI-generated.
- Six-megabyte audio limit, 5,000-character synthesis limit, 45-second upstream timeout, and 12 paid requests/minute/user per server process. Distributed limits and monetary budgets are release work.
- Request cancellation, microphone cleanup, conversation-switch cleanup, and single read-aloud playback at a time.
- Voice transcript response bodies excluded from the existing API response logger. The app does not save recorded audio. Provider retention follows the configured account; no zero-retention claim is made.
- Existing chat, attachments, and workflow-approval logic remain the execution path.

## Verification evidence

- TypeScript check passed.
- Eight voice endpoint tests passed: authentication, unavailable configuration, cross-site requests, unsupported/oversized input, multilingual text, transcript-only response, provider failure, and per-user throttling.
- Five control tests passed: editable transcript callback, unmount cleanup, late microphone permission resolution, denied microphone permission, and explicit handling of replies too long for synthesis.
- Real ElevenLabs requests using the existing tutorial account synthesized short English and Chinese sentences and transcribed both successfully. Sanitized evidence: `qa/20261009-voice/provider-proof.json`. This validates the provider account, not the complete BioMate browser flow or Speech Engine access.
- Full frontend regression suite passed: 150 files / 1,838 tests; 2 files / 7 tests skipped. Existing composer and workflow-approval tests also passed.

## Remaining gates

Not deployed or enabled. Continuous conversation, live microphone/playback audit, deployment secret configuration, scientific-term accuracy tests, and production billing integration remain unfinished. Do not describe these as delivered features in the user manual.

## Provider references

- https://elevenlabs.io/docs/overview/capabilities/speech-engine
- https://elevenlabs.io/docs/api-reference/speech-to-text/convert
- https://elevenlabs.io/docs/api-reference/text-to-speech/convert
