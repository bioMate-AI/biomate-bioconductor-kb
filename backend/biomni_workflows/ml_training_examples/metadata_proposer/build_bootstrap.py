#!/usr/bin/env python3
# =============================================================================
# metadata_proposer / build_bootstrap.py
# =============================================================================
# BOOTSTRAP dataset builder for the per-client metadata-mapping PROPOSER.
#
# WHY THIS EXISTS
# ---------------
# The harmonization survey (docs/20260727_HARMONIZATION_SURVEY.md) verified that
# LLM-ONLY metadata mapping is ~96% accurate in-dictionary but collapses to ~17%
# out-of-dictionary AND hallucinates ontology IDs. So the per-client model must
# never be trained to EMIT an ID. It is trained to SELECT a grounded candidate
# (retrieved from a real ontology) or ABSTAIN. This builder produces the data
# for exactly that objective.
#
# WHAT IT PRODUCES
# ----------------
#   ontology_seed.csv    a controlled-vocabulary seed (term_id, term_label,
#                        synonyms) with REAL ontology IDs from EFO / Mondo / HPO
#                        / Cell Ontology (CL). This is the retriever's dictionary
#                        AND the ground truth of "what an ID is allowed to be".
#   train.jsonl          {input, gold_term_id, gold_label, in_dictionary} rows
#   eval.jsonl           held-out split, same schema
#   instructions.jsonl   the SAME rows rendered as {instruction, output} pairs
#                        for the Ludwig LoRA drop-in (mirrors the stratification
#                        _adapter format), where output is a SELECT/ABSTAIN
#                        decision — never a free-form ID.
#
# GROUNDING GUARANTEE
# -------------------
# Every gold_term_id for an in-dictionary example is literally present in
# ontology_seed.csv. Every OUT-OF-DICTIONARY example has gold_term_id == "ABSTAIN"
# and there is deliberately NO ontology row that should match it. The eval script
# checks that the proposer NEVER outputs an ID absent from the retrieved candidate
# set (hallucination rate must be 0 by construction).
#
# All IDs below are real, stable public ontology identifiers (EFO/Mondo/HPO/CL).
# Data is a hand-encoded realistic SEED, not a full corpus — see README for how
# text2term over full EFO/Mondo replaces this at scale.
# =============================================================================

import csv
import json
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
random.seed(42)

