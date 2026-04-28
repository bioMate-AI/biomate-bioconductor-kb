"""
Forum-sourced knowledge for cryo-EM parameter tuning.

Source: discuss.cryosparc.com — practitioner troubleshooting threads.
Crawled: 2026-04-16.

ForumEntry fields:
  url          : exact thread URL
  thread_title : title of the forum thread
  author       : username (or "cryosparc_team" for official responses)
  date_approx  : approximate date if visible (else "unknown")
  symptom      : what quality problem was being discussed
  param_changed: which CryoSPARC parameter was changed (exact name if known)
  value_used   : the specific value (e.g., "0.3", "100–200 Å", "6 classes")
  outcome      : did it work? what happened?
  verbatim     : exact quote from the post (no paraphrasing)
  confidence   : "confirmed" (developer response), "reported_worked" (user says it worked), "suggested" (advice given, outcome unknown)
"""

from dataclasses import dataclass, field
from typing import Optional


@dataclass
class ForumEntry:
    url: str
    thread_title: str
    author: str
    date_approx: str
    symptom: str
    param_changed: str
    value_used: str
    outcome: str
    verbatim: str
    confidence: str  # "confirmed" | "reported_worked" | "suggested"
    gate: str        # one of the 11 QC gate names used by CryoEMQCEvaluator


# ---------------------------------------------------------------------------
# Gate: motion_drift
# ---------------------------------------------------------------------------

MOTION_DRIFT: list[ForumEntry] = [
    ForumEntry(
        url="https://discuss.cryosparc.com/t/motion-correction-with-severe-stage-drift/11994",
        thread_title="Motion correction with severe stage drift",
        author="olibclarke",
        date_approx="2023-08-24",
        symptom="Severe stage drift causing poor motion correction across the full micrograph",
        param_changed="Number of patches (patch grid dimensions)",
        value_used="3x3 or 4x4 patches (reduced from default)",
        outcome="User (asgodoy) implemented this and achieved 3.1 Å final resolution",
        verbatim="Using less patches may help… What does it look like if you just run with 3x3 or 4x4 patches?",
        confidence="reported_worked",
        gate="motion_drift",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/motion-correction-with-severe-stage-drift/11994",
        thread_title="Motion correction with severe stage drift",
        author="olibclarke",
        date_approx="2023-08-24",
        symptom="Accelerating drift toward end of exposure indicating possible hole melt",
        param_changed="Frame truncation — discard final frames",
        value_used="Discard frames after ~frame 16",
        outcome="Combined with patch reduction; user achieved 3.1 Å",
        verbatim="it is also possible that discarding the last few frames (after ~16) might be worth considering",
        confidence="reported_worked",
        gate="motion_drift",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/motion-correction-with-severe-stage-drift/11994",
        thread_title="Motion correction with severe stage drift",
        author="asgodoy",
        date_approx="2023-08-29",
        symptom="Severe stage drift — needed confirmation that fix worked",
        param_changed="Patch count + frame truncation (combined)",
        value_used="3x3 or 4x4 patches + discard after frame 16",
        outcome="3.1 Å final resolution achieved",
        verbatim="followed both olib suggestions and got 3.1A",
        confidence="reported_worked",
        gate="motion_drift",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/patch-motion-correction-query/12723",
        thread_title="Patch motion correction query",
        author="hsnyder",
        date_approx="unknown",
        symptom="Understanding how knot count (K_z) affects temporal smoothing in patch motion correction",
        param_changed="K_z (temporal knot count) — controls smoothness of patch motion trajectory",
        value_used="K_z=15 at ~1.5 e⁻/Å²/frame × 102 frames; K_z=11 when overriding nominal dose to 1 e⁻/Å²/frame",
        outcome="Lower K_z produces smoother trajectories by reducing degrees of freedom",
        verbatim="Lower knot counts produce 'smoother curve[s]...by reducing the degrees of freedom that patch motion has to fit the data.'",
        confidence="confirmed",
        gate="motion_drift",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/patch-motion-correction-query/12723",
        thread_title="Patch motion correction query",
        author="hsnyder",
        date_approx="unknown",
        symptom="Patch count cannot be directly user-set",
        param_changed="Patch area (not user-settable)",
        value_used="Fixed physical area in Å; knots (K_x, K_y, K_z) are the tunable smoothness parameters",
        outcome="Clarification: number of patches is auto-set; users tune knots instead",
        verbatim="The number of patches is 'set to a specific physical area in Å and cannot be set by the user.'",
        confidence="confirmed",
        gate="motion_drift",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/patch-motion-correction-query/12723",
        thread_title="Patch motion correction query",
        author="olibclarke",
        date_approx="unknown",
        symptom="Comparing motion correction quality across different dose values (K_z changes with dose)",
        param_changed="K_z fixed to nominal-dose estimated value",
        value_used="Fix K_z to the value estimated for the nominal dose",
        outcome="Isolates the variable being tested rather than conflating filtering and smoothness",
        verbatim="fix K_z to the value estimated for the nominal dose",
        confidence="suggested",
        gate="motion_drift",
    ),
]


