"""
Seed corpus for the Grounded Standards Assistant prototype.

IMPORTANT — these entries are ILLUSTRATIVE PROTOTYPE FIXTURES, not a controlled
copy of any standard. They model the *shape* of a threshold-provenance chain so
the engine can be demonstrated end to end. Every entry that paraphrases a
standard carries `verified=False` and a citation the reader must confirm against
the controlled document. This is deliberate: the product's whole thesis is that
a regulated-domain assistant must point at a verifiable source rather than
assert from memory, and the prototype holds itself to that same rule.

The worked example is EN 285 steam quality — specifically the question the user
actually cares about: *why is the dryness-value threshold set where it is, what
work produced it, and where does the public record stop.*
"""

from __future__ import annotations

from typing import List

from .models import Source, SourceTier


# ──────────────────────────────────────────────────────────────────────────────
# Shared / global sources (owner=None): standards, literature, QA-approved org KB
# ──────────────────────────────────────────────────────────────────────────────

_SHARED: List[Source] = [
    # ---- Tier A: the normative text (WHAT the number is) --------------------
    Source(
        id="en285-dryness-clause",
        tier=SourceTier.NORMATIVE_PRIMARY,
        title="EN 285 — steam quality: dryness value requirement",
        citation="EN 285:2015 steam-quality clause; test method SHTM 2010 Part 3",
        text=(
            "The standard specifies a minimum dryness value for the steam supplied "
            "to the sterilizer: the dryness value shall be NOT LESS THAN 0.90 — or, "
            "if only metal loads are to be processed, NOT LESS THAN 0.95. This is a "
            "normative requirement: it states the acceptance limit, not its derivation. "
            "(Note: secondary sources frequently transpose the 0.90/0.95 figures — "
            "another reason to read the acceptance value from the controlled standard, "
            "not from memory or a web summary.)"
        ),
        owner=None,
        verified=False,  # paraphrase — reader must confirm against controlled EN 285 copy
        locator="controlled-copy://EN-285/steam-quality",
        keywords=["dryness", "dryness value", "0.95", "0.90", "steam quality", "en 285",
                  "threshold", "limit", "wet steam", "metal load", "porous"],
    ),
    Source(
        id="en285-ncg-clause",
        tier=SourceTier.NORMATIVE_PRIMARY,
        title="EN 285 — steam quality: non-condensable gases & superheat",
        citation="EN 285 steam-quality clauses; test method SHTM 2010 Part 3",
        text=(
            "Companion steam-quality limits in the same standard: non-condensable "
            "gases shall not exceed 3.5 ml of gas per 100 ml of condensate "
            "(commonly MIS-stated as '3.5% by volume' — it is ml per 100 ml of "
            "displaced water), and superheat shall not exceed 25 degrees C, each "
            "measured by the SHTM 2010 Part 3 method. These sit alongside the "
            "dryness-value test as the three steam-quality checks."
        ),
        owner=None,
        verified=False,
        locator="controlled-copy://EN-285/steam-quality",
        keywords=["non-condensable gases", "ncg", "3.5", "superheat", "25",
                  "steam quality", "en 285"],
    ),

    # ---- Tier A/committee: HOW the numbers were arrived at (origin record) ---
    Source(
        id="en285-drafting-basis",
        tier=SourceTier.NORMATIVE_PRIMARY,
        title="Steam-quality limits: documented origin and derivation",
        citation=(
            "K. Shuttleworth, 'The Application of Steam Quality Test Limits'; and "
            "'The Derivation of United Kingdom Physical Steam Quality Test Limits'"
        ),
        text=(
            "The documented origin: the physical steam-quality test limits come "
            "from the British National Health Service, first appearing in HTM 101, "
            "superseded by HTM 2010 and the Scottish SHTM 2010/2031, and later "
            "adopted into EN 285. The published record states the limits were "
            "'established PRAGMATICALLY' — i.e. set empirically, from in-service "
            "experience and expert judgement by the UK working groups, rather than "
            "derived to a specific figure from a single controlled experiment. A "
            "dedicated paper, 'The Derivation of United Kingdom Physical Steam "
            "Quality Test Limits', is the closest thing to a primary rationale."
        ),
        owner=None,
        verified=True,  # real, published industry references (see locator)
        locator="https://gmpua.com/Utilities/Steam/SteamQualityPaper.pdf",
        keywords=["committee", "nhs", "htm", "htm 2010", "shtm", "101", "pragmatic",
                  "consensus", "derivation", "drafting", "why", "rationale",
                  "working group", "revision", "origin", "shuttleworth"],
    ),

    # ---- Tier B: the experimental science (WHY wet steam matters) -----------
    Source(
        id="lit-wet-steam-efficacy",
        tier=SourceTier.PEER_REVIEWED,
        title="Detection of superheated steam during sterilization using biological indicators",
        citation="Detection of Superheated Steam During Sterilization Using Biological "
                 "Indicators (PMC10634659)",
        text=(
            "Peer-reviewed experimental work grounds the MECHANISM behind the "
            "limits: the dryness fraction is tied to the latent heat the steam "
            "carries; excessively dry or superheated steam behaves like hot air and "
            "loses the moist-heat lethality advantage, while over-wet steam deposits "
            "water on the load. Studies using biological indicators demonstrate the "
            "sterilization-efficacy consequences directly. This grounds WHY a "
            "dryness/superheat window exists — but it characterises the effect; it "
            "does not by itself fix the exact numeric cut-off."
        ),
        owner=None,
        verified=True,
        locator="https://pmc.ncbi.nlm.nih.gov/articles/PMC10634659/",
        keywords=["dryness", "latent heat", "penetration", "lethality", "moist heat",
                  "wet steam", "superheat", "biological indicator", "mechanism", "why",
                  "efficacy", "load"],
    ),
    Source(
        id="lit-load-dependence",
        tier=SourceTier.PEER_REVIEWED,
        title="Water quality effect on non-condensable gas concentration in sterilizing steam",
        citation="Analysis of water quality over non-condensable gases concentration on "
                 "steam used for sterilization (PMC9514632)",
        text=(
            "Experimental analysis linking feed-water quality to the non-condensable "
            "gas fraction in sterilizing steam, and thence to penetration and "
            "lethality. It grounds the DIRECTION and mechanism of the NCG limit — "
            "but, like the dryness work, it characterises the relationship rather "
            "than deriving the specific 3.5 ml/100 ml acceptance figure."
        ),
        owner=None,
        verified=True,
        locator="https://pmc.ncbi.nlm.nih.gov/articles/PMC9514632/",
        keywords=["non-condensable gases", "ncg", "water quality", "penetration",
                  "load dependence", "mechanism", "why", "3.5"],
    ),

    # ---- Tier C: QA-approved internal knowledge -----------------------------
    Source(
        id="sop-steam-quality-test",
        tier=SourceTier.ORG_VALIDATED,
        title="Internal SOP: clean-steam quality qualification",
        citation="SOP-ENG-STEAM-014 rev C (QA-approved)",
        text=(
            "Our validated SOP operationalises the EN 285 steam-quality tests "
            "(dryness, non-condensable gases, superheat) with the site test rig, "
            "sampling method, and acceptance limits. It records HOW we test and "
            "WHAT limits we apply; it does not restate the external scientific "
            "derivation of those limits."
        ),
        owner=None,          # QA-approved → shared within the org tenant scope
        verified=True,
        locator="dms://SOP-ENG-STEAM-014",
        keywords=["sop", "steam quality", "qualification", "test rig", "acceptance",
                  "dryness test", "procedure"],
    ),
]


