# AI Glasses & Audio — BioMate Prototype Concepts

**Date:** 2026-06-19
**Trigger:** User asked for a survey of AI-glasses + audio applications in life science, plus prototype concepts that link to BioMate. Goal: interesting prototypes for validation and trial-out — *not* product roadmap commitments.
**Companion docs:**
- `docs/20260619_UI_INSPIRATION_FROM_MIRA_DISCUSSION.md` — bench-metaphor UI work this complements
- `reference/claude_design/design_handoff_bench_prototype/` — earlier metaphor prototype
- `reference/claude_design/design_handoff_glasses_audio_prototype/` — design handoff written from this doc

## Part 1 — State of the field (survey summary)

Full sourced survey returned by research agent; key facts cited below. The honest read:

### AI glasses in life science (2025-2026)

**Mature beachhead = surgical AR.** Augmedics xvision (FDA-cleared, ~13k procedures, rolled into VB Spine Feb 2026), MediView XR90 (FDA-cleared, $24M Series A Oct 2025 led by GE HealthCare, 104-patient multicenter trial at Weill Cornell + MedStar Georgetown). Vision Pro + ScopeXR — SightMD's Dr Rosenberg has done "hundreds" of cataract surgeries since Oct 2025; UC San Diego completed 60 live-surgery trials.

**Pharma manufacturing / GMP = RealWear + Vuzix.** Voice-driven SOP step-through, hands-free barcode scan, remote expert call. Vuzix hired RealWear co-founder as President of Enterprise Solutions Sept 2025 — segment consolidating around assisted-reality monocular hardware.

**Wet-lab bench science = still pilots.** Named LabTwin-on-glasses / AugmentX deployments not found. Meta Ray-Ban Display / Even Realities G1 / Brilliant Labs Frame have zero peer-reviewed clinical or lab deployments surfaced.

**Recurring shape (what keeps working):**
1. AR overlay on a physical thing (anatomy, microscope field, sample tube)
2. Hands-free step-through of a fixed protocol (SOP, surgical checklist, GMP batch record)
3. POV capture for reproducibility / training / remote expert
4. Glanceable reference data without losing the sterile field

**Hardware constraints worth respecting:**
- Vision Pro: ~600-650g, tethered external battery, ~2hr. Fine for OR cockpit; fatiguing for all-day.
- RealWear/Vuzix: ~100-380g, monocular, voice-first, PPE-compatible, but assisted-reality (no real AR overlay).
- Consumer AR (Ray-Ban Display, G1): 20-30° FOV — small.
- HIPAA/PHI: dominant procurement blocker. Most surgical deployments keep compute on a paired workstation, not in the headset.

### Voice / audio AI in life science (2025-2026)

**Clinical ambient scribes = the breakout.** Nuance DAX rebranded **Microsoft Dragon Copilot** 2025, embedded in Epic. 46-clinician QI study: −20.4% note time (10.3→8.2 min/visit). Abridge: −14% note time. Suki, Ambience, Freed, DeepScribe, OrbDoc all report ≥90% note accuracy. **Dragon Copilot for Nurses** launched late 2025 — first push beyond physicians.

**Lab voice-AI = much earlier.** LabTwin (Berlin, 2018) still the headline — voice-driven hands-free ELN capture, mobile app, integrates with Colabra. Benchling emphasizes typed/structured capture, not voice. Whisper-based ad-hoc dictation exists but no major named pilot.

**Voice-driven bioinformatics = essentially greenfield.** No voice interface to Galaxy, Nextflow, Seven Bridges, or similar surfaced. Elicit and Consensus still text-first. **This is the open door for us.**

**Audio-as-output = NotebookLM Audio Overviews moment.** >2M users, podcast-style, March 2025 added tone/length controls. Flynn 2025 peer review of planetary-science use: "well-structured with creative explanations" but **hallucinations in every summary tested** — audio summarization for science needs grounding/citations to be safe.

**Recurring shape:**
1. Ambient capture of speech that would otherwise be re-typed
2. Structured-form-filling by voice rather than free dictation
3. Podcast-style audio summarization of dense docs (fighting hallucination problem)
4. **Voice as a query/command layer over existing bioinformatics systems — unbuilt**

## Part 2 — Where BioMate genuinely fits

**Honest principle: don't chase the surgical-AR market.** That's a regulated medical-device segment with FDA paths, OR integration, and 5-year sales cycles. Different product, different company.

