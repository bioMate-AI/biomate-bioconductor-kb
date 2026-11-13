# Voice settings: Cursor panel + OSS harness research (2026-11-13)

## Cursor Settings → Voice (from screenshot)

| Row | Control | Role |
|---|---|---|
| Agent Voice | Dropdown + sample speaker | TTS voice identity |
| Speed | Dropdown (1x) | TTS rate |
| Language | Dropdown (Auto-detect) | STT/TTS locale |
| Microphone | Device picker | Input device |
| Submit Keywords | Tag chips | Spoken words that submit while dictating |

**Patterns:** dense single card; label + one-line desc + control; prefs in Settings, not chat chrome; no vendor disclaimer copy; composer stays icon-only.

## OSS / harness comparison

| Product | How voice is added | Settings vs composer | Push-to-talk vs hands-free | Provider placement |
|---|---|---|---|---|
| **Cursor** | Native Settings → Voice + in-product voice chat | Rich prefs in Settings; chat stays clean | Keywords for submit; voice chats | Built-in (voice/speed/mic/lang) |
| **Open WebUI** | Settings → Audio (user) + Admin Audio | Mic/call affordance in input when allowed | Conversation / voice mode (hands-free loop) | STT/TTS engines in Settings (Whisper, OpenAI, ElevenLabs, browser, …) |
| **LibreChat** | Speech tab + STT button near send (`Shift+Alt+L`) | `speechTab` user prefs; YAML for providers | Conversation mode; auto-send after STT; auto-transcribe | browser vs external STT/TTS; voice + playbackRate |
| **SillyTavern** | Extensions → Speech Recognition; **mic next to send** | Extension settings (mode, language, mapping) | Append / Replace / Auto-send; phrase mapping ≈ keywords | Browser Web Speech, Whisper APIs, etc. |
| **Aider** | CLI `/voice` (record → ENTER → Whisper) | CLI flags: language, input device, format | Push-to-talk (start/stop); no chat panels | OpenAI Whisper via API key; PortAudio |
| **Continue.dev** | No first-class mic STT in product (issue #3467; Whisper PR closed) | N/A / experimental TTS flag only | N/A | Relies on VS Code / external |
| **Cline / Roo** | Mic-in-input desired; draft Whisper PR (#5358), not landed as standard | Discussion: composer mic | Push-to-talk intended | Whisper (proposed) |
| **GPT4All** | Chat UI; voice not a primary documented harness feature | — | — | Local LLM focus |

**Common pattern:** Settings (or extension config) hold engine/device/language; composer gets a **small mic**; hands-free = auto-send / conversation mode; keyword/phrase maps are optional power features.

## BioMate today vs Cursor

| Cursor row | BioMate | Ship now? |
|---|---|---|
| Agent Voice + sample | TTS via `/api/voice/speak` (read-aloud) — **no voice list / sample API wired in Settings** | **Defer** (don’t fake dropdown) |
| Speed | No playbackRate setting | **Defer** |
| Language | Scribe/Live has no user language picker | **Defer** |
| Microphone | Browser default only (`getUserMedia` / Scribe mic constraints) | **Defer** |
| Submit Keywords | No keyword chip store | **Defer** (closest: Hands-free = send on pause) |
| On/off + composer icons | `voiceEnabled` + Speak/Live in `chat-input` | **Ship** |
| Hands-free | `voiceHandsFree` → Live auto-send on VAD pause | **Ship** |

## Applied in this change

- Reachable **Settings → Voice** tab (outside `{false && …}`).
- Cursor-like dense rows for **Voice in chat**, **Hands-free**, and a read-only **Composer controls** hint (Speak · Live).
- No ElevenLabs disclaimer; no fake Agent Voice / Speed / Mic / Keywords.

## Deferred (need backend/product work)

- TTS voice catalog + sample playback
- Playback speed
- STT language + mic deviceId
- Submit-keyword chips (map spoken phrases → send / commands)