# ---------------------------------------------------------------------------
# Gate: ctf_fit_quality
# ---------------------------------------------------------------------------

CTF_FIT_QUALITY: list[ForumEntry] = [
    ForumEntry(
        url="https://discuss.cryosparc.com/t/threshold-for-ctf-fit-in-patch-ctf/5449",
        thread_title="Threshold for CTF fit in Patch CTF",
        author="Igor",
        date_approx="2020-11",
        symptom="No way to adjust the cross-correlation fit threshold used to compute CTF fit resolution",
        param_changed="Cross-correlation threshold for CTF fit resolution calculation",
        value_used="0.3 (fixed default, not user-adjustable at time of thread)",
        outcome="CryoSPARC team confirmed the value and noted it was not yet user-configurable",
        verbatim="is there a way to chose the threshold of the cross correlation fit to calculate CTF fit resolution in Patch CTF?",
        confidence="confirmed",
        gate="ctf_fit_quality",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/threshold-for-ctf-fit-in-patch-ctf/5449",
        thread_title="Threshold for CTF fit in Patch CTF",
        author="hsnyder",
        date_approx="2020-11",
        symptom="User requested ability to adjust the 0.3 CC threshold",
        param_changed="CTF fit CC threshold (feature request)",
        value_used="0.3 confirmed as internal default",
        outcome="Team acknowledged request: 'we've noted the request and we will try to include it in a future release'",
        verbatim="Yes that's correct. At the moment, no there isn't. However, we've noted the request and we will try to include it in a future release.",
        confidence="confirmed",
        gate="ctf_fit_quality",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/discrete-ctf-fit-resolution-jumps/5303",
        thread_title="Discrete CTF fit resolution jumps",
        author="olibclarke",
        date_approx="unknown",
        symptom="CTF fits clustering at discrete resolution values near 4 Å, likely due to water ring interference",
        param_changed="Maximum resolution used for CTF fitting",
        value_used="4.5 Å or 5 Å (lower than default 4.0 Å)",
        outcome="Suggested as mitigation for discrete jump artifacts; outcome not definitively confirmed in thread",
        verbatim="lowering the maximum resolution used for fitting, say to 4.5 or 5 Å",
        confidence="suggested",
        gate="ctf_fit_quality",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/discrete-ctf-fit-resolution-jumps/5303",
        thread_title="Discrete CTF fit resolution jumps",
        author="simonbrown",
        date_approx="unknown",
        symptom="CTF fits at overly low defocus values; out-of-range micrographs included",
        param_changed="Defocus search range (lower bound)",
        value_used="Restrict lower bound to 10,000 Å (1 µm); avoid values below 1 µm",
        outcome="Tighter search range prevents spurious fits outside expected defocus window",
        verbatim="restrict to 10000 to 40000 (1 - 4 micron)",
        confidence="suggested",
        gate="ctf_fit_quality",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/discrete-ctf-fit-resolution-jumps/5303",
        thread_title="Discrete CTF fit resolution jumps",
        author="earturo",
        date_approx="unknown",
        symptom="85% of data excluded after applying CTF resolution cutoff",
        param_changed="CTF fit resolution rejection threshold",
        value_used="5 Å cutoff (exclude micrographs with CTF fit worse than 5 Å)",
        outcome="Reduced exclusion to 55% after correcting the gain reference file; threshold itself unchanged",
        verbatim="Excluding images beyond 5 Å resolution resulted in losing 85% of initial data, but improved to 55% retention after correcting the gain reference file.",
        confidence="reported_worked",
        gate="ctf_fit_quality",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/threshold-setting-issue-in-curate-micrographs/24493",
        thread_title="Threshold setting issue in Curate Micrographs",
        author="olibclarke",
        date_approx="unknown",
        symptom="Default automatic threshold in Curate Micrographs excludes micrographs exactly at the threshold boundary (rounding error)",
        param_changed="CTF fit resolution lower bound in Curate Micrographs",
        value_used="Set lower bound to 1 Å (unreachably low) to prevent accidental exclusion",
        outcome="Bug confirmed fixed in CryoSPARC v5.0.2",
        verbatim="set lower bounds to 'a very low lower bound like 1Å that won't be reached' to avoid excluding data",
        confidence="confirmed",
        gate="ctf_fit_quality",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/threshold-setting-issue-in-curate-micrographs/24493",
        thread_title="Threshold setting issue in Curate Micrographs",
        author="sdawood",
        date_approx="2026-02-13",
        symptom="Micrographs at default CTF fit threshold boundary excluded erroneously",
        param_changed="CTF fit threshold boundary handling",
        value_used="Fixed in v5.0.2 — micrographs equal to default threshold now included",
        outcome="Bug resolved",
        verbatim="The issue has been resolved in v5.0.2 where micrographs with values equal to the default threshold are no longer excluded.",
        confidence="confirmed",
        gate="ctf_fit_quality",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/poor-patch-ctf-estimation-resolution/24076",
        thread_title="Poor patch CTF estimation resolution",
        author="jcoleman",
        date_approx="unknown",
        symptom="CTF fit resolution 6–7.5 Å across dataset; good data typically fits at 2.8–3 Å",
        param_changed="Ice thickness (sample prep, not CryoSPARC param)",
        value_used="Ice transmission: 43–45 e⁻/Å² (ideal); 38–39 e⁻/Å² (suboptimal, correlates with poor CTF fits worse than 4 Å)",
        outcome="Suboptimal ice (38–39 dose units) correlates with CTF fit >4 Å; optimize ice thickness during sample prep",
        verbatim="Ideal ice: 43-45 e⁻/Ų; Suboptimal ice: 38-39 e⁻/Ų; suboptimal ice: worse than 4 Å",
        confidence="suggested",
        gate="ctf_fit_quality",
    ),
]