**Where BioMate naturally fits:**
- **Wet-lab bench**: hands are wet/gloved; protocol runs in parallel to BioMate computational analysis; user wants to dictate observations + query last night's pipeline results without taking off gloves
- **CRO / GMP audit**: hands-free SOP step-through where the SOP came from a BioMate-generated protocol or methods report
- **Surgical / pathology / clinical**: not our market — leave to MediView, Augmedics, ScopeXR
- **Daily lab digest**: NotebookLM-style audio summary of "what your benches did overnight" — natural extension of our overnight-WIKI gap from the Mira discussion
- **Voice-driven chat with BioMate** while doing other lab work — the unbuilt voice-over-bioinformatics gap

## Part 3 — Five prototype concepts, ranked by feasibility-per-validation-value

### Prototype A — **"Bench Briefing"** — daily audio digest of your benches (audio, no glasses)

**The concept:** Each morning, BioMate generates a 3-5 minute audio briefing per bench (project) covering: what runs completed overnight, what failed and why, what bench-checks flagged, what's queued. User listens on commute / in the shower / during gloved bench work. Built on top of the WIKI auto-consolidation gap we already identified.

**Why it's the right first prototype:**
- Zero hardware cost — phone playback, web playback
- Reuses our After-run reports + project memory as input
- Validates audio-as-output for science without committing to glasses
- Directly answers a real user pain: "I came in this morning and don't know what happened"
- Hallucination-mitigation is achievable: ground every spoken sentence in a cited finding from the actual run report (Flynn 2025 said NotebookLM Audio hallucinates *because* it has no grounding contract — we have grounding by construction)

**MVP:** nightly cron per project → LLM generates structured digest from After-run reports + chat history → ElevenLabs or OpenAI TTS → MP3 + transcript posted to project + email/Slack with playable link. ~1 week.

**Validation question:** Do users actually listen? Do they prefer it over reading?

### Prototype B — **"Bench Voice"** — voice query of BioMate while gloved/away from keyboard (audio, no glasses)

**The concept:** A phone app (or web with push-to-talk) where a wet-lab user, mid-experiment with gloves on, can say *"BioMate, did last night's RNA-seq run finish?"* / *"What was the top hit from the ADMET screen?"* / *"Start a docking run on the compound I uploaded yesterday."* Replies are spoken back. Dictated observations get saved to the project notebook with timestamps.

**Why interesting:**
- Closes the "voice over bioinformatics" greenfield gap
- LabTwin proved the voice-to-ELN pattern works at the bench
- Our chain composer + project memory + chat infrastructure already does the hard part; voice is just an I/O wrapper
- Validates whether voice changes how scientists *think* about querying their data

**MVP:** Web app, push-to-talk, Whisper STT → existing BioMate chat backend → TTS reply. Per-project context-window already exists. ~1-2 weeks.

**Validation question:** Does voice surface useful queries that the typed UI doesn't? Or is it a novelty that users abandon after week 2?

### Prototype C — **"Bench Glasses"** — RealWear/Vuzix protocol step-through driven by BioMate-generated protocol (glasses)

**The concept:** When BioMate generates a wet-lab protocol (e.g. as part of an ADMET assay validation, or a CRO SOP), instead of just a PDF write-up, it ships an **assisted-reality script** that a tech can step through on RealWear/Vuzix glasses. Each step is voice-confirmed; deviations dictated as observations. End-of-protocol the deviation log syncs back to BioMate as part of the project notebook + becomes input to the next computational analysis.

**Why it's interesting:**
- Hits the *actual* product-market-fit point for lab glasses (hands-free SOP, not AR overlay)
- Connects BioMate's computational protocol to the wet-lab execution — closes the loop our product story currently leaves open
- RealWear is the obvious hardware (ruggedized, voice-first, $2-3k, PPE-compatible) — not Vision Pro
- Differentiates from LabTwin (phone-based) by being truly hands-free

**MVP:** Web companion that renders a BioMate write-up as a step-by-step voice-driven script, viewable on any browser; later port to RealWear/Vuzix SDK. ~2 weeks for the web version; +2-3 weeks for actual glasses port (RealWear has a Chromium-based browser, so HTML works).

**Validation question:** Do CRO clients (our existing IND/compliance customers) actually want hands-free SOP execution? Are they willing to give us their protocol corpus to test?

### Prototype D — **"Microscope Pin"** — Vision Pro overlay of BioMate analysis on live microscope feed (glasses, ambitious)

