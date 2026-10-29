"""Knowledge-conditioned prompt pack: target card + bound-conformation snippets, top-k rule statements, prior-work lessons, retrieved neighbours.

The neighbour section and the pharmacophore line are produced by the I-B prompt builder (retrieval/prompt.py::build_prompt, imported not modified); this module
builds the knowledge block that goes into its `header`, under a separate token budget, so the same builder serves generation and training examples.
Every line carries its id and evidence tier; T1 (peer-reviewed, quote verified), T2 (preprint / patent-class) and internal entries are visibly distinct ([T1] / [T2] / [int]).
Level content:  L0 nothing;  L1 rule statements + lessons;  L2 L1 + structure snippets (ring-size recomputed from the library, minus excluded targets);  L3 the
group-A descriptive line, labelled UNVALIDATED.  Arm-G exclusion: `exclude_tokens` (accessions or target keys) removes those targets from every structure-derived line, and
a target card whose receptor accession is excluded states that its structure is withheld; the ring statistics are recomputed without the excluded complexes.
ChemFM-1B has an atom-level SMILES vocabulary and cannot read this text: for that model the pack is carried by control-code tokens in the unused ids 266-319
(`control_codes`), whose embeddings are learned by the fine-tune. The text is the interface for text-capable backbones and for inspection.
"""
import json
import math
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
AP = os.path.normpath(os.path.join(HERE, ".."))
if AP not in sys.path:
    sys.path.insert(0, AP)
from knowledge_augment.levels import P, build_level, LEVELS  # noqa: E402
from knowledge_augment.ring_potential import ring_tables, CLASSES  # noqa: E402
from retrieval.prompt import build_prompt, PromptTooLong, _default_count  # noqa: E402,F401

CARDS = os.path.join(AP, "structure_knowledge", "results", "cards_v1.json")
TIER_TAG = {"T1": "[T1]", "T2": "[T2]", "T-internal": "[int]"}
TIER_ORDER = {"T1": 0, "T2": 1, "T-internal": 2}
LINE_CHARS = 170
KB_BUDGET_DEFAULT = 380


def _one_line(s, n=LINE_CHARS):
    s = " ".join(str(s).split())
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


def _kb():
    return json.load(open(P["kb"]))["rules"]


def rule_lines(level, k=8):
    """top-k rule statements: the entries that are WEIGHTS at the level first (they are the ones the sampler also uses), then other verified rules/fundamentals;
    T1 before T2 before internal; id as tie-break."""
    if level.name == "L0":
        return []
    used = set(level.rule_ids)
    pool = [e for e in _kb() if e["kind"] in ("rule", "fundamental") and e.get("quote_verified") and e.get("tier") in TIER_TAG]
    pool.sort(key=lambda e: (e["id"] not in used, TIER_ORDER[e["tier"]], e["id"]))
    return [dict(id=e["id"], tier=e["tier"], text="%s %s: %s" % (TIER_TAG[e["tier"]], e["id"], _one_line(e["statement"])), weight_in_sampler=e["id"] in used) for e in pool[:k]]


def lesson_lines(level, k=4, target=None):
    """prior-work lessons: cautions and method cards, cards applicable to `target` first."""
    if level.name == "L0":
        return []
    pool = [e for e in _kb() if e["kind"] in ("caution", "card") and e.get("quote_verified") and e.get("tier") in TIER_TAG]

    def applies(e):
        a = e.get("applicable_target") or []
        return not (target and target in a)
    pool.sort(key=lambda e: (applies(e), TIER_ORDER[e["tier"]], e["id"]))
    return [dict(id=e["id"], tier=e["tier"], text="%s %s: %s" % (TIER_TAG[e["tier"]], e["id"], _one_line(e["statement"]))) for e in pool[:k]]


def _quart(v):
    v = sorted(v)
    q = lambda p: v[min(len(v) - 1, int(p * (len(v) - 1) + 0.5))]  # noqa: E731
    return q(0.25), q(0.5), q(0.75)


def structure_lines(level, exclude_tokens=()):
    """ring-size snippets recomputed from the committed library without the excluded targets (L2 only)."""
    if level.name != "L2":
        return []
    from knowledge_augment.ring_potential import _read_lib, LIB_DEFAULT
    toks = set(map(str, exclude_tokens))
    rows = [r for r in _read_lib(LIB_DEFAULT) if not r["receptor_antibody_like"]]
    rows = [r for r in rows if not (r["target_key"] in toks or set(r["target_key"].split("+")) & toks)]
    th = ring_tables(exclude_tokens)["targets_sha256"]
    out = []
    for cls in CLASSES:
        rr = [int(r["ring_residues"]) for r in rows if r["primary_cyclisation"] == cls]
        if len(rr) < 20:
            continue
        a, m, b = _quart(rr)
        out.append(dict(id="STR-RING-%s" % cls, tier="T1", text="[str] STR-RING-%s: target-bound cyclic peptides closed by %s span %d-%d residues (IQR), median %d (n=%d complexes; targets set %s)"
                        % (cls, cls.replace("_", " "), a, b, m, len(rr), th)))
    return out


