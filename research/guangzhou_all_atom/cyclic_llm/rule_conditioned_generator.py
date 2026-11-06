"""SNG L2/L5: a rule-CONDITIONED generator. Takes the induced rule (H) + Target-KB mechanism constraints and
generates candidates that satisfy them BY CONSTRUCTION, then REJECTS any residual violator (correctness-by-
construction). Emits (H, X). This rule-constrained enumeration is a STAND-IN for the neural peptide generator;
the point here is the constrain+reject mechanism and the free-position exploration (incl. ncAA), not genus enum."""
import json, os, itertools
from rule_induction import predicates
from acceptance_gate import avb6_gate
from fto_score import fto_score

HERE = os.path.dirname(__file__)
AROM = ["F", "Y", "W", "[2Nal]", "[Phe4F]", "[Phe4Cl]"]   # aromatic flanks incl. ncAA (free-position diversity)
SMALL = ["A", "G", "S", "[Aib]", "[Abu]"]                  # p6 specificity knob incl. ncAA

def gen_avb6(n=12):
    """Conditioned on induced rule (RGD.L + aromatic flanks) + KB mechanism (D-Pro turn + single NMe-Lys handle).
    Free positions explored: p1, p7 (aromatic incl ncAA), p6 (small incl ncAA)."""
    H = json.load(open(os.path.join(HERE, "target_kb", "avb6_induced_rule.json")))["induced_rule"]
    kb = json.load(open(os.path.join(HERE, "target_kb", "avb6.json")))
    out = []
    combos = itertools.product(AROM, SMALL, AROM)   # p1, p6, p7
    for p1, p6, p7 in combos:
        helm = f"cyclo({p1}-R-G-D-L-{p6}-{p7}-[dP]-[NMeK])"   # scaffold = KB mechanism (turn + handle) fixed
        # CONSTRAIN by construction; then REJECT residual violators (verify predicates + hard gate)
        pr = predicates(helm)
        if not (pr["has_rgd"] and pr["has_rgdl"] and pr["flank_aromatic_p1"] and pr["flank_aromatic_p7"]):
            continue
        g = avb6_gate(helm)
        if not g["PASS_H1_H5"]:
            continue
        # FTO by construction: reject patent-INFRINGING (inside the claim); keep + rank the rest by DoE
        fto = fto_score(helm, "avb6")
        if fto["claim"]["verdict"].startswith("INSIDE"):
            continue   # rejected: literally inside the CA2998968 genus
        ncaa = [x for x in (p1, p6, p7) if x.startswith("[")]
        out.append({"helm": helm, "free": {"p1": p1, "p6": p6, "p7": p7}, "ncaa_count": len(ncaa),
                    "fto_verdict": fto["claim"]["verdict"], "doe": fto["claim"]["doe"],
                    "nearest_patented_id": fto["nearest_patented_identity"]})
        if len(out) >= n:
            break
    # rank survivors by FTO strength (LOW < MED < HIGH DoE) then lower patent-identity
    rank = {"LOW": 0, "MED": 1, "HIGH": 2}
    out.sort(key=lambda c: (rank.get(c["doe"], 1), c["nearest_patented_id"]))
    return H, out

if __name__ == "__main__":
    H, X = gen_avb6(12)
    print("H (induced rule, the design spec):  binder(X) :- " + ", ".join(H) + ".")
    print(f"X ({len(X)} candidates satisfying H + mechanism; rule-violators AND patent-INFRINGING rejected by construction):")
    for c in X:
        print(f"  {c['helm']}   ncAA={c['ncaa_count']}  FTO: {c['fto_verdict']} (DoE {c['doe']}, patent-id {c['nearest_patented_id']})")
    json.dump({"H": H, "X": X}, open(os.path.join(HERE, "target_kb", "avb6_generated_HX.json"), "w"), indent=2)
    print("wrote avb6_generated_HX.json  (the (H,X) artifact)")