**The concept:** Vision Pro running a BioMate companion app. User is at a microscope (or imaging station); the camera feed is captured; BioMate runs cell-segmentation / phenotype-classification / hit-flagging in near-real-time; results overlaid as floating annotations in the Vision Pro's stereoscopic view. Press "Pin" and the annotated frame becomes a notebook entry.

**Why it's interesting:**
- Hits the "AR overlay on a physical thing" recurring shape that's working in surgery
- Microscopy is the natural lab analog
- Vision Pro stereoscopic 3D microscope rendering is *exactly* what ScopeXR is doing in cataract surgery — same hardware capability, transferred to research microscopy
- BioMate's existing cell-segmentation + nf-core image-analysis pipelines provide the substrate

**Why I'd defer it:**
- Hardware cost ($3500+ per unit)
- Vision Pro deployment is non-trivial
- Real-time inference on microscope feeds is a hard ML/MLOps problem
- Better to prove A + B + C first; this is a flagship demo, not a first prototype

**MVP path if pursued:** static demo — pre-recorded microscope clip + pre-computed overlays — rendered in Vision Pro. Skip real-time. ~3 weeks for a demo film; production-grade is months.

### Prototype E — **"POV Reproducibility"** — record-once protocol video that becomes a BioMate run-card (glasses, opportunistic)

**The concept:** A scientist wearing glasses records their wet-lab protocol once (POV video + voice annotations). BioMate ingests the video + transcript, extracts the protocol steps, generates a structured methods-section write-up + a re-runnable computational pipeline for the downstream analysis. The video itself becomes part of the run-card for reproducibility / training / regulatory audit.

**Why interesting:**
- Hits the "POV capture for reproducibility" recurring shape
- Compounds the bench notebook into something the next person on the team can actually replicate
- The voice annotation + video pairing makes regulatory audit (21 CFR Part 11) much cleaner — visual chain-of-custody for wet-lab steps

**Why it's lower-priority:**
- Video transcription + step extraction is a real ML pipeline
- Wide angle for validation — unclear whether users want to record themselves at all
- Privacy issues in shared labs

**MVP:** demo film using a single recorded protocol + manual transcript + GPT-generated structured write-up. ~2 weeks for the demo; production-grade is 2-3 months.

## Part 4 — Recommendation: prototype A + B first

**Sprint shape (3-4 weeks):**

| Week | Build |
|---|---|
| 1 | **Prototype A — Bench Briefing.** Nightly cron, digest LLM call, TTS pipeline, web playback. Demo to user. |
| 2 | **Prototype B — Bench Voice.** Web push-to-talk on top of existing chat backend. Demo to user. |
| 3 | Build a small recorded demo of **Prototype C — Bench Glasses** (web version, no glasses hardware yet) using a real CRO SOP we already have. |
| 4 | Buffer / iterate / decide whether to pursue glasses hardware (RealWear) for a real Prototype C pilot |

**What we get out of it:**
- 2 working prototypes users can react to with real audio
- 1 video-demo prototype for CRO/glasses conversation
- A real read on whether audio is a feature or a novelty for our users
- Clear signal on whether glasses are worth a hardware investment

**What we're *not* committing to:**
- Vision Pro (Prototype D)
- POV video (Prototype E)
- Surgical AR market entry (out of scope, wrong company)
- Any new ML pipelines

## Part 5 — Hallucination contract (cross-cutting)

Every audio output (A, B, and the voice-replies in Bench Voice) must be **grounded by construction**:

- Every spoken sentence cites an underlying source (a specific run, a chat message, a finding row, a published threshold)
- Source list is shown alongside the audio player (transcript + clickable citations)
- If the LLM can't ground a sentence, it doesn't get spoken — it gets dropped or replaced with "I don't have confirmed information about X"
- The transcript is the audit artifact; the audio is the convenience

This is the lesson from Flynn 2025's NotebookLM audit. We have grounding by construction; we shouldn't waste it.

## Open questions for you

1. Bench Briefing (A) is the obvious first prototype. Agree?
2. Does any current customer (CRO, lab, IND-filer) already have a hands-free use case we know about? That would change the ranking — Prototype C jumps to #1 if there's a real user pulling.
3. Hardware budget for a RealWear unit (~$2.5k) to test Prototype C properly — worth it before we have a customer pulling?
4. For Bench Voice (B), do we build it as a phone app or a web push-to-talk first? Web is faster but worse for the hands-gloved bench use case.
