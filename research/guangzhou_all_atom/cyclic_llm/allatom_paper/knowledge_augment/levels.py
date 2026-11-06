"""Knowledge-augmentation configuration levels for the ablation. Each level is a PURE FUNCTION of committed files + its explicit configuration; the config hash
covers the content hashes of every input file, the selected rule ids, the weights and the exclusion tokens, so the same hash means the same behaviour.

  L0  none                : hard rules only (SoftSource.none, no ring potential).
  L1  literature priors   : only entries that are weight_eligible AND quote_verified AND agreed in BOTH group-A sources in the direction check
                            (direction_check_results.json: rule_status == 'agree' with n_agree_cells == n_cells); monotone directions only ('+', '-', 'multi';
                            the one 'window' rule, LIT-BRO5-001, is not a monotone token weight and enters the PROMPT only); uniform weights (magnitude 1 times the KB
                            proxy_scale for proxy-mapped features, signs from the KB, channel value = mean over the contributing rules); size (mw) and D-residue terms are
                            never weighted (verified unreliable in the direction check).
  L2  L1 + structure      : L1 + ring-size potential from bound-conformation priors (default weight 0.5, untuned); interface-residue enrichment weight 0
                            (unstable under leave-one-target-out); the turn prior is exported to the prompt only (no token proxy).
  L3  data-descriptive    : group-A descriptive directions (Spearman / N-Me dz of Townsend and Kelly; labelled UNVALIDATED), ablation only; not combined with L2.

lam_soft is the global scale of the log-linear potential on the token proxies; its default (0.5) is fixed here before any measurement and is not tuned.
No input of any level derives from groups S or B (leak_report checks mined_from and the direction-check sources against source_groups_v2.json).
"""
import hashlib
import json
import os
import sys
from dataclasses import dataclass, field

HERE = os.path.dirname(os.path.abspath(__file__))
AP = os.path.normpath(os.path.join(HERE, ".."))
if AP not in sys.path:
    sys.path.insert(0, AP)
from rules.soft import SoftSource, assert_sources_disjoint, forbidden_from_groups  # noqa: E402
from knowledge_augment.ring_potential import RingPotential, ring_tables  # noqa: E402

P = dict(
    kb=os.path.join(AP, "knowledge", "knowledge_kb_v1.json"),
    direction=os.path.join(AP, "knowledge", "direction_check_results.json"),
    groups=os.path.join(AP, "track_e", "source_groups_v2.json"),
    groupA_sens=os.path.join(AP, "rules_mining", "groupA_sensitivity.json"),
    ring_lib=os.path.join(AP, "structure_knowledge", "results", "library_v1.jsonl"),
    soft_pot=os.path.join(AP, "structure_knowledge", "results", "soft_potentials_v1.json"),
)
LEVELS = ("L0", "L1", "L2", "L3")
DEFAULT_LAM = 0.5
DEFAULT_RING_WEIGHT = 0.5
# Code-level exclusions (coordinator finding 2026-10-31): the stored KB `weight` field is NEVER read for potentials, and size, rotatable-bond and D-residue terms
# can never receive a nonzero potential at any level, whatever the KB stores (LIT-SIZE-001, LIT-STAB-008 etc. keep weight 0.05 in the KB file).
EXCLUDED_FEATURES = frozenset({"mw", "n_heavy_atoms", "nrotb", "n_dres"})
EXCLUDED_IDS_EXPLICIT = frozenset({"LIT-SIZE-001", "LIT-SIZE-002", "LIT-STAB-008", "LIT-STAB-002", "LIT-NCAA-001", "LIT-HBD-001", "LIT-BRO5-003"})
TOKEN_FEATS = {"tpsa": "polar", "hbd": "polar", "hba": "polar", "clogp": "carbon", "alogp": "carbon", "n_nme": "nme"}


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def l1_selection(kb_path=None, direction_path=None):
    """ids of the entries used as L1 weights, with the reason every other weight-eligible entry is left out."""
    kb = json.load(open(kb_path or P["kb"]))["rules"]
    dc = json.load(open(direction_path or P["direction"]))["rules"]
    used, left_out = [], {}
    for e in kb:
        if not e.get("weight_eligible"):
            continue
        d = dc.get(e["id"], {})
        if e["id"] in EXCLUDED_IDS_EXPLICIT:
            left_out[e["id"]] = "explicit exclusion (size / rotatable bonds / D-residue / mixed direction check)"
        elif not e.get("quote_verified"):
            left_out[e["id"]] = "quote not verified"
        elif d.get("rule_status") != "agree" or d.get("n_agree_cells") != d.get("n_cells") or not d.get("n_cells"):
            left_out[e["id"]] = "direction check: %s" % d.get("rule_status", "absent")
        elif e.get("direction") not in ("+", "-", "multi"):
            left_out[e["id"]] = "non-monotone direction (%s): prompt only" % e.get("direction")
        elif not any(f in TOKEN_FEATS for f in e.get("feat_mapped", {})):
            left_out[e["id"]] = "no token proxy"
        else:
            used.append(e["id"])
    return sorted(used), left_out