# -----------------------------------------------------------------------------
# 1. ONTOLOGY SEED — real IDs, canonical labels, real synonyms.
#    (term_id, canonical_label, [synonyms...])
#    Sources: EFO (www.ebi.ac.uk/efo), Mondo (mondo.monarchinitiative.org),
#    HPO (hpo.jax.org), Cell Ontology (obofoundry.org/ontology/cl).
# -----------------------------------------------------------------------------
ONTOLOGY_SEED = [
    # --- diseases: Mondo / EFO ------------------------------------------------
    ("MONDO:0008383", "rheumatoid arthritis",
     ["RA", "rheumatoid arthritis (disorder)"]),
    ("MONDO:0011849", "juvenile rheumatoid arthritis",
     ["juvenile idiopathic arthritis", "JIA", "juvenile RA"]),
    ("MONDO:0007915", "systemic lupus erythematosus",
     ["SLE", "lupus", "systemic lupus"]),
    ("MONDO:0005301", "multiple sclerosis",
     ["MS", "disseminated sclerosis"]),
    ("MONDO:0005147", "type 1 diabetes mellitus",
     ["T1D", "type 1 diabetes", "insulin-dependent diabetes mellitus", "IDDM"]),
    ("MONDO:0005148", "type 2 diabetes mellitus",
     ["T2D", "type 2 diabetes", "non-insulin-dependent diabetes mellitus"]),
    ("MONDO:0005011", "Crohn disease",
     ["Crohn's disease", "CD", "regional enteritis"]),
    ("MONDO:0005101", "ulcerative colitis",
     ["UC", "colitis ulcerosa"]),
    ("MONDO:0004979", "asthma",
     ["bronchial asthma"]),
    ("MONDO:0007256", "systemic scleroderma",
     ["systemic sclerosis", "SSc", "scleroderma"]),
    ("EFO:0000685", "rheumatoid arthritis (EFO)",
     []),  # EFO cross-listing kept distinct on purpose (near-synonym trap)

    # --- cell types: Cell Ontology (CL) --------------------------------------
    ("CL:0000624", "CD4-positive, alpha-beta T cell",
     ["CD4+ T cell", "CD4 T cell", "helper T cell", "CD4 positive T lymphocyte"]),
    ("CL:0000625", "CD8-positive, alpha-beta T cell",
     ["CD8+ T cell", "CD8 T cell", "cytotoxic T cell", "CD8 positive T lymphocyte"]),
    ("CL:0000236", "B cell",
     ["B lymphocyte", "B-cell"]),
    ("CL:0000235", "macrophage",
     ["macrophages"]),
    ("CL:0000784", "plasmacytoid dendritic cell",
     ["pDC", "plasmacytoid DC"]),
    ("CL:0000451", "dendritic cell",
     ["DC", "dendritic cells"]),
    ("CL:0000939", "CD16-negative, CD56-bright natural killer cell",
     ["CD56 bright NK cell", "CD56bright NK"]),
    ("CL:0000814", "mature NK T cell",
     ["NKT cell", "natural killer T cell"]),
    ("CL:2000001", "peripheral blood mononuclear cell",
     ["PBMC", "PBMCs", "peripheral blood mononuclear cells"]),
    ("CL:0000576", "monocyte",
     ["monocytes"]),
    ("CL:0000771", "eosinophil",
     ["eosinophils", "eosinophilic granulocyte"]),

    # --- phenotypes: HPO ------------------------------------------------------
    ("HP:0002960", "Autoimmunity",
     ["autoimmune", "autoimmune reaction"]),
    ("HP:0001369", "Arthritis",
     ["joint inflammation"]),
    ("HP:0000988", "Skin rash",
     ["rash", "cutaneous rash"]),
    ("HP:0001945", "Fever",
     ["pyrexia", "febrile"]),
    ("HP:0002829", "Arthralgia",
     ["joint pain", "arthralgias"]),
    ("HP:0000969", "Edema",
     ["oedema", "swelling"]),
]

# -----------------------------------------------------------------------------
# 2. IN-DICTIONARY examples — messy free-text -> the gold ontology ID it maps to.
#    Deliberately messy: abbreviations, typos, casing, punctuation, plurals.
#    Every gold_term_id here EXISTS in ONTOLOGY_SEED above.
# -----------------------------------------------------------------------------
IN_DICT = [
    # rheumatoid arthritis cluster
    ("RA", "MONDO:0008383"),
    ("rheumatoid arth.", "MONDO:0008383"),
    ("Rheumatoid Arthritis", "MONDO:0008383"),
    ("rheum. arthritis", "MONDO:0008383"),
    ("rheumatoid arthritis (disorder)", "MONDO:0008383"),
    # juvenile RA
    ("JIA", "MONDO:0011849"),
    ("juvenile idiopathic arthritis", "MONDO:0011849"),
    ("juvenile RA", "MONDO:0011849"),
    # SLE
    ("SLE", "MONDO:0007915"),
    ("lupus", "MONDO:0007915"),
    ("systemic lupus erythematosus", "MONDO:0007915"),
    # MS
    ("MS", "MONDO:0005301"),
    ("multiple sclerosis", "MONDO:0005301"),
    # diabetes
    ("T1D", "MONDO:0005147"),
    ("type 1 diabetes", "MONDO:0005147"),
    ("IDDM", "MONDO:0005147"),
    ("T2D", "MONDO:0005148"),
    ("type 2 diabetes mellitus", "MONDO:0005148"),
    # IBD
    ("Crohn's disease", "MONDO:0005011"),
    ("crohn disease", "MONDO:0005011"),
    ("CD", "MONDO:0005011"),
    ("ulcerative colitis", "MONDO:0005101"),
    ("UC", "MONDO:0005101"),
    # asthma / scleroderma
    ("asthma", "MONDO:0004979"),
    ("bronchial asthma", "MONDO:0004979"),
    ("systemic sclerosis", "MONDO:0007256"),
    ("scleroderma", "MONDO:0007256"),

    # cell types (CL)
    ("CD4+ T cell", "CL:0000624"),
    ("CD4 T cell", "CL:0000624"),
    ("helper T cell", "CL:0000624"),
    ("CD4-positive, alpha-beta T cell", "CL:0000624"),
    ("CD8+ T cell", "CL:0000625"),
    ("cytotoxic T cell", "CL:0000625"),
    ("CD8 T cells", "CL:0000625"),
    ("B cell", "CL:0000236"),
    ("B lymphocyte", "CL:0000236"),
    ("B-cell", "CL:0000236"),
    ("macrophage", "CL:0000235"),
    ("macrophages", "CL:0000235"),
    ("pDC", "CL:0000784"),
    ("plasmacytoid dendritic cell", "CL:0000784"),
    ("dendritic cell", "CL:0000451"),
    ("DC", "CL:0000451"),
    ("peripheral blood mononuclear cells", "CL:2000001"),
    ("PBMC", "CL:2000001"),
    ("PBMCs", "CL:2000001"),
    ("monocyte", "CL:0000576"),
    ("monocytes", "CL:0000576"),
    ("eosinophils", "CL:0000771"),
    ("NKT cell", "CL:0000814"),
    ("CD56 bright NK cell", "CL:0000939"),

    # phenotypes (HPO)
    ("autoimmunity", "HP:0002960"),
    ("autoimmune", "HP:0002960"),
    ("arthritis", "HP:0001369"),
    ("joint inflammation", "HP:0001369"),
    ("skin rash", "HP:0000988"),
    ("rash", "HP:0000988"),
    ("fever", "HP:0001945"),
    ("pyrexia", "HP:0001945"),
    ("joint pain", "HP:0002829"),
    ("arthralgia", "HP:0002829"),
    ("swelling", "HP:0000969"),
    ("oedema", "HP:0000969"),
]

