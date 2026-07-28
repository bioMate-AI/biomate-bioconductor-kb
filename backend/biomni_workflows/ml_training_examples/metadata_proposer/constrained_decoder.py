#!/usr/bin/env python3
# =============================================================================
# metadata_proposer / constrained_decoder.py
# =============================================================================
# CONSTRAINED-DECODING harness for the metadata-mapping proposer.
#
# THE CORE INVARIANT (why this design beats LLM-alone mapping)
# ------------------------------------------------------------
# The proposer can produce EXACTLY one of:
#   - SELECT a candidate that the RETRIEVER pulled from the real ontology, or
#   - ABSTAIN.
# It can NEVER emit an ontology ID that is not in the retrieved candidate set.
# Because every candidate ID comes verbatim from ontology_seed.csv, a
# hallucinated ID is structurally impossible — the output space is the retrieved
# set plus {ABSTAIN}, nothing else. The survey's "~17% out-of-dictionary +
# hallucinated IDs" failure of free-generation LLMs cannot occur here.
#
# TWO PARTS
# ---------
#   Retriever  deterministic string/synonym/token match over the seed dictionary
#              -> a ranked shortlist of grounded candidates (or [] for OOD).
#   Proposer   a RANKER that either SELECTs the best candidate (if it clears an
#              acceptance margin) or ABSTAINs. Runs on CPU, no GPU, no network.
#
# A real per-client LoRA LLM is a DROP-IN replacement for the ranker's decision
# step: it reads the SAME retrieved candidate list (rendered by
# build_bootstrap.render_instruction) and answers 'SELECT <n>' or 'ABSTAIN'. The
# harness then maps <n> back to the retrieved candidate's ID — so even a
# fine-tuned LLM is decoding-constrained to grounded IDs. See README + Ludwig
# config. This deterministic ranker is the CPU baseline / oracle-of-record.
# =============================================================================

import csv
import difflib
import os
import re


# ------------------------------------------------------------------ text utils
def normalize(s):
    if s is None:
        return ""
    s = str(s).lower().strip()
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def tokens(s):
    return set(t for t in normalize(s).split(" ") if t)


def jaccard(a, b):
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def fuzzy(a, b):
    return difflib.SequenceMatcher(None, normalize(a), normalize(b)).ratio()


def split_synonyms(raw):
    if not raw:
        return []
    parts = re.split(r"[|;]", str(raw))
    if len(parts) == 1:
        parts = str(raw).split(",")
    return [p.strip() for p in parts if p.strip()]


# -------------------------------------------------------------------- Retriever
class Retriever:
    """Deterministic candidate retriever over the ontology seed dictionary.

    Given a free-text value, returns a ranked list of grounded candidates:
        [{"term_id","label","score","via"}...]  (highest score first)
    Only candidates scoring above `floor` are returned; a genuinely
    out-of-dictionary value returns [] (nothing plausible to select).
    """

    def __init__(self, ontology_csv, top_k=5, floor=0.34):
        self.top_k = top_k
        self.floor = floor
        self.entries = []
        with open(ontology_csv, newline="") as fh:
            for r in csv.DictReader(fh):
                tid = (r.get("term_id") or "").strip()
                lab = (r.get("term_label") or "").strip()
                if not tid or not lab:
                    continue
                syns = split_synonyms(r.get("synonyms"))
                self.entries.append({
                    "term_id": tid,
                    "label": lab,
                    "synonyms": syns,
                    "norm_label": normalize(lab),
                    "norm_syns": [normalize(s) for s in syns],
                    "label_tok": tokens(lab),
                    "syn_tok": [tokens(s) for s in syns],
                })
        # exact indices (normalized label / synonym -> entry)
        self._exact = {}
        self._syn = {}
        for e in self.entries:
            self._exact.setdefault(e["norm_label"], e)
            for ns in e["norm_syns"]:
                self._syn.setdefault(ns, e)

    def _score(self, value, e):
        """Best grounded similarity of value vs this entry (label + synonyms)."""
        nv = normalize(value)
        vt = tokens(value)
        # exact label / synonym -> saturate
        if nv == e["norm_label"]:
            return 1.0, "exact_label"
        if nv in e["norm_syns"]:
            return 0.98, "exact_synonym"
        # token-set Jaccard (best over label + synonyms)
        j = jaccard(vt, e["label_tok"])
        for st in e["syn_tok"]:
            j = max(j, jaccard(vt, st))
        # character fuzzy (best over label + synonyms)
        fz = fuzzy(nv, e["norm_label"])
        for ns in e["norm_syns"]:
            fz = max(fz, fuzzy(nv, ns))
        # blended grounded score; token overlap weighted higher (more reliable
        # for reordered / abbreviated clinical phrases than raw edit distance)
        score = max(j, 0.6 * j + 0.4 * fz)
        via = "token_set" if j >= fz else "fuzzy"
        return round(score, 4), via

    def retrieve(self, value):
        # fast path: exact hits are always candidate #1
        nv = normalize(value)
        scored = []
        for e in self.entries:
            s, via = self._score(value, e)
            if s >= self.floor:
                scored.append({"term_id": e["term_id"], "label": e["label"],
                               "score": s, "via": via})
        scored.sort(key=lambda c: c["score"], reverse=True)
        # keep exact/synonym hits regardless; cap the rest at top_k
        return scored[: self.top_k]


