"""Pluggable SOFT-rule sources for the rule automaton (coordinator decision, 2026-10-29): hard rules are the primary configuration; soft potentials are an input.
  none                 : hard rules only (default, primary).
  literature(kb_path)  : signed weights summed from the literature knowledge base (workstream K, allatom_paper/knowledge/knowledge_kb_v1.json; only weight_eligible AND quote_verified
                         rules), mapped to token proxies; or literature_uniform(): unit magnitudes with the textbook signs (TPSA/HBD -, logP +, N-methyl +).
  groupA_descriptive(path) : per-source Spearman/mean-dz of the two group-A sources (2020_Townsend, 2021_Kelly) from rules_mining/groupA_sensitivity.json; labelled
                         'data-descriptive, unvalidated' (no soft rule reached validated status on group A); ablation only.
No weight is ever tuned on the stop or held-out groups: `assert_sources_disjoint` refuses a source whose mined_from intersects forbidden sources (track_e/source_groups_v2.json groups S and B).
Token proxies (documented approximations): polar heteroatom tokens N/O ~ (TPSA, HBD, HBA) direction; carbon tokens ~ logP direction; an N-methyl nudge on '(' after an amide N and on 'C'
inside that new branch."""
import json
from dataclasses import dataclass, field


@dataclass(frozen=True)
class SoftSource:
    name: str
    status: str
    weights: dict = field(default_factory=lambda: {"polar": 0.0, "carbon": 0.0, "nme": 0.0})
    mined_from: tuple = ()

    @staticmethod
    def none(): return SoftSource("none", "none (hard rules only)")

    @staticmethod
    def literature_uniform():
        return SoftSource("literature_uniform", "literature-derived directions, uniform magnitude (textbook signs)", {"polar": -1.0, "carbon": 1.0, "nme": 1.0})

    @staticmethod
    def from_knowledge(kb_path):
        doc = json.load(open(kb_path)); acc = {"polar": 0.0, "carbon": 0.0, "nme": 0.0}; used = []
        for e in doc["rules"]:
            if not (e.get("weight_eligible") and e.get("quote_verified")) or e.get("direction") not in ("+", "-", "multi"): continue
            for f, sgn in e.get("feat_mapped", {}).items():
                sc = e.get("proxy_scale", 1.0) if f in e.get("feat_proxy", []) else 1.0; w = float(e["weight"]) * sc * sgn
                if f in ("tpsa", "hbd", "hba"): acc["polar"] += w
                elif f in ("clogp", "alogp"): acc["carbon"] += w
                elif f == "n_nme": acc["nme"] += w
                else: continue
                used.append(e["id"])
        return SoftSource("literature_kb", f"literature knowledge base v1 ({len(set(used))} rules)", acc)

    @staticmethod
    def groupA_descriptive(path):
        d = json.load(open(path)); per = d["per_source_descriptive"]; srcs = tuple(per)
        def mean(f): return sum(per[s][f]["spearman_with_y"] for s in srcs) / len(srcs)
        nme = sum(per[s]["N-Me added (with minus without)"]["mean_dz"] for s in srcs) / len(srcs)
        w = {"polar": (mean("tpsa") + mean("hbd")), "carbon": mean("logp"), "nme": nme}
        return SoftSource("groupA_descriptive", "data-descriptive, unvalidated (2 sources)", w, srcs)


def assert_sources_disjoint(soft, forbidden):
    bad = set(map(str, soft.mined_from)) & set(map(str, forbidden))
    assert not bad, f"soft weights were derived from stop/held-out sources: {sorted(bad)}"
    return True


def forbidden_from_groups(groups_json_path):
    """sources of groups S and B (stop and held-out) in track_e/source_groups_v2.json."""
    g = json.load(open(groups_json_path))["membership"]
    return tuple(s for s, v in g.items() if v["group"] in ("S", "B"))
