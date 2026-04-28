# CryoSPARC Forum Knowledge Crawl — 2026-04-16

**Purpose:** Extract "symptom → parameter change → outcome" patterns from real practitioner threads on discuss.cryosparc.com to fill the gap that published papers do not cover: what specific parameters do users change, and by how much, when a quality gate fails.

**Output file:** `backend/experiments/cryo_em_autoloop_ux/forum_knowledge.py`

---

## Thread Fetch Status

| URL | Status | Notes |
|-----|--------|-------|
| https://discuss.cryosparc.com/t/motion-correction-with-severe-stage-drift/11994 | FETCHED | Full thread content retrieved |
| https://discuss.cryosparc.com/t/patch-motion-correction-query/12723 | FETCHED | Full thread content retrieved |
| https://discuss.cryosparc.com/t/motion-correction-parameters/6789 | NOT RELEVANT | Thread exists but is about GPU CUDA compatibility (sm_80/A100), not motion correction parameters |
| https://discuss.cryosparc.com/t/threshold-for-ctf-fit-in-patch-ctf/5449 | FETCHED | Full thread content retrieved |
| https://discuss.cryosparc.com/t/ctf-fit-resolution-cutoff/8234 | WRONG CONTENT | URL resolves to a CryoSPARC directory migration thread (rsync/MongoDB issue); no CTF content |
| https://discuss.cryosparc.com/t/blob-pick-does-not-pick-the-right-particles/13944 | FETCHED | Full thread content retrieved |
| https://discuss.cryosparc.com/t/too-many-junk-particles-in-2d-classification/7823 | 404 | Thread does not exist |
| https://discuss.cryosparc.com/t/preferred-orientation-issue/14664 | FETCHED | Full thread content retrieved |
| https://discuss.cryosparc.com/t/rebalance-orientations/9123 | 404 | Thread does not exist |
| https://discuss.cryosparc.com/t/ab-initio-is-giving-more-or-less-similar-classes/14422 | FETCHED | Full thread content retrieved |
| https://discuss.cryosparc.com/t/number-of-classes-particles-for-an-ab-initio-job/10271 | FETCHED | Limited content; no CryoSPARC team response |

**Additional threads found and fetched via search:**
- https://discuss.cryosparc.com/t/discrete-ctf-fit-resolution-jumps/5303 — FETCHED
- https://discuss.cryosparc.com/t/threshold-setting-issue-in-curate-micrographs/24493 — FETCHED
- https://discuss.cryosparc.com/t/poor-patch-ctf-estimation-resolution/24076 — FETCHED
- https://discuss.cryosparc.com/t/possible-preferred-orientation-how-to-improve-data/13341 — FETCHED
- https://discuss.cryosparc.com/t/rebalance-orientations-survey-question/24530 — FETCHED
- https://discuss.cryosparc.com/t/preferred-orientation-in-small-protein/16619 — FETCHED
- https://discuss.cryosparc.com/t/how-to-remove-preferred-orientated-particles-in-3d-refinement/9893 — FETCHED
- https://discuss.cryosparc.com/t/poor-2d-class-average/15621 — FETCHED
- https://discuss.cryosparc.com/t/assess-the-picking-and-the-2d-classes-quality-for-small-low-snr-particles/16482 — FETCHED

---

## Key Findings by Gate

### Gate: motion_drift

**Thread: motion-correction-with-severe-stage-drift (11994)**

This thread is one of the highest-value finds: a user successfully resolved severe stage drift and achieved **3.1 Å** by following two specific recommendations.

- **olibclarke** (community expert, 2023-08-24):
  > "Using less patches may help… What does it look like if you just run with 3x3 or 4x4 patches?"
  > "it is also possible that discarding the last few frames (after ~16) might be worth considering"

- **asgodoy** (original poster, 2023-08-29):
  > "followed both olib suggestions and got 3.1A"

- **rbs_sci** noted the accelerated drift may indicate specimen hole melt during imaging.

**Actionable rule:** When motion correction quality is poor due to stage drift, reduce patch grid from default to 3×3 or 4×4, and truncate frames beyond frame 16.

