"""Verbalize FULL biomedical KGs into natural-language text for mid-training (continued pretraining).
- PrimeKG (Harvard Dataverse kg.csv, ~8.1M edges, 30 relations) -> typed sentences (curated phrase map + fallback).
- MAP-KG (HF RainGate/MAP-KG GENE-GENE + DRUG-GENE) -> uses its built-in NL relation strings.
NOT the immune subgraph — the full graphs. stdlib-only (csv), header-driven. Writes {"text","source"} jsonl.
Usage: python build_kg_corpus.py --primekg kg.csv --mapkg-gg gg.csv --mapkg-dg dg.csv --out kg_corpus.jsonl
"""
import argparse, csv, json, os
csv.field_size_limit(10 ** 7)

# curated readable phrases for PrimeKG display_relation / relation; generic fallback otherwise
PHRASE = {
    "ppi": "physically interacts with", "protein_protein": "physically interacts with",
    "target": "is a molecular target of the drug", "enzyme": "is metabolized by the enzyme",
    "carrier": "is carried by", "transporter": "is transported by",
    "drug_protein": "acts on", "drug_effect": "causes the effect", "contraindication": "is contraindicated in",
    "indication": "is indicated for", "off-label use": "is used off-label for", "drug_drug": "interacts with the drug",
    "associated with": "is associated with", "disease_protein": "is genetically associated with",
    "phenotype_protein": "is linked to the phenotype", "phenotype_phenotype": "is a subtype of the phenotype",
    "disease_phenotype_positive": "commonly presents with", "disease_phenotype_negative": "is not typically associated with",
    "disease_disease": "is related to", "pathway_protein": "participates in the pathway",
    "bioprocess_protein": "is involved in the biological process", "molfunc_protein": "has the molecular function",
    "cellcomp_protein": "localizes to", "anatomy_protein_present": "is expressed in",
    "anatomy_protein_absent": "is not expressed in", "exposure_protein": "is affected by exposure to",
    "exposure_disease": "influences the disease", "exposure_bioprocess": "affects the process",
    "pathway_pathway": "is a subpathway of", "bioprocess_bioprocess": "is a subprocess of",
    "molfunc_molfunc": "is a subtype of", "cellcomp_cellcomp": "is part of", "anatomy_anatomy": "is part of",
}


def col(row, *names):
    for n in names:
        if n in row and row[n]: return row[n]
    return ""


def primekg(path, fo):
    n = 0
    with open(path, newline="") as f:
        rd = csv.DictReader(f)
        print(f"[kg] PrimeKG header: {rd.fieldnames}", flush=True)
        for r in rd:
            rel = col(r, "display_relation", "relation")
            x, y = col(r, "x_name"), col(r, "y_name")
            xt, yt = col(r, "x_type"), col(r, "y_type")
            if not (x and y and rel): continue
            phrase = PHRASE.get(rel) or PHRASE.get(col(r, "relation")) or rel.replace("_", " ")
            txt = f"{x} ({xt}) {phrase} {y} ({yt})." if xt and yt else f"{x} {phrase} {y}."
            fo.write(json.dumps({"text": txt, "source": "primekg"}) + "\n"); n += 1
            if n % 1000000 == 0: print(f"[kg] primekg {n:,}", flush=True)
    return n


def mapkg(path, fo, kind):
    if not path or not os.path.exists(path): return 0
    n = 0
    with open(path, newline="") as f:
        rd = csv.DictReader(f)
        print(f"[kg] MAP-KG {kind} header: {rd.fieldnames}", flush=True)
        for r in rd:
            i = col(r, "i_symbol", "gene", "gene_symbol", "j_symbol_i", "source", "head")
            j = col(r, "j_symbol", "drug", "drug_name", "target", "tail")
            rel = col(r, "relation", "relation_text", "edge_type")
            if kind == "drug-gene":
                i = col(r, "drug", "drug_name", "i_symbol", "source", "head") or i
                j = col(r, "gene", "gene_symbol", "j_symbol", "target", "tail") or j
            if not (i and j): continue
            rel = rel or ("is associated with" if kind == "gene-gene" else "targets")
            fo.write(json.dumps({"text": f"{i} {rel} {j}.", "source": f"mapkg_{kind}"}) + "\n"); n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--primekg", default=""); ap.add_argument("--mapkg-gg", default=""); ap.add_argument("--mapkg-dg", default="")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    counts = {}
    with open(a.out, "w") as fo:
        if a.primekg and os.path.exists(a.primekg): counts["primekg"] = primekg(a.primekg, fo)
        counts["mapkg_gene-gene"] = mapkg(a.mapkg_gg, fo, "gene-gene")
        counts["mapkg_drug-gene"] = mapkg(a.mapkg_dg, fo, "drug-gene")
    tot = sum(counts.values()); toks = os.path.getsize(a.out) // 4
    print(f"KG DONE: {counts} | total {tot:,} edges, ~{toks:,} tokens -> {a.out}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
