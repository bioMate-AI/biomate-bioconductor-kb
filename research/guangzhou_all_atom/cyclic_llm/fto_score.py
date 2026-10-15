"""Patent/FTO KB — claim layer. Generalizes the hand CA2998968 read into a reusable in_claim(candidate, claim)
that maps a candidate onto a structured genus claim and returns {inside | literally-outside + position + DoE}.
Plus a sequence-identity dissimilarity to known patented compounds (stand-in for a SureChEMBL/Google-Patents
compound layer, which is the data-ingestion follow-on)."""
import json, os
from acceptance_gate import raw_tokens, _strip_mods, _canon1

HERE = os.path.dirname(__file__)
# residue -> allowed-class tokens, so ncAA map onto the claim's canonical enumerations
NCAA_HOMOLOG = {"2Nal": "F", "1Nal": "F", "Phe4F": "F", "Phe4Cl": "F", "hPhe": "F", "Bip": "F", "Nle": "Nle"}

def _res_class(core):
    c = _strip_mods(core)
    return c  # canonical letter or ncAA token core

def in_claim(helm, claim):
    """Map a head-to-tail cyclic nonapeptide (P1-R-G-D-L-P6-P7-[dP]-[NMeK] family) onto the genus claim."""
    toks = raw_tokens(helm)
    cyclic = helm.strip().lower().startswith("cyclo(")
    seq1 = "".join(_canon1(t) for t in toks); w = seq1 + seq1[:6]
    # claim applies only to its FORM: head-to-tail cyclic nonapeptide containing RGDL
    if not cyclic:
        return {"verdict": "OUTSIDE (form)", "basis": "not head-to-tail cyclic (e.g. side-chain lactam / bicycle)", "doe": "LOW"}
    if len(toks) != 9:
        return {"verdict": "OUTSIDE (form)", "basis": f"ring size {len(toks)} != claimed 9-mer", "doe": "MED"}
    if "RGDL" not in w:
        return {"verdict": "OUTSIDE (form)", "basis": "no RGDL motif", "doe": "LOW"}
    # map positions (read from Arg): X1=G, X2=L, X3=P6, X4=P7, X5=dP, X6=NMeK, X7=P1
    i = w.find("RGDL")
    p1 = toks[i - 1] if i > 0 else toks[-1]
    dpi = next((j for j, t in enumerate(toks) if _strip_mods(t) == "P" and t.startswith("d")), None)
    p7 = toks[dpi - 1] if dpi else None
    p6 = toks[(i + 4) % len(toks)]
    pos = claim["claim_form"]["positions"]
    out = []
    checks = {"X7(P1)": (p1, pos["X7"]), "X3(P6)": (p6, pos["X3"]), "X4(P7)": (p7, pos["X4"])}
    for name, (res, allowed) in checks.items():
        if res is None:
            continue
        c = _res_class(res)
        if c in allowed:
            continue                                   # literally within the enumeration
        elif NCAA_HOMOLOG.get(c) in allowed:
            out.append({"position": name, "residue": res, "doe": "MED"})   # ncAA homolog of a listed residue -> literally OUT, MED DoE
        else:
            out.append({"position": name, "residue": res, "doe": "HIGH"})  # conservative canonical sub outside list -> literally OUT, HIGH DoE
    if not out:
        return {"verdict": "INSIDE (literal genus)", "basis": "all X positions within enumerations", "doe": "infringes"}
    return {"verdict": "literally OUTSIDE at " + ", ".join(o["position"] for o in out),
            "outside_positions": out, "doe": max(o["doe"] for o in out)}

def nearest_patented(helm, claim):
    bb = "".join(_canon1(t) for t in raw_tokens(helm))
    best = 0.0
    for kc in claim.get("known_compounds", []):
        kbb = "".join(_canon1(t) for t in raw_tokens(kc))
        if len(kbb) == len(bb):
            best = max(best, sum(a == b for a, b in zip(bb, kbb)) / len(bb))
    return round(best, 2)

def fto_score(helm, target="avb6"):
    claim = json.load(open(os.path.join(HERE, "fto_kb", "ca2998968.json")))
    return {"claim": in_claim(helm, claim), "nearest_patented_identity": nearest_patented(helm, claim)}

if __name__ == "__main__":
    tests = [
        "cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])",          # avebehexin = literal genus
        "cyclo(W-R-G-D-L-A-[2Nal]-[dP]-[NMeK])",     # ncAA flank -> MED DoE
        "cyclo(Y-R-G-D-L-S-F-[dP]-[NMeK])",          # Ser@X3 -> HIGH DoE
        "cyclo(R-G-D-L-F-[dP]-[NMeK])",              # 7-mer ring-size -> OUTSIDE(form) MED
        "Ac-[Dap]-R-G-D-L-A-F-[dP]-[Glu]-K-NH2",     # side-chain lactam -> OUTSIDE(form) LOW
    ]
    for h in tests:
        r = fto_score(h)
        print(f"{h}\n   -> {r['claim']['verdict']} | DoE {r['claim']['doe']} | nearest-patented id {r['nearest_patented_identity']}")