def literature_agreed_source(kb_path=None, direction_path=None, ids=None):
    kb = {e["id"]: e for e in json.load(open(kb_path or P["kb"]))["rules"]}
    ids = l1_selection(kb_path, direction_path)[0] if ids is None else ids
    acc, n = {"polar": 0.0, "carbon": 0.0, "nme": 0.0}, {"polar": 0, "carbon": 0, "nme": 0}
    for i in ids:
        e = kb[i]
        for f, sgn in e["feat_mapped"].items():
            ch = TOKEN_FEATS.get(f)
            if f in EXCLUDED_FEATURES or ch is None or not sgn:   # size / rotb / D-residue / is_cyclic terms: never weighted
                continue
            sc = e.get("proxy_scale", 1.0) if f in e.get("feat_proxy", []) else 1.0
            acc[ch] += sgn * sc
            n[ch] += 1
    w = {k: (acc[k] / n[k] if n[k] else 0.0) for k in acc}
    return SoftSource("literature_agreed_uniform", "literature priors: weight-eligible, agreed in both group-A sources, uniform weights (%d entries)" % len(ids), w)


def entry_potentials(level, kb_path=None):
    """effective potential per KB entry at a level: {id: {channel: contribution to the channel mean, 'used': bool}} for every KB entry (zero for unused/excluded).
    Contribution = sign * scale / n_contributors(channel), i.e. what literature_agreed_source adds to each channel."""
    kb = {e["id"]: e for e in json.load(open(kb_path or P["kb"]))["rules"]}
    ids = set(build_level(level).rule_ids) if level in ("L1", "L2") else set()
    n = {"polar": 0, "carbon": 0, "nme": 0}
    for i in ids:
        for f, sgn in kb[i]["feat_mapped"].items():
            if f not in EXCLUDED_FEATURES and f in TOKEN_FEATS and sgn:
                n[TOKEN_FEATS[f]] += 1
    out = {}
    for i, e in kb.items():
        c = {"polar": 0.0, "carbon": 0.0, "nme": 0.0}
        if i in ids:
            for f, sgn in e["feat_mapped"].items():
                ch = TOKEN_FEATS.get(f)
                if f in EXCLUDED_FEATURES or ch is None or not sgn:
                    continue
                sc = e.get("proxy_scale", 1.0) if f in e.get("feat_proxy", []) else 1.0
                c[ch] += sgn * sc / n[ch]
        out[i] = dict(c, used=i in ids, stored_weight=e.get("weight"))
    return out