# -----------------------------------------------------------------------------
# 3. OUT-OF-DICTIONARY negatives — free-text with NO correct ontology term in
#    the seed. These MUST map to ABSTAIN. If the proposer emits any ID for these,
#    that is a hallucination. Chosen to be plausible-but-absent: clinical prose,
#    novel/administrative terms, assay codes, free-text notes, and near-miss
#    terms whose true concept is simply not in the seed dictionary.
# -----------------------------------------------------------------------------
OOD = [
    "pt reported joint stiffness worst in AM, better w movement",
    "sample stored at -80C for 14 months, single freeze-thaw",
    "batch QC failed — RIN 3.2, excluded from integration",
    "site 4 collection protocol v2.1 amendment pending IRB",
    "cyclic peptide macrocycle permeability assay plate 7",
    "responder per investigator global assessment week 24",
    "flow panel P3 gate: live singlets, CD45+",
    "concomitant medication: methotrexate 15mg weekly",
    "spatial transcriptomics ROI annotated by pathologist",
    "novel endotype cluster 3 (unpublished, internal name)",
    "left knee synovial biopsy, formalin-fixed",
    "HLA-DRB1 shared-epitope genotype pending",
    "adverse event grade 2 injection-site reaction",
    "cohort C enrolled under compassionate-use pathway",
    "instrument: 10x Chromium Next GEM 3' v3.1",
    "quality flag: doublet-enriched, needs re-sort",
    "clinician note: query overlap syndrome, refer rheum",
    "specimen SPREC code TTL-A-Z-B",
]

# -----------------------------------------------------------------------------
# builders
# -----------------------------------------------------------------------------
def build_ontology_csv(path):
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["term_id", "term_label", "synonyms"])
        for tid, label, syns in ONTOLOGY_SEED:
            w.writerow([tid, label, "|".join(syns)])
    # ground-truth ID set (the ONLY IDs an emitter is ever allowed to produce)
    return {tid for tid, _, _ in ONTOLOGY_SEED}


def _label_for(tid):
    for t, label, _ in ONTOLOGY_SEED:
        if t == tid:
            return label
    return ""


def build_rows():
    rows = []
    for text, gold in IN_DICT:
        rows.append({
            "input": text,
            "gold_term_id": gold,
            "gold_label": _label_for(gold),
            "in_dictionary": True,
        })
    for text in OOD:
        rows.append({
            "input": text,
            "gold_term_id": "ABSTAIN",
            "gold_label": "",
            "in_dictionary": False,
        })
    return rows


