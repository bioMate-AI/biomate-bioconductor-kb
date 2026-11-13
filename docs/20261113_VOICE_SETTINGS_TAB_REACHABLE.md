# Voice settings tab must be reachable (2026-11-13)

## Bug
Earlier voice work claimed **Settings → Chat → Voice**. The Chat Preferences
block (including `voiceEnabled` / `voiceHandsFree` switches) lived inside
`{false && (<>…</>)}` in `settings-dialog.tsx`. The sidebar only listed API
Keys / Connectors / Import — **there was no Chat tab**. Users could not turn
voice on; the composer icons stayed hidden (default off).

## Fix
- Add a real **Voice** sidebar tab (`data-testid="tab-voice"`).
- Render Voice / Hands-free switches in an active `TabsContent` **outside**
  the `{false && …}` gate.
- Source test `settings-dialog.voice-tab.test.ts` fails if switches fall
  back inside the gate.
