# Glasses & Audio Prototype — Design Requirement

**Date:** 2026-06-19
**Audience:** Claude design agent at `localhost:7779`
**Format:** Standalone HTML prototype (same pattern as `reference/claude_design/cro/Workflow Panel Redesign.html` and the sibling Bench-Prototype handoff)
**Purpose:** Mock up three of the five prototype concepts from `docs/20260619_AI_GLASSES_AND_AUDIO_BIOMATE_PROTOTYPES.md` as static UI surfaces so the user can react to *what they would look like* before we build them.

**Context for designer:** BioMate is exploring two adjacent modalities — voice/audio and AI glasses — as ways to extend the chat-driven bioinformatics product. Survey of the field found that surgical AR is a mature regulated segment we should *avoid*, while wet-lab voice/audio and CRO hands-free SOP step-through are genuine open doors. We want HTML mockups (no code, no audio playback, no real glasses) so the team can see and feel the prototype before committing engineering. Full discussion + the 5 prototype concepts ranked are in `docs/20260619_AI_GLASSES_AND_AUDIO_BIOMATE_PROTOTYPES.md`. The companion bench-metaphor work is in `reference/claude_design/design_handoff_bench_prototype/`.

**Use the same Bench metaphor and dual-voice register established in the Bench-Prototype handoff.** Project = "Bench"; chains = "protocols"; agents = "bench crew"; QC = "bench-check"; report = "notebook entry"; etc. Warm voice for chat/audio/glanceable surfaces; regulatory voice for compliance surfaces.

---

## 3 mockup screens required

### Screen 1 — **Bench Briefing** (morning audio digest)

**The concept:** Each morning, BioMate generates a 3-5 min audio briefing per bench covering: what runs completed overnight, what failed and why, what bench-checks flagged, what's queued. Listen on commute / while gloving up.

**Mock as:** a phone-shaped viewport (375×812) showing the BioMate app's "Bench Briefing" screen.

**Visible elements:**
- Header: *"Tuesday, June 19 · ADMET Screening Bench"*
- Large audio-player UI (play button, scrubber, 4:32 duration shown)
- Below the player: *transcript with clickable citations* — each sentence underlined where it grounds to a specific run / finding / source. Example:
  > *"Overnight, three protocols finished on this bench. The ADMET-100 screen on the Tuesday compound set [run #1284] flagged 18 of 120 compounds for cardiac risk — that's above the Aronov 2008 hERG line. The remediation re-run completed at 3 a.m. with a tighter logP filter; 14 compounds now pass. Two compounds, BMT-44 and BMT-71, still fail and have been pinned to your bench for review."*
- Each `[run #...]` / `Aronov 2008` etc renders as a soft-underline citation chip
- Below transcript: *"Sources: 3 runs, 2 papers, 4 findings"* with chip list
- Foot of screen: small toggle *"Listen daily"* (on) and *"Push to Slack at 8 a.m."* (on)
- Bottom-of-card note: *"Every sentence is grounded in a cited source. If BioMate isn't sure, it doesn't say it."* — this is the hallucination-contract reassurance from the parent doc

**Why this design:** validates the audio modality without playing actual audio in the mock; the transcript-with-citations IS the audit artifact + the convenience surface combined.

### Screen 2 — **Bench Voice** (push-to-talk chat with BioMate, gloved)

**The concept:** Wet-lab user, mid-experiment with gloves on, holds a foot-pedal / wake-word and asks BioMate a question. Reply is spoken back; dictated observations get saved to the notebook.

**Mock as:** a tablet-shaped viewport (1024×768, landscape — assume the tablet is mounted near the bench, not held) showing the BioMate Bench Voice surface.

**Visible elements:**
- Large central mic / waveform area; state shown as *"Listening… (foot pedal held)"*
- Above the mic: scrolling transcript of the most recent exchange:
  - **User:** *"Did last night's RNA-seq finish?"*
  - **BioMate:** *"Yes — it completed at 2:14 a.m. on the Tuesday samples. Bench-check passed. The top differentially-expressed gene was IFNG, log2FC 4.2, padj 1e-12. Want me to open the notebook entry?"*
  - **User:** *"Not now. Note this — well A4 looks contaminated, skip it in the analysis."*
  - **BioMate:** *"Noted on the notebook with timestamp 09:42. I've also flagged A4 as excluded for the next run on this bench."*
- Side-panel on the right: the *notebook entry being live-updated* — the "A4 contamination" observation shown freshly added with a microphone icon
- Top-right: warm-voice status pill *"Bench crew listening · 3 agents online"* with mini-avatars
- Below transcript: small chips for *"Ask BioMate"* / *"Dictate to notebook"* / *"Show last result"* — the verbs are the affordances
- Foot of screen: tiny note *"Microphone is off when foot pedal is released."* — privacy reassurance