@dataclass(frozen=True)
class Level:
    name: str
    soft: SoftSource
    ring: object                      # RingPotential | None
    lam_soft: float
    rule_ids: tuple                   # entries used as weights
    prompt_rule_ids: tuple            # entries available to the prompt pack (superset of rule_ids)
    exclude_tokens: tuple
    config: dict = field(compare=False, hash=False, default_factory=dict)
    config_hash: str = ""
    labels: tuple = ()

    def constraint(self, vocab, **kw):
        from knowledge_augment.ring_potential import AugmentedConstraint
        return AugmentedConstraint(vocab, lam_soft=self.lam_soft, soft=self.soft, forbidden_sources=forbidden_from_groups(P["groups"]), ring=self.ring, **kw)


def build_level(name, exclude_tokens=(), lam_soft=DEFAULT_LAM, ring_weight=DEFAULT_RING_WEIGHT):
    assert name in LEVELS, name
    exclude_tokens = tuple(sorted(map(str, exclude_tokens)))
    ids, left_out, labels = (), {}, ()
    soft, ring = SoftSource.none(), None
    if name in ("L1", "L2"):
        ids_l, left_out = l1_selection()
        ids = tuple(ids_l)
        soft = literature_agreed_source()
    if name == "L2":
        rt = ring_tables(exclude_tokens)
        ring = RingPotential.build(rt, ring_weight)
    if name == "L3":
        soft = SoftSource.groupA_descriptive(P["groupA_sens"])
        labels = ("data-descriptive, UNVALIDATED (group A only), ablation only",)
    lam = 0.0 if name == "L0" else float(lam_soft)
    forb = forbidden_from_groups(P["groups"])
    assert_sources_disjoint(soft, forb)
    assert not (set(ids) & EXCLUDED_IDS_EXPLICIT), "excluded entry selected"
    prompt_ids = tuple(sorted(e["id"] for e in json.load(open(P["kb"]))["rules"] if e.get("quote_verified")))
    cfg = dict(
        level=name, lam_soft=lam, ring_weight=(ring_weight if ring else 0.0), soft_name=soft.name, soft_weights=soft.weights, rule_ids=list(ids),
        exclude_tokens=list(exclude_tokens), ring_targets_sha256=(ring.targets_sha256 if ring else None), ring_n=(ring.n if ring else None),
        inputs=dict(kb=sha256_file(P["kb"]), direction=sha256_file(P["direction"]), groups=sha256_file(P["groups"]),
                    groupA_sens=sha256_file(P["groupA_sens"]) if name == "L3" else None,
                    ring_lib=sha256_file(P["ring_lib"]) if name == "L2" else None),
        mined_from=list(soft.mined_from), excluded_features=sorted(EXCLUDED_FEATURES), excluded_ids=sorted(EXCLUDED_IDS_EXPLICIT))
    h = hashlib.sha256(json.dumps(cfg, sort_keys=True).encode()).hexdigest()[:16]
    return Level(name, soft, ring, lam, ids, prompt_ids, exclude_tokens, dict(cfg, left_out=left_out), h, labels)


def leak_report():
    """checks that no level's inputs derive from groups S or B."""
    g = json.load(open(P["groups"]))["membership"]
    forb = set(forbidden_from_groups(P["groups"]))
    A = sorted(s for s, v in g.items() if v["group"] == "A")
    dc = json.load(open(P["direction"]))
    out = dict(group_A=A, forbidden=sorted(forb), levels={})
    for L in LEVELS:
        lv = build_level(L)
        out["levels"][L] = dict(config_hash=lv.config_hash, mined_from=list(lv.soft.mined_from), overlap_with_S_B=sorted(set(lv.soft.mined_from) & forb))
    out["direction_check_sources"] = dc["meta"]["group_A_sources"]
    out["direction_check_overlap_with_S_B"] = sorted(set(dc["meta"]["group_A_sources"]) & forb)
    out["ok"] = (not out["direction_check_overlap_with_S_B"]) and all(not v["overlap_with_S_B"] for v in out["levels"].values())
    return out


if __name__ == "__main__":
    print(json.dumps(leak_report(), indent=1))
    for L in LEVELS:
        lv = build_level(L)
        print(L, lv.config_hash, lv.soft.weights, lv.lam_soft, len(lv.rule_ids))