def split_rows(rows, eval_frac=0.30):
    # stratified split so eval contains BOTH in-dict and OOD examples
    in_dict = [r for r in rows if r["in_dictionary"]]
    ood = [r for r in rows if not r["in_dictionary"]]
    random.shuffle(in_dict)
    random.shuffle(ood)

    def cut(lst):
        k = max(1, round(len(lst) * eval_frac))
        return lst[k:], lst[:k]  # train, eval

    tr_i, ev_i = cut(in_dict)
    tr_o, ev_o = cut(ood)
    train = tr_i + tr_o
    ev = ev_i + ev_o
    random.shuffle(train)
    random.shuffle(ev)
    return train, ev


def write_jsonl(path, rows):
    with open(path, "w") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")


# -----------------------------------------------------------------------------
# instruction rendering for the Ludwig LoRA drop-in.
# The output is a CONSTRAINED decision string, NOT a free-form ID. The model is
# taught to pick "SELECT <candidate_number>" or "ABSTAIN"; the harness maps the
# number back to a retrieved candidate ID, so the model can never emit an
# ungrounded identifier even at train time.
# -----------------------------------------------------------------------------
def render_instruction(text, candidates):
    lines = [
        "You are a metadata-mapping PROPOSER. Map the free-text metadata value "
        "to ONE of the numbered candidate ontology terms retrieved below, or "
        "ABSTAIN. You may ONLY answer 'SELECT <n>' for a listed candidate, or "
        "'ABSTAIN'. Never invent an ontology ID.",
        "",
        "VALUE: " + text,
        "",
        "CANDIDATES:",
    ]
    if candidates:
        for i, c in enumerate(candidates, 1):
            lines.append("  %d. %s  (%s)" % (i, c["label"], c["term_id"]))
    else:
        lines.append("  (none retrieved)")
    lines.append("")
    lines.append("ANSWER with 'SELECT <n>' or 'ABSTAIN':")
    return "\n".join(lines)


def build_instructions(rows, retriever):
    """Render each row as an {instruction, output} pair for Ludwig LoRA.

    Uses the SAME retriever the harness uses so the candidate list the model
    is trained on is identical to what it will see at inference. The gold
    output selects the candidate whose term_id == gold (if retrieved), else
    ABSTAIN — which is exactly the correct-and-grounded target.
    """
    out = []
    for r in rows:
        cands = retriever(r["input"])
        gold_idx = None
        for i, c in enumerate(cands, 1):
            if c["term_id"] == r["gold_term_id"]:
                gold_idx = i
                break
        if r["in_dictionary"] and gold_idx is not None:
            target = "SELECT %d" % gold_idx
        else:
            # OOD, or gold not retrieved -> the grounded-correct answer is ABSTAIN
            target = "ABSTAIN"
        out.append({
            "instruction": render_instruction(r["input"], cands),
            "output": target,
        })
    return out


def main():
    ont_path = os.path.join(HERE, "ontology_seed.csv")
    allowed_ids = build_ontology_csv(ont_path)

    rows = build_rows()
    train, ev = split_rows(rows)
    write_jsonl(os.path.join(HERE, "train.jsonl"), train)
    write_jsonl(os.path.join(HERE, "eval.jsonl"), ev)

    # build instruction pairs using the real retriever (import here to avoid a
    # cycle at module import; retriever depends only on the ontology CSV)
    from constrained_decoder import Retriever
    retr = Retriever(ont_path)
    train_instr = build_instructions(train, retr.retrieve)
    ev_instr = build_instructions(ev, retr.retrieve)
    write_jsonl(os.path.join(HERE, "instructions_train.jsonl"), train_instr)
    write_jsonl(os.path.join(HERE, "instructions_eval.jsonl"), ev_instr)

    print("=== BOOTSTRAP BUILD ===")
    print("  ontology seed terms : %d  (allowed IDs: %d)"
          % (len(ONTOLOGY_SEED), len(allowed_ids)))
    print("  in-dictionary rows  : %d" % len(IN_DICT))
    print("  out-of-dict rows    : %d" % len(OOD))
    print("  train / eval split  : %d / %d" % (len(train), len(ev)))
    print("  eval in-dict / OOD  : %d / %d"
          % (sum(1 for r in ev if r["in_dictionary"]),
             sum(1 for r in ev if not r["in_dictionary"])))
    print("  wrote: ontology_seed.csv, train.jsonl, eval.jsonl,")
    print("         instructions_train.jsonl, instructions_eval.jsonl")


if __name__ == "__main__":
    main()
