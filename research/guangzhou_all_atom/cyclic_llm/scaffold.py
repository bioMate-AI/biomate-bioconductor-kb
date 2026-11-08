"""Generic motif-scaffold proposer — one fill routine for ANY linear-motif integrin, scaffold = DATA.

A scaffold is a template (motif residues + beta-turn + chelator handle + free slots), keyed by the canonical
motif. The SAME generic routine fills the free slots (neural-ranked via the v4 model, else enumeration), checks
the motif is present + developability, and ranks — for RGD.L (αvβ6) and LDV (α4β7 / α4β1) identically, and for
any motif you add to SCAFFOLD. Zero per-motif code; add a template row to extend.
"""
import os, sys, re, json

HERE = os.path.dirname(__file__)
PARENT = os.path.dirname(HERE)
for _p in (HERE, PARENT):
    if _p not in sys.path:
        sys.path.insert(0, _p)
from acceptance_gate import raw_tokens, _strip_mods, _is_arom
from score import developability

CKPT = os.path.join(PARENT, "runs_helm", "unified_cyclic_llm_v4.pt")

# DATA: canonical motif -> scaffold template. "{aromatic}"/"{small}" = free slots of that chemistry class.
# Core = the integrin recognition motif; "dP" = D-Pro beta-turn; "NMeK" = N-methyl-Lys chelator handle.
SCAFFOLD = {
    "RGDL": {"tokens": ["{aromatic}", "R", "G", "D", "L", "{small}", "{aromatic}", "dP", "NMeK"], "motif": "RGDL"},
    "LDV":  {"tokens": ["{aromatic}", "L", "D", "V", "{small}", "{aromatic}", "dP", "NMeK"],       "motif": "LDV"},
}
PALETTE = {"aromatic": ["F", "Y", "W", "2Nal"], "small": ["A", "G", "S", "Aib", "Abu"]}
MODEL2SCAFFOLD = {"Nal": "2Nal"}   # v4 vocab -> scaffold symbol (scoring uses model-known tokens)


def canon_motif(s):
    """Normalize a spec motif string to a scaffold key: 'RGD.L'->'RGDL', 'LDV/IDS'->'LDV', 'LDV (CS-1)'->'LDV'."""
    if not s:
        return None
    core = re.split(r"[ /(]", s)[0].replace(".", "").upper()
    return core if core in SCAFFOLD else None


def _helm(tokens):
    return "cyclo(" + "-".join(t if len(t) == 1 else f"[{t}]" for t in tokens) + ")"


def _fills(tpl):
    """All free-slot combinations for a template (small, model-known palette)."""
    import itertools
    slots = [t[1:-1] for t in tpl["tokens"] if t.startswith("{")]        # e.g. ['aromatic','small','aromatic']
    for combo in itertools.product(*[PALETTE[c] for c in slots]):
        yield combo


def _assemble(tpl, combo):
    out, i = [], 0
    for t in tpl["tokens"]:
        if t.startswith("{"):
            out.append(MODEL2SCAFFOLD.get(combo[i], combo[i])); i += 1
        else:
            out.append(t)
    return out


def _motif_present(helm, motif):
    seq = "".join(_strip_mods(t) if len(_strip_mods(t)) == 1 else "X" for t in raw_tokens(helm))
    return motif in (seq + seq[:len(motif)])


def _neural_rank(helms):
    """Rank HELMs by the v4 model's permeability-conditioned macrocycle loglik (higher=better). None if torch/ckpt absent."""
    try:
        import numpy as np, design
        from train_cyclic_llm_v3 import TFEAT_DIM
    except Exception:
        return None
    if not os.path.exists(CKPT):
        return None
    model, toks, stoi, a, dev = design.load(CKPT)
    zero = np.zeros(TFEAT_DIM, "float32")
    scored = {}
    for h in helms:
        monos = [("K" if _strip_mods(t) == "K" else _strip_mods(t)) if t.startswith("NMe") else t for t in raw_tokens(h)]
        monos = [m if m != "dP" else "dP" for m in monos]
        try:
            scored[h] = design.loglik(model, stoi, monos, "<e_na>", "<p_hi>", zero, dev)
        except Exception:
            scored[h] = -1e9
    return scored


def scaffold_propose(spec, n=12):
    """Generic scaffold-conditioned proposal for a motif target. Returns {target, mode, motif, candidates}."""
    key = canon_motif(spec.get("motif"))
    if key is None:
        return {"target": spec["target"], "mode": "scaffold", "error": f"no scaffold template for motif {spec.get('motif')!r}", "candidates": []}
    tpl = SCAFFOLD[key]
    # enumerate fills -> HELMs -> keep motif-present + developable
    cands = []
    for combo in _fills(tpl):
        helm = _helm(_assemble(tpl, combo))
        if not _motif_present(helm, tpl["motif"]):
            continue
        dev = developability(helm)
        cands.append({"helm": helm, "developable": dev["pass"], "meanH": dev["meanH"],
                      "ncaa": sum(1 for t in raw_tokens(helm) if len(_strip_mods(t)) > 1)})
    # neural rank (permeability-conditioned); else developable-first then lower meanH
    nl = _neural_rank([c["helm"] for c in cands])
    if nl is not None:
        for c in cands:
            c["neural_loglik"] = round(float(nl.get(c["helm"], -1e9)), 2)
        cands.sort(key=lambda c: (not c["developable"], -c["neural_loglik"]))
        backend = "neural (unified_cyclic_llm_v4) scaffold-ranked"
    else:
        cands.sort(key=lambda c: (not c["developable"], c["meanH"]))
        backend = "enumeration (developability-ranked)"
    return {"target": spec["target"], "mode": "scaffold-conditioned", "motif": tpl["motif"],
            "backend": backend, "candidates": cands[:n]}


if __name__ == "__main__":
    from target_spec import load_spec
    for t in ["avb6", "a4b7", "a4b1", "lfa1"]:
        s = load_spec(t)
        key = canon_motif(s.get("motif"))
        print(f"\n=== {t}: motif={s.get('motif')!r} -> scaffold key={key} ===")
        if not key:
            print("   (no scaffold template -> de-novo path)"); continue
        r = scaffold_propose(s, n=5)
        print(f"   backend={r['backend']} motif-core={r['motif']}")
        for c in r["candidates"]:
            nl = f" ll={c.get('neural_loglik')}" if "neural_loglik" in c else ""
            print(f"     {c['helm']:40s} dev={c['developable']} meanH={c['meanH']} ncaa={c['ncaa']}{nl}")
