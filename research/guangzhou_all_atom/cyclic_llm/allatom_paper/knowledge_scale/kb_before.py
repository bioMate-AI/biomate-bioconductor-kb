"""Map the statements already in experience_kb / target_kb / medchem_kb onto the K2 coverage matrix (keyword classifier)."""
import glob, json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
CL = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, CL)
sys.path.insert(0, os.path.join(HERE, "cyclic_llm_mod"))

PROP = [("oral_bioavailability", r"oral bioavail|oral absorption"), ("permeability", r"permeab|PAMPA|Caco"),
        ("selectivity", r"selectiv"), ("binding_affinity", r"affinity|binding|potency|IC50|\bKd\b|\bpharmacophore|\bRGD"),
        ("solubility", r"solub"), ("metabolic_stability", r"metabolic|microsom|clearance"),
        ("proteolytic_stability", r"proteoly|protease|deamid|isomeris|oxidation|stability"),
        ("conformation_chameleonicity", r"chameleon|conformation|NOE"), ("renal_pk", r"renal|kidney"),
        ("toxicity_liability", r"toxic|liabilit|PAINS|hERG|alert"), ("synthesis_macrocyclization", r"macrocycl|cyclis|cycliz|synthes")]
SUB = [("n_methylation", r"N-methyl|methylat"), ("d_residue_stereo", r"\bD-|stereo|enantio|chiral"),
       ("ring_size_topology", r"ring size|macrocycle size|lariat|head-to-tail|topolog"), ("noncanonical_residue", r"non-canonical|unnatural|ncAA"),
       ("physchem_tpsa_hbd_logp_mw", r"TPSA|HBD|logP|logD|molecular weight|\bMW\b|Veber|Ro5|rule of"),
       ("ihb_conformation", r"hydrogen bond|IMHB|chameleon"), ("side_chain_motif_pharmacophore", r"RGD|motif|pharmacophore|hot-?spot|residue|aromatic"),
       ("linker_terminus_macrocyclization_chem", r"linker|stapl|lactam|thioether|disulfide|terminus|\bcap\b"),
       ("charge_polarity", r"charge|cationic|\bLys\b|\bArg\b|polar")]


def classify(statement: str):
    p = next((k for k, rx in PROP if re.search(rx, statement, re.I)), "other")
    s = next((k for k, rx in SUB if re.search(rx, statement, re.I)), "other")
    return p, s


def main(out):
    import experience_kb as E
    targets = [os.path.splitext(os.path.basename(f))[0] for f in sorted(glob.glob(os.path.join(CL, "target_kb", "*.json")) + glob.glob(os.path.join(HERE, "cyclic_llm_mod", "target_kb", "*.json")))
               if "dpo" not in f and "result" not in f and "induced" not in f and "generated" not in f and "neural" not in f]
    seen, rows = set(), []
    for t in targets:
        try:
            ents = E.all_entries(t)
        except Exception as e:  # noqa: BLE001
            print("skip", t, e, file=sys.stderr)
            continue
        for e in ents:
            if not getattr(e, "admitted", False) or e.kind in E.CONFIG_KINDS:
                continue
            if e.statement in seen:
                continue
            seen.add(e.statement)
            p, s = classify(e.statement)
            rows.append({"property": p, "substructure_class": s, "doi": (e.provenance or {}).get("ref") or e.id,
                         "tier": (e.provenance or {}).get("evidence_tier", "T2"), "statement": e.statement[:200], "kind": e.kind})
    json.dump(rows, open(out, "w"), indent=1)
    print("before-KB statements:", len(rows))


if __name__ == "__main__":
    main(sys.argv[1])