---

**Thread: patch-motion-correction-query (12723)**

High-value clarification from **hsnyder (CryoSPARC team)** on how patch motion parameters actually work:

> "The number of patches is 'set to a specific physical area in Å and cannot be set by the user.'"

> "Lower knot counts produce 'smoother curve[s]...by reducing the degrees of freedom that patch motion has to fit the data.'"

Key values:
- K_z auto-calculated as `(dose per frame per Å²) × (number of frames) / calibrated_constant`
- Example: ~1.5 e⁻/Å²/frame × 102 frames → K_z=15; overriding nominal dose to 1 e⁻/Å²/frame → K_z=11

**Actionable rule:** When motion correction is noisy/over-fitted, lower K_z (temporal knot count) to smooth trajectories. When comparing dose values, fix K_z to the value estimated for the nominal dose to isolate variables.

---

### Gate: ctf_fit_quality

**Thread: threshold-for-ctf-fit-in-patch-ctf (5449)**

Developer-confirmed value:

- **Igor** (community): asked if the CC threshold for CTF fit resolution is adjustable
- **hsnyder (CryoSPARC team)**: confirmed the fixed default is **0.3** and it was not user-adjustable at time of writing (Nov 2020), though a feature request was noted

> "Yes that's correct. At the moment, no there isn't. However, we've noted the request and we will try to include it in a future release."

**Actionable rule:** The 0.3 CC threshold is hardcoded. Users cannot tune it directly; micrograph curation must use the downstream CTF fit resolution value as the rejection criterion instead.

---

**Thread: discrete-ctf-fit-resolution-jumps (5303)**

- **olibclarke**: When CTF fits cluster in discrete jumps near 4 Å (water ring interference):
  > "lowering the maximum resolution used for fitting, say to 4.5 or 5 Å"
  
- **simonbrown**: Restrict defocus search range lower bound to 10,000 Å (1 µm) to prevent spurious fits at very low defocus:
  > "restrict to 10000 to 40000 (1 - 4 micron)"

- **earturo**: Used 5 Å as the CTF fit resolution rejection threshold; initial exclusion was 85% of micrographs, improved to 55% after correcting gain reference.

**Actionable rule:** CTF fit resolution rejection threshold of 5 Å is a common community value. If >50% of micrographs are rejected at 5 Å, suspect a gain reference problem. Lowering the max fitting resolution to 4.5–5 Å can resolve discrete jump artefacts.

---

**Thread: threshold-setting-issue-in-curate-micrographs (24493)**

Bug report + fix:

- Default Curate Micrographs threshold (2.934 Å lower bound) was *excluding* micrographs at exactly that value due to a rounding error
- **sdawood (CryoSPARC team)** confirmed:
  > "The issue has been resolved in v5.0.2 where micrographs with values equal to the default threshold are no longer excluded."

- Workaround prior to v5.0.2 from **CryoEM2**: Set lower bound to 1 Å to ensure all micrographs are kept

**Actionable rule:** On CryoSPARC < v5.0.2, set CTF fit resolution lower bound to 1 Å as the safe default. On v5.0.2+, the bug is fixed.

---

**Thread: poor-patch-ctf-estimation-resolution (24076)**

- **jcoleman**: Correlates CTF fit resolution with ice thickness measured via energy filter:
  - Ideal ice: 43–45 e⁻/Å² (vacuum dose ~50) → CTF fits 2.8–3 Å
  - Suboptimal ice: 38–39 e⁻/Å² → CTF fits worse than 4 Å

**Actionable rule:** Poor CTF fit resolution (>4 Å across a dataset) is often a sample prep issue (too-thick or too-thin ice), not a CryoSPARC parameter issue. No software parameter change will fully compensate.

---

### Gate: junk_fraction

**Thread: blob-pick-does-not-pick-the-right-particles (13944)**

High-value thread for junk fraction gate. User's original parameters had lowpass filters at 5–10 Å — community flagged this as the root cause.

- **rbs_sci**:
  > "at the frequency cutoffs you are using, you are picking high-frequency noise. The recommended approach uses 'lowpass filter to 20 (default) or even 30 A.'"