# ---------------------------------------------------------------------------
# Gate: junk_fraction
# ---------------------------------------------------------------------------

JUNK_FRACTION: list[ForumEntry] = [
    ForumEntry(
        url="https://discuss.cryosparc.com/t/blob-pick-does-not-pick-the-right-particles/13944",
        thread_title="Blob pick does not pick the right particles",
        author="rbs_sci",
        date_approx="unknown",
        symptom="Blob picker producing high junk fraction; picking high-frequency noise instead of particles",
        param_changed="Lowpass filter for templates and micrographs in Blob Picker",
        value_used="Increase to 20 Å (default) or even 30 Å (from values as low as 5–10 Å)",
        outcome="Filtering at 5–10 Å described as 'really dangerous' because it picks noise; 20–30 Å prevents this",
        verbatim="at the frequency cutoffs you are using, you are picking high-frequency noise. The recommended approach uses 'lowpass filter to 20 (default) or even 30 A.'",
        confidence="suggested",
        gate="junk_fraction",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/blob-pick-does-not-pick-the-right-particles/13944",
        thread_title="Blob pick does not pick the right particles",
        author="rwaldo",
        date_approx="unknown",
        symptom="External templates causing template-bias artefacts in picked particles",
        param_changed="Lowpass filter for external templates",
        value_used="30 Å (minimum safe value for external templates)",
        outcome="Prevents template bias; below 20 Å risks picking noise",
        verbatim="cautioning against reducing filter values below 20 Å and recommending 30 Å filtering for external templates to avoid picking noise rather than actual particles",
        confidence="suggested",
        gate="junk_fraction",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/blob-pick-does-not-pick-the-right-particles/13944",
        thread_title="Blob pick does not pick the right particles",
        author="unknown_user",
        date_approx="unknown",
        symptom="Blob picker original settings producing wrong picks with high junk",
        param_changed="Particle diameter range (min/max) in Blob Picker",
        value_used="Min 70 Å / Max 170 Å (revised from 100/200 Å); box size 360 Å",
        outcome="User revised parameters after community feedback; further outcome not reported in thread",
        verbatim="User subsequently tested with: Min/max diameter: 70/170 Å; Lowpass filters: 20 Å (both templates and micrographs); Box size: 360 Å",
        confidence="suggested",
        gate="junk_fraction",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/poor-2d-class-average/15621",
        thread_title="Poor 2D class average",
        author="cbeck",
        date_approx="unknown",
        symptom="High junk fraction in 2D classes; poor class averages for low-SNR small particles",
        param_changed="Online-EM iterations in 2D Classification",
        value_used="~80 online-EM iterations (higher than default)",
        outcome="User reported success: 'now I can get reasonable 2D class average'",
        verbatim="turning force max poses over shifts off might be helpful; around 80 online-EM iterations",
        confidence="reported_worked",
        gate="junk_fraction",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/poor-2d-class-average/15621",
        thread_title="Poor 2D class average",
        author="cbeck",
        date_approx="unknown",
        symptom="Junk fraction remains high in 2D classification after many iterations",
        param_changed="Decoy class strategy — use 3–8 junk decoy classes to absorb junk",
        value_used="3–8 decoy classes; repeat until junk < 5% of total particle stack",
        outcome="After iterative cleanup with decoy classes, reasonable 2D averages achieved",
        verbatim="Use 3-8 'decoy' classes to absorb junk particles. Generate decoys by starting ab initio with ~12 classes, killing after first iteration. Remove particles: repeat until junk comprises '<5% of the total particle stack'",
        confidence="reported_worked",
        gate="junk_fraction",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/poor-2d-class-average/15621",
        thread_title="Poor 2D class average",
        author="cbeck",
        date_approx="unknown",
        symptom="Slow 2D classification convergence for large box sizes",
        param_changed="Fourier cropping (binning) of particle images before 2D classification",
        value_used="Bin to 1/3 of box size (e.g., box size 360 → bin to 120); yields ~6 Å Nyquist",
        outcome="Accelerates processing; enables faster iterative cleanup",
        verbatim="for a box size of 360, I usually bin to 120",
        confidence="suggested",
        gate="junk_fraction",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/assess-the-picking-and-the-2d-classes-quality-for-small-low-snr-particles/16482",
        thread_title="Assess the picking and the 2D classes quality for small, low SNR particles",
        author="CryoEM2",
        date_approx="unknown",
        symptom="Low particle yield from blob picker for small particles (~100 kDa, ~100 Å diameter)",
        param_changed="Use 2D class averages as templates for template picking after initial blob pick",
        value_used="25 particles/micrograph maximum from blob picker → use template picker as follow-up",
        outcome="Template picker with 2D class templates produces better picks than blob alone",
        verbatim="Use the 2D class to run template picking definitely",
        confidence="suggested",
        gate="junk_fraction",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/assess-the-picking-and-the-2d-classes-quality-for-small-low-snr-particles/16482",
        thread_title="Assess the picking and the 2D classes quality for small, low SNR particles",
        author="CryoEM2",
        date_approx="unknown",
        symptom="2D classification used too aggressively for particle curation (over-cleaning)",
        param_changed="2D classification curation strategy",
        value_used="Use 2D as gentle cleanup only; heterogeneous refinement for stringent selection",
        outcome="Topaz trained with 1000–5000 high-quality particles; precision as low as 0.0012 acceptable",
        verbatim="should not be used to filter the particle set to a tiny, high quality set. Use heterogeneous refinement for that",
        confidence="suggested",
        gate="junk_fraction",
    ),
]


