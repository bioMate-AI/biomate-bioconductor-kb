# Live voice implementation — October 10, 2026

## Architecture decision

Use ElevenLabs Scribe Realtime for microphone transcription and the existing server-side ElevenLabs synthesis endpoint for BioMate replies. This keeps the current chat dispatcher, visible history, project context, and workflow approval behavior. Speech Engine was evaluated, but a separate publicly reachable backend conversation service would duplicate BioMate's existing frontend orchestration. No separate LLM or hosted agent was provisioned.

## Implemented locally

- Live voice panel in the real chat interface: Start/End, Mute/Unmute, partial transcripts, editable draft, and optional hands-free sending after pauses. Review-before-send is the default.
- Complete new replies are spoken while a session is active; existing replies are not replayed at startup. Replies over 5,000 characters stay on screen with a request to ask for a summary.
- Speech interruptions stop playback, not workflow execution. While chat is busy, additional speech is retained as a draft rather than silently queued for execution.
- Chat changes, page hiding, end-call, errors, and disconnects release the live connection. Late callbacks cannot submit to a different chat. Drafts survive disconnection within the panel.
- Batch recording and live recording stop each other to prevent concurrent microphone use.
- Authenticated, separately gated short-lived single-use transcription-token endpoint; two requests per minute per user per process. Provider API key stays server-side; token response bodies are excluded from API logs.
- Dedicated enable flag `BIOMATE_LIVE_VOICE_ENABLED=true` in addition to the base voice configuration. Defaults remain disabled.
- Same-origin bundled audio worklet avoids permitting blob scripts. When enabled, CSP explicitly allows the ElevenLabs WebSocket destination and blob audio playback.
- Five-minute browser session cap. This is not a server-enforced provider billing limit; quota accounting and distributed limits remain release requirements.

## Evidence

- Real existing-account provider connection succeeded with Scribe Realtime. Synthetic speech was transcribed as “Please compare BRCA1 and TP53.” See `qa/20261010-voice/realtime-provider-proof.json`. One sentence does not establish broad biomedical accuracy.
- 18 focused tests passed across batch controls, live controls, and authenticated server endpoints.
- TypeScript passed. Production build passed with existing bundle-size/dependency warnings. Full regression suite passed: 151 files / 1,843 tests; 2 files / 7 tests skipped.

## Not yet delivered

No development or production deployment. No real browser microphone/playback end-to-end pass yet. Current local app configuration has no usable local backend configuration; an authenticated development runtime is needed for that test. No claim of full ChatGPT voice parity, low-latency streaming synthesis, Safari autoplay compatibility, or complete scientific-term accuracy.

Before enabling users: test the real browser audio flow, verify safe operation against existing workflow approvals, configure deployment secrets, integrate usage budgeting, run the mandatory deployment checks, deploy to development and recheck. Keep website feature claims unchanged until then.
