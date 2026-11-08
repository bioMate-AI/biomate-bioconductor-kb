"""
Capability-tagged source registry — the dispatcher the router selects over.

BioMate already has `data_sources.py` (a ~58-source catalog: id/name/category/
entity_types/surfaces), but it is introspection-only. This adds the two things a
router needs to reason about WHICH source for WHICH question:

  * `kind`      — what the source is good for (publication / knowledge_base /
                  regulatory / clinical / patent / structure / web)
  * `authority` — the trust tier it feeds into the Grounded lattice (A/B/C)

plus `keyless` (usable today with no credentials) and a per-source `playbook`
(the skill-level query idiom). In production this is `data_sources.py` enriched
with these fields and made the dispatcher; here it's a compact seed.

Patents: keyless lane is EuropePMC's EPO patent records (no new credential);
USPTO ODP/PatentsView is a free-key option (NOT Google Patents — no free API).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import List

from engine.models import SourceTier


# kind constants
PUBLICATION = "publication"
KNOWLEDGE_BASE = "knowledge_base"
REGULATORY = "regulatory"
CLINICAL = "clinical"
PATENT = "patent"
STRUCTURE = "structure"
WEB = "web"


@dataclass
class SourceSpec:
    id: str
    name: str
    kind: str
    authority: SourceTier            # the tier results from this source get
    keyless: bool                    # usable with no credential today
    entity_types: List[str] = field(default_factory=list)
    playbook: str = ""               # skill-level: how to query this source well

    @property
    def tier_label(self) -> str:
        return f"{self.authority.short} ({self.kind})"


# Seed registry. Authority tiers: normative/guidance -> A; peer-reviewed + the
# curated KBs -> B; preprint/web -> (still B but lower); clinical registries -> B.
_SOURCES: List[SourceSpec] = [
    # ── publications (peer-reviewed) ────────────────────────────────────────
    SourceSpec("europepmc", "Europe PMC", PUBLICATION, SourceTier.PEER_REVIEWED, True,
               ["literature", "gene", "protein", "disease", "compound"],
               "keyword query; rich abstracts + PMIDs; also indexes EPO PATENTS (SRC:PAT)"),
    SourceSpec("crossref", "Crossref", PUBLICATION, SourceTier.PEER_REVIEWED, True,
               ["literature"], "cross-publisher metadata ~150M works; broadens coverage"),
    SourceSpec("semantic_scholar", "Semantic Scholar", PUBLICATION, SourceTier.PEER_REVIEWED, True,
               ["literature"], "citation graph; influential-paper ranking"),
    SourceSpec("openalex", "OpenAlex", PUBLICATION, SourceTier.PEER_REVIEWED, True,
               ["literature"], "open scholarly graph; concepts/topics"),
    SourceSpec("pubmed", "PubMed", PUBLICATION, SourceTier.PEER_REVIEWED, True,
               ["literature"], "keyless E-utilities throttle — add NCBI key for reliability"),
    SourceSpec("biorxiv", "bioRxiv/medRxiv", PUBLICATION, SourceTier.PEER_REVIEWED, True,
               ["literature"], "PREPRINTS — flag as not-yet-peer-reviewed; good for recency"),

    # ── knowledge bases (structured facts) ──────────────────────────────────
    SourceSpec("chembl", "ChEMBL", KNOWLEDGE_BASE, SourceTier.ORG_VALIDATED, True,
               ["compound"], "bioactivity, IC50/Ki, ADMET endpoints by target"),
    SourceSpec("pubchem", "PubChem", KNOWLEDGE_BASE, SourceTier.ORG_VALIDATED, True,
               ["compound"], "compound properties, assays, SMILES/InChI"),
    SourceSpec("uniprot", "UniProt", KNOWLEDGE_BASE, SourceTier.ORG_VALIDATED, True,
               ["protein", "gene"], "protein function, domains, PTMs"),
    SourceSpec("clinvar", "ClinVar", KNOWLEDGE_BASE, SourceTier.ORG_VALIDATED, True,
               ["variant"], "variant clinical significance + review status"),

    # ── regulatory (normative) ──────────────────────────────────────────────
    SourceSpec("ich_corpus", "ICH/FDA/EMA guidelines", REGULATORY, SourceTier.NORMATIVE_PRIMARY, True,
               ["regulatory", "compound"], "BM25 over guideline text; cite the clause"),

    # ── clinical ────────────────────────────────────────────────────────────
    SourceSpec("clinicaltrials", "ClinicalTrials.gov", CLINICAL, SourceTier.PEER_REVIEWED, True,
               ["disease", "compound"], "trial design, phase, endpoints, status — keyless API"),
    SourceSpec("openfda", "openFDA / FAERS", CLINICAL, SourceTier.PEER_REVIEWED, True,
               ["compound"], "adverse events, labels — keyless API"),

    # ── patents ──────────────────────────────────────────────────────────────
    # Keyless lane = EuropePMC (EP/PCT-centric; MISSES US-only & CN-only filings).
    # NOT Google Patents (no free API) and NOT USPTO ODP (needs a key application).
    SourceSpec("patents_epmc", "Patents (via Europe PMC)", PATENT, SourceTier.PEER_REVIEWED, True,
               ["compound", "literature"],
               "EPO patent docs via EuropePMC SRC:PAT — keyless. COVERAGE: EP/PCT-"
               "centric; does NOT comprehensively cover US-only or CN-only patents. "
               "Flag the gap in the answer when patents are load-bearing."),
    # Worldwide opt-in: EPO OPS INPADOC/DOCDB gives US+EP+CN family coverage, but
    # needs ONE free OAuth registration (credentials, not a paid license). OFF by
    # default (router is keyless-only unless allow_nonkeyless=True). Lens.org is
    # excluded on purpose: free tier is non-commercial only ($1k/yr commercial =
    # a license, which BioMate's commercial use would require).
    SourceSpec("epo_ops", "EPO Open Patent Services (worldwide)", PATENT,
               SourceTier.PEER_REVIEWED, False,
               ["compound", "literature"],
               "INPADOC/DOCDB worldwide bibliographic incl. US + CN; free OAuth "
               "registration required (no cost). Enable via allow_nonkeyless."),

    # ── structure ───────────────────────────────────────────────────────────
    SourceSpec("pdb", "RCSB PDB", STRUCTURE, SourceTier.ORG_VALIDATED, True,
               ["structure", "protein"], "experimental structures"),

    # ── open web (last resort for recency / non-indexed facts) ──────────────
    SourceSpec("web", "Open web search", WEB, SourceTier.UNVERIFIED_PERSONAL, True,
               ["literature", "disease"],
               "lowest trust tier; for recency/news only; must be corroborated"),
]

BY_ID = {s.id: s for s in _SOURCES}


def all_sources() -> List[SourceSpec]:
    return list(_SOURCES)


def by_kind(kind: str) -> List[SourceSpec]:
    return [s for s in _SOURCES if s.kind == kind]


def keyless() -> List[SourceSpec]:
    return [s for s in _SOURCES if s.keyless]