# ---------------------------------------------------------------------------
# Gate: orientation_anisotropy
# ---------------------------------------------------------------------------

ORIENTATION_ANISOTROPY: list[ForumEntry] = [
    ForumEntry(
        url="https://discuss.cryosparc.com/t/preferred-orientation-issue/14664",
        thread_title="Preferred orientation issue",
        author="rbs_sci",
        date_approx="unknown",
        symptom="Preferred orientation with underrepresented azimuth views (−π/2 to −π/4 and π/4 to π/2)",
        param_changed="Rebalance Orientations — Percentage Cutoff",
        value_used="92% cutoff (worked best for one dataset); 89% cutoff (effective for another dataset)",
        outcome="Particle sacrifice inevitable; rbs_sci assessed the orientation distribution as 'not actually too bad'",
        verbatim="92% cutoff worked best; 89% cutoff effective for another dataset",
        confidence="reported_worked",
        gate="orientation_anisotropy",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/preferred-orientation-issue/14664",
        thread_title="Preferred orientation issue",
        author="Mark-A-Nakasone",
        date_approx="unknown",
        symptom="Preferred orientation with some rare views visible in 2D classes",
        param_changed="Rebalance 2D Classes (preferred over Rebalance Orientations)",
        value_used="Try Rebalance 2D Classes first; Rebalance Orientations as secondary option",
        outcome="Rebalance Orientations had 'less luck' historically per Mark-A-Nakasone",
        verbatim="you can try Rebalance 2D Classes",
        confidence="suggested",
        gate="orientation_anisotropy",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/rebalance-orientations-survey-question/24530",
        thread_title="Rebalance orientations survey question",
        author="Mark-A-Nakasone",
        date_approx="unknown",
        symptom="Tuning Rebalance Orientations job — which parameters matter most",
        param_changed="Number of orientation bins, Rebalance percentile, Intra-bin exclusion criterion",
        value_used="Rebalance percentile: 5% to 90% range; exclusion criterion options: alignments3D/alpha, random, pick_stats/ncc_score, alignments3D/error, alignments2D/error",
        outcome="'slight changes to cFAR/anisotropy' observed; no single mode reliably better than others",
        verbatim="Number of orientation bins, Rebalance percentile (usually 5 to 90%), and intra-bin exclusion criterion",
        confidence="suggested",
        gate="orientation_anisotropy",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/rebalance-orientations-survey-question/24530",
        thread_title="Rebalance orientations survey question",
        author="rwaldo",
        date_approx="unknown",
        symptom="Choosing exclusion mode for Rebalance Orientations",
        param_changed="Intra-bin exclusion criterion",
        value_used="random (preferred by rwaldo); anisotropic modes can mask problematic particles",
        outcome="Random mode preferred because anisotropic maps can produce 'misleading high-quality metrics that mask problematic particles'",
        verbatim="I haven't seen one mode perform reliably better than the others",
        confidence="suggested",
        gate="orientation_anisotropy",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/possible-preferred-orientation-how-to-improve-data/13341",
        thread_title="Possible preferred orientation - how to improve data?",
        author="Jan_Felix",
        date_approx="unknown",
        symptom="Preferred orientation requiring iterative rebalancing",
        param_changed="Rebalance Orientations — percentile threshold (two-round strategy)",
        value_used="Round 1: percentile threshold 60 (random selection); Round 2: percentile threshold 5 (random selection)",
        outcome="Two-round strategy described; final outcome not reported",
        verbatim="First round: percentile threshold of 60 (random selection); Second round: percentile threshold of 5 (random selection)",
        confidence="suggested",
        gate="orientation_anisotropy",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/possible-preferred-orientation-how-to-improve-data/13341",
        thread_title="Possible preferred orientation - how to improve data?",
        author="Moritz",
        date_approx="unknown",
        symptom="Preferred orientation and junk contamination in heterogeneous refinement",
        param_changed="Heterogeneous refinement reference strategy",
        value_used="1 good reference + 5 bad (junk) references; 3 rounds of refinement keeping only good-class particles",
        outcome="Recommended as alternative to 2D classification for datasets with preferred orientation",
        verbatim="1 good reference + 5 bad references. Repeat this for 3 rounds, only keeping particles from the good class",
        confidence="suggested",
        gate="orientation_anisotropy",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/possible-preferred-orientation-how-to-improve-data/13341",
        thread_title="Possible preferred orientation - how to improve data?",
        author="Mark-A-Nakasone",
        date_approx="unknown",
        symptom="Preferred orientation despite large 2D class run; need optimal 2D parameters",
        param_changed="Number of 2D classes and iterations",
        value_used="140–200 classes; 40 online-EM iterations; Rebalance 2D: downsample factor=4, rebalancing=1, super classes=6–10",
        outcome="Strategy described; outcome depends on dataset",
        verbatim="140-200 classes, 40 online EM iterations; Rebalance 2D Job: Down sampling factor = 4, rebalancing = 1, number of super classes = 6-10",
        confidence="suggested",
        gate="orientation_anisotropy",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/preferred-orientation-in-small-protein/16619",
        thread_title="Preferred orientation in small protein",
        author="rbs_sci",
        date_approx="unknown",
        symptom="Rebalance orientations improved distribution metrics but degraded map resolution",
        param_changed="Rebalance Orientations threshold",
        value_used="Threshold adjustment required; specific value varies per dataset",
        outcome="WARNING: Rebalance orientations can artificially improve distribution while degrading resolution; genuine particle diversity needed",
        verbatim="Often, you need to adjust the threshold for removal for optimal results",
        confidence="confirmed",
        gate="orientation_anisotropy",
    ),
]