# --------------------------------------------------------------------- Proposer
class Proposer:
    """RANKER that SELECTs a grounded candidate or ABSTAINs.

    Decision rule (deterministic CPU baseline):
      - No candidates retrieved                      -> ABSTAIN (OOD).
      - Top candidate below accept_threshold         -> ABSTAIN (too weak).
      - Top vs runner-up within tie_margin AND both
        strong but different concepts                -> ABSTAIN (ambiguous;
                                                        a human must disambiguate).
      - Otherwise                                    -> SELECT the top candidate.

    A SELECT decision returns ONLY a term_id drawn from the retrieved set, so
    the emitted ID is always grounded. This is the object an LLM LoRA replaces:
    same inputs (value + retrieved candidates), same constrained output space.
    """

    def __init__(self, retriever, accept_threshold=0.62, tie_margin=0.05):
        self.retriever = retriever
        self.accept_threshold = accept_threshold
        self.tie_margin = tie_margin

    def propose(self, value):
        cands = self.retriever.retrieve(value)
        if not cands:
            return self._abstain(value, cands, "no grounded candidate retrieved "
                                                "(out of dictionary)")
        top = cands[0]
        if top["score"] < self.accept_threshold:
            return self._abstain(value, cands,
                                 "top candidate %.2f < accept %.2f"
                                 % (top["score"], self.accept_threshold))
        # ambiguity: near-tie between two DIFFERENT ontology terms
        if len(cands) > 1:
            runner = cands[1]
            if (top["score"] - runner["score"]) < self.tie_margin \
                    and runner["term_id"] != top["term_id"]:
                return self._abstain(value, cands,
                                     "ambiguous near-tie %s vs %s (%.2f/%.2f)"
                                     % (top["term_id"], runner["term_id"],
                                        top["score"], runner["score"]))
        return {
            "input": value,
            "decision": "SELECT",
            "term_id": top["term_id"],       # ALWAYS from the retrieved set
            "label": top["label"],
            "confidence": top["score"],
            "via": top["via"],
            "candidates": cands,
            "reason": "grounded match via %s (score %.2f)"
                      % (top["via"], top["score"]),
        }

    def _abstain(self, value, cands, reason):
        return {
            "input": value,
            "decision": "ABSTAIN",
            "term_id": None,                 # NEVER an ID on abstain
            "label": None,
            "confidence": cands[0]["score"] if cands else 0.0,
            "via": None,
            "candidates": cands,
            "reason": reason,
        }


# --------------------------------------------------------------------- LLM stub
def llm_select_from_candidates(instruction_text, candidates, generate_fn):
    """DROP-IN point for a real per-client LoRA LLM (see Ludwig config).

    `generate_fn(instruction_text) -> str` is any text generator (a vLLM call to
    the client's adapter, or a local transformers pipeline). Its output is
    PARSED, not trusted: we accept only 'SELECT <n>' pointing at a retrieved
    candidate, or 'ABSTAIN'. Anything else -> ABSTAIN. Thus even a hallucinating
    LLM cannot emit an ungrounded ID — the parser maps <n> back to the
    retrieved candidate's real term_id.
    """
    raw = (generate_fn(instruction_text) or "").strip()
    m = re.search(r"select\s+(\d+)", raw, re.IGNORECASE)
    if m:
        n = int(m.group(1))
        if 1 <= n <= len(candidates):
            c = candidates[n - 1]
            return {"decision": "SELECT", "term_id": c["term_id"],
                    "label": c["label"], "raw": raw}
    # unparsable, out-of-range index, or explicit ABSTAIN -> ABSTAIN
    return {"decision": "ABSTAIN", "term_id": None, "label": None, "raw": raw}


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    ont = os.path.join(here, "ontology_seed.csv")
    r = Retriever(ont)
    p = Proposer(r)
    for v in ["RA", "rheumatoid arth.", "CD4+ T cell",
              "peripheral blood mononuclear cells",
              "sample stored at -80C for 14 months"]:
        d = p.propose(v)
        print("%-45s -> %-8s %s" % (v[:45], d["decision"], d["term_id"] or "—"))