**Why this design:** shows that voice is bidirectional (query AND dictation), shows the bench-crew metaphor working, shows the notebook being compounded live.

### Screen 3 — **Bench Glasses** (RealWear/Vuzix hands-free protocol step-through)

**The concept:** A BioMate-generated wet-lab protocol (e.g. ADMET assay sample prep) rendered as a voice-driven step-through script. The tech wears RealWear/Vuzix glasses; says "next" or "back" or "note that"; deviations dictated as observations sync back to BioMate.

**Mock as:** a small monocular viewport (~640×360, with a rounded "screen" shape to evoke a head-up display — NOT a full immersive AR view; RealWear is assisted-reality, not mixed-reality, and we want the mockup to be honest about that). Surround the viewport with a faint "glasses frame" hint so the viewer understands this is what the wearer sees, not a desktop UI.

**Visible elements inside the viewport:**
- Top line, small: *"Bench: ADMET Sample Prep · Step 4 of 12"*
- Center, larger: the current step text in *warm voice* —
  > *"Add 50 µL of the diluted compound stock to wells B1 through B6. Say 'next' when done, or 'note that' if something's off."*
- Below the step text: a tiny voice-status icon *"Listening for: next · back · note that · pause"*
- A muted timer bottom-right: *"00:42 on this step"*
- Side panel (small chip): bench-check preview — *"Next: bench-check at step 6 will verify pipette volumes match the protocol."* — so the user knows what's coming

**Below the glasses viewport (in the mockup canvas, not inside the lens):**
- A second smaller frame showing *"What BioMate captured back at HQ"* — a notebook entry being filled in live with each step's timestamp + dictated observations + the eventual sync of the deviation log to the project
- A caption: *"After completion, this hands-free run becomes a notebook entry in the bench, attached to whichever computational run consumes the wet-lab output. The deviation log is part of the 21 CFR Part 11 audit trail."*

**Why this design:** demonstrates the closed loop (BioMate generates the protocol → wet-lab tech executes hands-free → results sync back to BioMate's computational pipeline) which is the differentiator vs LabTwin (phone, no closed loop with computational backend).

---

## Side-by-side comparison strip (bottom of page)

After the three screens, add a one-row comparison strip showing all three side-by-side at thumbnail size, labelled with:
- *Bench Briefing* — audio output, no hardware
- *Bench Voice* — voice I/O, tablet at the bench
- *Bench Glasses* — hands-free SOP, RealWear/Vuzix

Below the strip, a one-line caption per: feasibility (✓✓✓ / ✓✓ / ✓) and hardware cost ($0 / $0 / ~$2.5k per unit).

---

## What we explicitly do *not* want

- ❌ Mockups of Vision Pro / Apple-style AR overlays. Surgical AR is not our market.
- ❌ Mockups of microscope-overlay (Prototype D) or POV-video (Prototype E). Defer.
- ❌ A full immersive 3D AR view in the glasses screen — RealWear is assisted-reality, not mixed-reality; mockup must be honest
- ❌ Real audio playback or working voice in the prototype — static mockup only
- ❌ Any mention of "nextflow," "Galaxy," "AWS Batch," "S3" in user-visible strings (existing rule)
- ❌ Whimsical illustration that undermines clinical credibility — warm but professional, consistent with Bench-Prototype handoff
- ❌ Hallucinated audio without citation chips — every transcript must show grounding

## Deliverables

1. `Glasses-Audio-Prototype.html` — three screens, single scrollable page with anchor links, plus the comparison strip
2. Reuse the bench-metaphor styling from the Bench-Prototype handoff if it exists; otherwise establish a consistent visual style we can carry across prototypes
3. A caption block under each screen listing the mapped terms used (Bench = project, bench-check = QC, etc.)
4. A "What I changed and why" footer note (3-5 bullets) for choices the designer made that diverged from this brief

## How we'll judge it

After delivery we (user + me) will sit with the prototype and decide:
- Does Bench Briefing's transcript-with-citations make audio-for-science feel safe?
- Does Bench Voice's bidirectional pattern (query + dictation) feel natural, or forced?
- Does Bench Glasses (RealWear-style assisted-reality, not Vision Pro AR) feel right for the lab — or do we need to mock a Vision Pro version too for comparison?
- Which prototype gets built first?
- Whether to commission a real audio sample to layer on top of the Bench Briefing mock for a second-pass demo

**No code changes will be made to BioMate based on this prototype until we've reacted to it.** This is exploration, not specification.