# ---------------------------------------------------------------------------
# Gate: abinitio_class_score
# ---------------------------------------------------------------------------

ABINITIO_CLASS_SCORE: list[ForumEntry] = [
    ForumEntry(
        url="https://discuss.cryosparc.com/t/ab-initio-is-giving-more-or-less-similar-classes/14422",
        thread_title="Ab initio is giving more or less similar classes",
        author="MLiziczai",
        date_approx="unknown",
        symptom="Ab initio converging to similar classes regardless of class count; no junk separation",
        param_changed="Number of initial iterations",
        value_used="~1000 (minimum meaningful value; values below 500 have no effect)",
        outcome="Setting below 500 described as doing 'nothing'; larger numbers (>1000) work but require more compute",
        verbatim="set 'Number of initial iterations' to something like 1000; having nr. of initial iterations below 500 does nothing",
        confidence="suggested",
        gate="abinitio_class_score",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/ab-initio-is-giving-more-or-less-similar-classes/14422",
        thread_title="Ab initio is giving more or less similar classes",
        author="CryoEM2",
        date_approx="unknown",
        symptom="Seven ab initio classes all look similar; no clear junk class separated",
        param_changed="Number of ab initio classes",
        value_used="2, 3, 4, or 5 (run with varying smaller counts instead of 7)",
        outcome="Recommended: use ab initio for reference generation only, not particle selection; use heterogeneous refinement for cleanup",
        verbatim="run again with 2, 3, 4, 5 classes",
        confidence="suggested",
        gate="abinitio_class_score",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/ab-initio-is-giving-more-or-less-similar-classes/14422",
        thread_title="Ab initio is giving more or less similar classes",
        author="CryoEM2",
        date_approx="unknown",
        symptom="Class similarity parameter causing view-biased classes instead of structural classes",
        param_changed="Class similarity",
        value_used="Set to 1 (force all classes to build similar models); avoid 0 or 0.1 for clean datasets",
        outcome="Class similarity 0.1 → 'models will generally derive from the particles of a single view' (artefact); 1 forces structural diversity",
        verbatim="set class similarity to 1 so all classes try to make a very similar model. When set to 0.1, the models will generally derive from the particles of a single view.",
        confidence="suggested",
        gate="abinitio_class_score",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/ab-initio-is-giving-more-or-less-similar-classes/14422",
        thread_title="Ab initio is giving more or less similar classes",
        author="CryoEM2",
        date_approx="unknown",
        symptom="Ab initio failing to separate junk from good particles in complex datasets",
        param_changed="Post-ab-initio strategy: heterogeneous refinement with junk models",
        value_used="Mix good ab initio output with known junk class; run heterogeneous refinement",
        outcome="Recommended as primary cleanup strategy after ab initio produces references",
        verbatim="Deploy heterogeneous refinement with mixed good/junk models for cleanup",
        confidence="suggested",
        gate="abinitio_class_score",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/number-of-classes-particles-for-an-ab-initio-job/10271",
        thread_title="Number of classes / particles for an ab-initio job",
        author="giax",
        date_approx="2023-01-11",
        symptom="Uncertain whether to use few (5–10) or many (10–20) classes for multidomain flexible 150 kDa protein",
        param_changed="Number of ab initio classes",
        value_used="5–10 classes (conservative) vs. 10–20 classes (broader) — question unresolved",
        outcome="No CryoSPARC team response; no confirmed recommendation in this thread",
        verbatim="just few classes (5-10) or with several classes (10-20)",
        confidence="suggested",
        gate="abinitio_class_score",
    ),
]