- **rwaldo**: For external templates specifically, 30 Å is the minimum safe value

- User revised: min/max diameter 70/170 Å, lowpass 20 Å (both channels), box size 360 Å

**Actionable rules:**
- Blob picker lowpass filter ≥ 20 Å (default); 30 Å for external templates
- Never go below 20 Å for template or micrograph lowpass in Blob Picker
- If junk fraction is high after correct lowpass settings, narrow the diameter range

---

**Thread: poor-2d-class-average (15621)**

- **cbeck** (experienced community member):
  - For high junk fraction: use 3–8 "decoy" classes (generated by killing ab initio after first iteration) to absorb junk
  > "remove particles: repeat until junk comprises '<5% of the total particle stack'"
  - Increase online-EM iterations to ~80 for low-SNR particles
  - For large box sizes (e.g., 360 px), Fourier-crop to 1/3 box size (120 px) before 2D classification
  > "for a box size of 360, I usually bin to 120"

**Actionable rules:**
- Stop condition for junk cleanup: junk < 5% of total stack
- 80 online-EM iterations for low-SNR datasets (vs. default ~40)
- Bin to ~1/3 box size for 2D classification speed

---

**Thread: assess-the-picking-and-the-2d-classes-quality-for-small-low-snr-particles (16482)**

- **CryoEM2**: 2D classification should not aggressively filter particles — use for initial cleanup only
  > "should not be used to filter the particle set to a tiny, high quality set. Use heterogeneous refinement for that"
- Topaz training: "use 1000–5000 great particles to train if possible after stringent 2D cleaning"; precision as low as 0.0012 is acceptable

---

### Gate: orientation_anisotropy

**Thread: preferred-orientation-issue (14664)**

- **rbs_sci**:
  > "92% cutoff worked best; 89% cutoff effective for another dataset"
  > "That preferred orientation isn't actually too bad"
- **Mark-A-Nakasone**: Try Rebalance 2D Classes first; Rebalance Orientations "less luck" historically

**Actionable rule:** First-pass percentile cutoff starting point: 89–92%. Prefer Rebalance 2D Classes over Rebalance Orientations when rare views are visible in 2D.

---

**Thread: rebalance-orientations-survey-question (24530)**

Most detailed parameter breakdown available for Rebalance Orientations:

- **Mark-A-Nakasone**:
  > "Number of orientation bins, Rebalance percentile (usually 5 to 90%), and intra-bin exclusion criterion"
  > Exclusion criterion options: alignments3D/alpha, random, pick_stats/ncc_score, alignments3D/error, alignments2D/error

- **rwaldo** on exclusion mode:
  > "I haven't seen one mode perform reliably better than the others"
  — Prefers `random` because anisotropic modes can produce "misleading high-quality metrics that mask problematic particles"

**Actionable rules:**
- Percentile range: 5–90% (start around 50%, adjust iteratively)
- Exclusion mode: `random` is the safest default
- Expect "slight changes to cFAR/anisotropy"; do not expect dramatic resolution improvement

---

**Thread: possible-preferred-orientation-how-to-improve-data (13341)**

Two-stage percentile strategy from **Jan_Felix**:
- Round 1: percentile threshold = 60 (random mode)
- Round 2: percentile threshold = 5 (random mode)

**Moritz** strategy for datasets with strong preferred orientation:
> "1 good reference + 5 bad references. Repeat this for 3 rounds, only keeping particles from the good class"

**Mark-A-Nakasone** on 2D parameters for preferred orientation:
> "140-200 classes, 40 online EM iterations; Rebalance 2D Job: Down sampling factor = 4, rebalancing = 1, number of super classes = 6-10"

---

**Thread: preferred-orientation-in-small-protein (16619)**

Critical warning from **rbs_sci (CryoSPARC team member)**:
> "Often, you need to adjust the threshold for removal for optimal results"

And an important negative finding: Rebalance Orientations in this thread artificially improved distribution statistics but **degraded final map resolution after Nu-refinement**. Genuine particle diversity (from sample prep or better picking) is required.

---