# ──────────────────────────────────────────────────────────────────────────────
# Personal, unverified sources (owner-scoped). Two different users, to exercise
# tenant isolation. NEITHER may ever support a confirmed claim; and user "bob"'s
# note must NEVER surface for user "alice".
# ──────────────────────────────────────────────────────────────────────────────

_PERSONAL: List[Source] = [
    Source(
        id="note-alice-draft",
        tier=SourceTier.UNVERIFIED_PERSONAL,
        title="Alice's working note (draft, unverified)",
        citation="personal note — not reviewed",
        text=(
            "Draft hypothesis: our recurring wet-load deviations may track with a "
            "dryness reading drifting toward the 0.95 limit after the boiler "
            "maintenance window. Needs confirmation — this is my own guess."
        ),
        owner="alice",
        verified=False,
        locator="note://alice/2026-10-02",
        keywords=["dryness", "0.95", "wet load", "deviation", "boiler", "drift"],
    ),
    Source(
        id="note-bob-opinion",
        tier=SourceTier.UNVERIFIED_PERSONAL,
        title="Bob's working note (draft, unverified)",
        citation="personal note — not reviewed",
        text=(
            "I think 0.95 was chosen just to be safe and there's no real study "
            "behind it, we could probably run at 0.90 for everything."
        ),
        owner="bob",
        verified=False,
        locator="note://bob/2026-09-19",
        keywords=["dryness", "0.95", "0.90", "opinion", "no study"],
    ),
]


def load_corpus() -> List[Source]:
    """Return the full seed corpus (shared + all personal, unfiltered).

    Tenant filtering is the retrieval layer's job, not the corpus's — keeping
    them separate is what lets the isolation test prove the filter actually works.
    """
    return list(_SHARED) + list(_PERSONAL)