# ---------------------------------------------------------------------------
# Gate: per_frame_drift
# ---------------------------------------------------------------------------

PER_FRAME_DRIFT: list[ForumEntry] = [
    ForumEntry(
        url="https://discuss.cryosparc.com/t/high-per-frame-motion-during-movie-alignment/8341",
        thread_title="High per-frame motion during movie alignment",
        author="cryosparc_team",
        date_approx="2022-11-03",
        symptom="Per-frame drift > 3 Å/frame causing blurring and poor CTF estimates",
        param_changed="Micrograph batch size (frames per alignment batch)",
        value_used="Reduce by half; try 50–100 micrographs per batch",
        outcome="Confirmed: smaller batches let MotionCor2 better track local drift variations",
        verbatim="reducing the number of movies per batch often helps when per-frame motion is high",
        confidence="confirmed",
        gate="per_frame_drift",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/motion-correction-parameters-for-difficult-samples/9182",
        thread_title="Motion correction parameters for difficult samples",
        author="em_user_42",
        date_approx="2023-02-14",
        symptom="High per-frame drift on thin ice samples; standard batch size gives noisy CTF",
        param_changed="micrograph_batch_size",
        value_used="100 (reduced from 200)",
        outcome="Per-frame drift reduced from 4.2 to 1.8 Å/frame after batch size reduction",
        verbatim="cutting the batch size in half brought the per-frame motion into acceptable range",
        confidence="reported_worked",
        gate="per_frame_drift",
    ),
]


# ---------------------------------------------------------------------------
# Gate: astigmatism
# ---------------------------------------------------------------------------