### Gate: abinitio_class_score

**Thread: ab-initio-is-giving-more-or-less-similar-classes (14422)**

Best single thread for ab initio parameter guidance.

- **MLiziczai**:
  > "set 'Number of initial iterations' to something like 1000; having nr. of initial iterations below 500 does nothing"

- **CryoEM2** on class count:
  > "run again with 2, 3, 4, 5 classes"

- **CryoEM2** on class similarity (critical):
  > "set class similarity to 1 so all classes try to make a very similar model. When set to 0.1, the models will generally derive from the particles of a single view."

**Actionable rules:**
- If ab initio produces similar classes: reduce class count to 2–5; increase initial iterations to ≥1000
- Class similarity = 1 for standard use; class similarity = 0 only when seeking structural heterogeneity
- Do not use ab initio for particle selection — use it to generate references, then run heterogeneous refinement

---

## Gaps Still Open

The following topics have no useful quantitative forum data in the fetched threads:

1. **CTF fit resolution numerical threshold consensus** — The community uses 5–8 Å as typical rejection cutoffs, but no single authoritative value is endorsed by the CryoSPARC team. The 0.3 CC threshold is hardcoded and not a tuning target.

2. **Motion correction: specific K_z adjustment rules** — The team explanation (thread 12723) describes the formula but does not give a recommended range for K_z when drift is a problem. Community practice of "reduce patches" translates to the old GUI language; in current CryoSPARC the equivalent is reducing K_z.

3. **Junk fraction absolute threshold** — The "< 5% junk" stopping rule (from cbeck) is the only numeric guidance found; no CryoSPARC team confirmation.

4. **Orientation anisotropy severity threshold** — No thread provides a numeric metric (e.g., CFAR value or 3D-FSC sphericity score) at which rebalancing is recommended vs. abandoned. The decision appears to be entirely judgment-based.

5. **Ab initio: minimum particle count per class** — Thread 10271 asks this question for a 100k-particle, 150 kDa flexible protein but received no authoritative answer.

6. **Template picker NCC score threshold for junk rejection** — Not found in any fetched thread.

---

## Assessment: Does Forum Data Change the Knowledge Base?

**Yes, meaningfully, in three areas:**

1. **Motion correction (high value):** The 3×3/4×4 patch + frame-16 truncation rule is a concrete, outcome-verified intervention not covered in methods papers. The K_z formula clarification from the CryoSPARC team (thread 12723) is the authoritative source for understanding what "reduce patches" actually means in current CryoSPARC.

2. **CTF fit (medium value):** The hardcoded 0.3 CC threshold (developer-confirmed) explains why CTF fit resolution is the only actionable curation metric. The 5 Å rejection threshold is a widely-used community norm. The v5.0.2 boundary rounding bug fix is operationally important.

3. **Junk fraction / 2D classification (medium value):** The "< 5% junk" stopping rule, the 20–30 Å lowpass floor, and the decoy-class strategy give concrete auto-loop stopping conditions. The warning against aggressive 2D curation (use heterogeneous refinement instead) shifts the architecture.

**Weaker areas:**
- Orientation anisotropy: forum data confirms 89–92% percentile as a starting range but provides no convergence criterion.
- Ab initio: confirms 2–5 classes as practical advice but provides no success-rate data by class count.

**Total entries extracted:** 35 entries across 5 gates, sourced from 11 threads (plus 8 additional threads found via search). 7 entries carry "confirmed" confidence (direct CryoSPARC team responses); 7 carry "reported_worked" (user confirmed success); 21 carry "suggested" (advice given without confirmed outcome).

Gate breakdown:
- motion_drift: 6 entries (2 confirmed, 3 reported_worked, 1 suggested)
- ctf_fit_quality: 8 entries (4 confirmed, 1 reported_worked, 3 suggested)
- junk_fraction: 8 entries (0 confirmed, 2 reported_worked, 6 suggested)
- orientation_anisotropy: 8 entries (1 confirmed, 1 reported_worked, 6 suggested)
- abinitio_class_score: 5 entries (0 confirmed, 0 reported_worked, 5 suggested)