def target_card(target, exclude_tokens=()):
    """one-line card for a target from cards_v1.json; withheld when its receptor accession is excluded (arm G)."""
    if not target:
        return None
    cards = json.load(open(CARDS))
    c = next((x for x in cards if x["target"] == target), None)
    if c is None:
        return dict(id="CARD-%s" % target, text="target %s: no structure card" % target, withheld=False)
    toks = set(map(str, exclude_tokens))
    if set(c.get("receptor_uniprot", [])) & toks or target in toks:
        return dict(id="CARD-%s" % target, text="target %s (%s): structure information withheld" % (target, c["label"]), withheld=True)
    return dict(id="CARD-%s" % target, text="target %s (%s): reference %s; %s" % (target, c["label"], c.get("reference_pdb"), _one_line(c["structure_status"], 110)), withheld=False)


def group_a_line(level):
    if level.name != "L3":
        return []
    w = level.soft.weights
    return [dict(id="DESC-A", tier="T-data", text="[data, UNVALIDATED] group-A descriptive directions: polar %+0.2f, carbon %+0.2f, N-methyl %+0.2f" % (w["polar"], w["carbon"], w["nme"]))]


def knowledge_block(level, target=None, k_rules=8, k_lessons=4, exclude_tokens=(), max_tokens=KB_BUDGET_DEFAULT, count_tokens=_default_count):
    """returns (text, meta). Lowest-priority lines are dropped first when over budget; the header alone must fit."""
    if level.name == "L0":
        return "", dict(level="L0", lines=[], dropped=0, n_tokens_est=0)
    card = target_card(target, exclude_tokens)
    groups = [("card", [card] if card else []), ("rule", rule_lines(level, k_rules)), ("structure", structure_lines(level, exclude_tokens)),
              ("lesson", lesson_lines(level, k_lessons, target)), ("data", group_a_line(level))]
    head = "Knowledge (level %s, config %s):" % (level.name, level.config_hash)
    if count_tokens(head) > max_tokens:
        raise PromptTooLong("knowledge header exceeds budget")
    flat = [(g, x) for g, xs in groups for x in xs]
    keep = len(flat)
    render = lambda n: "\n".join([head] + [x["text"] for _, x in flat[:n]])  # noqa: E731
    while keep > 0 and count_tokens(render(keep)) > max_tokens:
        keep -= 1
    text = render(keep)
    meta = dict(level=level.name, config_hash=level.config_hash, lines=[dict(group=g, id=x["id"], tier=x.get("tier")) for g, x in flat[:keep]], dropped=len(flat) - keep,
                n_tokens_est=count_tokens(text), exclude_tokens=list(exclude_tokens))
    return text, meta


def build_pack(level, hits=(), target=None, exclude_tokens=(), kb_tokens=KB_BUDGET_DEFAULT, total_tokens=1024, value_keys=("z",), count_tokens=_default_count,
               footer="New cyclic peptide (SMILES):"):
    """knowledge block + retrieved neighbours + pharmacophore line, one prompt. Returns (PromptResult, knowledge_meta)."""
    kb_text, kmeta = knowledge_block(level, target, exclude_tokens=exclude_tokens, max_tokens=kb_tokens, count_tokens=count_tokens)
    header = (kb_text + "\n" if kb_text else "") + "Known cyclic peptides with measured values:"
    res = build_prompt(list(hits), target=target, value_keys=value_keys, max_tokens=total_tokens, count_tokens=count_tokens, header=header, footer=footer)
    return res, kmeta


# ------------------------------------------------------------------------------------------------ control codes for ChemFM-1B (ids 266-319)
CODE_BASE = 266
LEVEL_CODE = {L: CODE_BASE + i for i, L in enumerate(LEVELS)}                 # 266-269
CLASS_CODE = {c: CODE_BASE + 4 + i for i, c in enumerate(CLASSES)}            # 270-273
RING_BINS = ((4, 6), (7, 8), (9, 10), (11, 12), (13, 15), (16, 30))
RING_CODE = {b: CODE_BASE + 8 + i for i, b in enumerate(RING_BINS)}           # 274-279
CODE_MAX = CODE_BASE + 8 + len(RING_BINS) - 1                                  # 279 < 320


def ring_bin(residues):
    return next(b for b in RING_BINS if b[0] <= residues <= b[1])


def control_codes(level_name, closure_class=None, ring_residues=None):
    """token ids prepended to the sequence: level, optional closure-class preference, optional ring-size bin. All ids lie in the unused range 266-319."""
    ids = [LEVEL_CODE[level_name]]
    if closure_class in CLASS_CODE:
        ids.append(CLASS_CODE[closure_class])
    if ring_residues is not None:
        ids.append(RING_CODE[ring_bin(int(ring_residues))])
    assert all(CODE_BASE <= i <= CODE_MAX < 320 for i in ids)
    return ids