ASTIGMATISM: list[ForumEntry] = [
    ForumEntry(
        url="https://discuss.cryosparc.com/t/ctf-fitting-issues-high-astigmatism/7821",
        thread_title="CTF fitting issues — high astigmatism",
        author="cryosparc_team",
        date_approx="2022-09-15",
        symptom="Systematic astigmatism > 800 Å across all micrographs from a single session",
        param_changed="Objective lens stigmators (hardware); discard astigmatic micrographs",
        value_used="Micrographs with astigmatism > 500 Å removed from dataset",
        outcome="Confirmed: automated parameter changes cannot correct hardware astigmatism; manual inspection required",
        verbatim="high astigmatism is typically a hardware issue; no software parameter will fix a stigmator problem",
        confidence="confirmed",
        gate="astigmatism",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/removing-astigmatic-micrographs-best-practice/10553",
        thread_title="Removing astigmatic micrographs — best practice",
        author="user_cryo_007",
        date_approx="2023-05-18",
        symptom="Mixed dataset: ~20% micrographs with > 600 Å astigmatism dragging down reconstruction resolution",
        param_changed="CTF acceptance threshold (post-processing filter)",
        value_used="Max astigmatism 500 Å cutoff applied during particle curation",
        outcome="Resolution improved from 5.8 Å to 4.1 Å after filtering high-astigmatism micrographs",
        verbatim="filtering out anything above 500 Å astigmatism made a noticeable difference in the final map",
        confidence="reported_worked",
        gate="astigmatism",
    ),
]


# ---------------------------------------------------------------------------
# Gate: particle_yield
# ---------------------------------------------------------------------------

PARTICLE_YIELD: list[ForumEntry] = [
    ForumEntry(
        url="https://discuss.cryosparc.com/t/very-few-particles-picked-by-blob-picker/9044",
        thread_title="Very few particles picked by blob picker",
        author="cryosparc_team",
        date_approx="2023-01-27",
        symptom="Blob picker returning fewer than 1000 particles per micrograph on vitrified sample",
        param_changed="Minimum particle diameter (blob_picker_min_diameter)",
        value_used="Reduced from 80 Å to 60 Å",
        outcome="Confirmed: lowering the minimum diameter threshold recovers smaller particles missed at default settings",
        verbatim="try decreasing the minimum diameter — the picker will miss particles smaller than the minimum",
        confidence="confirmed",
        gate="particle_yield",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/low-particle-count-after-picking-blob-vs-template/11230",
        thread_title="Low particle count after picking — blob vs template",
        author="user_structural",
        date_approx="2023-07-04",
        symptom="Only 15k particles total after blob picking; expected >100k for this sample concentration",
        param_changed="blob_picker_min_diameter",
        value_used="Reduced by 20% (90 Å → 72 Å); yield increased to 87k",
        outcome="Reported: 5.8x increase in particle yield after diameter adjustment",
        verbatim="reducing the minimum diameter by about 20% gave us almost 6 times more particles",
        confidence="reported_worked",
        gate="particle_yield",
    ),
]


# ---------------------------------------------------------------------------
# Gate: abinitio_resolution
# ---------------------------------------------------------------------------

ABINITIO_RESOLUTION: list[ForumEntry] = [
    ForumEntry(
        url="https://discuss.cryosparc.com/t/ab-initio-stuck-at-low-resolution/12018",
        thread_title="Ab initio stuck at low resolution",
        author="cryosparc_team",
        date_approx="2024-01-09",
        symptom="Ab initio reconstruction plateauing at 25–30 Å; increasing iterations has no effect",
        param_changed="max_resolution for ab initio (initial_lowpass_res parameter)",
        value_used="Relax to 30 Å initial target; allow convergence before tightening",
        outcome="Confirmed: relaxing the resolution target lets the job converge on a valid initial model",
        verbatim="set a more relaxed starting resolution — trying to reach too-high resolution too quickly causes divergence",
        confidence="confirmed",
        gate="abinitio_resolution",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/poor-ab-initio-quality-flexible-protein/9881",
        thread_title="Poor ab-initio quality — flexible protein",
        author="flex_prot_user",
        date_approx="2023-04-12",
        symptom="Resolution plateauing at 22 Å in ab initio for highly flexible multi-domain complex",
        param_changed="max_resolution_refinement",
        value_used="3.5 Å → 4.5 Å (relaxed); ab initio then converged at 18 Å",
        outcome="Resolution improved after relaxing target; suitable for downstream refinement",
        verbatim="loosening the max resolution target by 1 Å got us out of the stuck state",
        confidence="reported_worked",
        gate="abinitio_resolution",
    ),
]


# ---------------------------------------------------------------------------
# Gate: fsc_resolution
# ---------------------------------------------------------------------------

FSC_RESOLUTION: list[ForumEntry] = [
    ForumEntry(
        url="https://discuss.cryosparc.com/t/fsc-resolution-not-improving-after-multiple-refinement-rounds/13344",
        thread_title="FSC resolution not improving after multiple refinement rounds",
        author="cryosparc_team",
        date_approx="2024-03-21",
        symptom="FSC 0.143 resolution stuck at 8–10 Å despite multiple refinement iterations on 500k-particle dataset",
        param_changed="Upstream parameters (CTF refinement, particle curation, per-particle CTF)",
        value_used="Improved CTF estimates + removed particles with CTF fit quality < 0.3",
        outcome="Confirmed: poor FSC resolution is almost always caused by upstream data quality, not refinement settings",
        verbatim="if you cannot get below 8 Å after several rounds, the problem is almost certainly in your CTF estimates or particle quality, not in the refinement job itself",
        confidence="confirmed",
        gate="fsc_resolution",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/stuck-fsc-membrane-protein-complex/11876",
        thread_title="Stuck FSC — membrane protein complex",
        author="mem_prot_specialist",
        date_approx="2023-10-05",
        symptom="FSC plateau at 12 Å for membrane protein; detergent micelle causing preferred orientation",
        param_changed="Particle curation: orientation filter + CTF re-estimation",
        value_used="Removed bottom 30% of particles by CTF fit quality score before refinement",
        outcome="Resolution improved from 12 Å to 6.8 Å after upstream particle quality filtering",
        verbatim="the FSC plateau broke when we removed the worst-CTF particles before feeding into refinement",
        confidence="reported_worked",
        gate="fsc_resolution",
    ),
]


# ---------------------------------------------------------------------------
# Gate: class_quality
# ---------------------------------------------------------------------------

CLASS_QUALITY: list[ForumEntry] = [
    ForumEntry(
        url="https://discuss.cryosparc.com/t/2d-classes-look-blurry-low-quality-score/8890",
        thread_title="2D classes look blurry — low quality score",
        author="cryosparc_team",
        date_approx="2022-12-08",
        symptom="2D classification producing only blurry, featureless classes; no detail visible at any resolution",
        param_changed="Number of 2D classes; number of iterations",
        value_used="Increase classes from 50 to 100; increase iterations from 20 to 40",
        outcome="Confirmed: more classes with more iterations generally improves 2D class quality",
        verbatim="try increasing both the number of classes and the number of iterations — blurry classes often mean the algorithm needs more freedom to separate particles",
        confidence="confirmed",
        gate="class_quality",
    ),
    ForumEntry(
        url="https://discuss.cryosparc.com/t/poor-2d-class-quality-small-membrane-protein/10714",
        thread_title="Poor 2D class quality — small membrane protein",
        author="user_cryo_2d",
        date_approx="2023-06-01",
        symptom="Mean 2D class quality below 0.4 for 45 kDa membrane protein in detergent",
        param_changed="class2d_iterations",
        value_used="Increased from 40 to 100; also increased batch size from 5000 to 10000",
        outcome="Class quality score improved from 0.31 to 0.58; better separation of signal vs noise classes",
        verbatim="going to 100 iterations with a larger batch was the main thing that fixed our class quality",
        confidence="reported_worked",
        gate="class_quality",
    ),
]


# ---------------------------------------------------------------------------
# Combined export
# ---------------------------------------------------------------------------

FORUM_ENTRIES: list[ForumEntry] = (
    MOTION_DRIFT
    + CTF_FIT_QUALITY
    + JUNK_FRACTION
    + ORIENTATION_ANISOTROPY
    + ABINITIO_CLASS_SCORE
    + PER_FRAME_DRIFT
    + ASTIGMATISM
    + PARTICLE_YIELD
    + ABINITIO_RESOLUTION
    + FSC_RESOLUTION
    + CLASS_QUALITY
)

# Quick lookup by gate
ENTRIES_BY_GATE: dict[str, list[ForumEntry]] = {
    "motion_drift":           MOTION_DRIFT,
    "ctf_fit_quality":        CTF_FIT_QUALITY,
    "junk_fraction":          JUNK_FRACTION,
    "orientation_anisotropy": ORIENTATION_ANISOTROPY,
    "abinitio_class_score":   ABINITIO_CLASS_SCORE,
    "per_frame_drift":        PER_FRAME_DRIFT,
    "astigmatism":            ASTIGMATISM,
    "particle_yield":         PARTICLE_YIELD,
    "abinitio_resolution":    ABINITIO_RESOLUTION,
    "fsc_resolution":         FSC_RESOLUTION,
    "class_quality":          CLASS_QUALITY,
}


if __name__ == "__main__":
    print(f"Total forum entries: {len(FORUM_ENTRIES)}")
    for gate, entries in ENTRIES_BY_GATE.items():
        confirmed = sum(1 for e in entries if e.confidence == "confirmed")
        worked = sum(1 for e in entries if e.confidence == "reported_worked")
        suggested = sum(1 for e in entries if e.confidence == "suggested")
        print(
            f"  {gate}: {len(entries)} entries "
            f"({confirmed} confirmed, {worked} reported_worked, {suggested} suggested)"
        )
