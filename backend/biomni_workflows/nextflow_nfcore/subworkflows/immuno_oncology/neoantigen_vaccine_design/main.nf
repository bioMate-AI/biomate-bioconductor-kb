#!/usr/bin/env nextflow
/*
 * immuno_oncology/neoantigen_vaccine_design
 *
 * END-TO-END personalized NEOANTIGEN VACCINE design. Takes a patient's somatic
 * missense / indel neoepitopes and produces a ranked, MHC-prioritized
 * multi-epitope vaccine construct (protein + codon-reasonable DNA/mRNA). This is
 * an IN-SILICO DESIGN pipeline, NOT a validated vaccine: every candidate must be
 * confirmed by immunogenicity assay (ELISpot / tetramer / in-vivo) before use.
 *
 * CHAIN (each stage feeds the next; runs end-to-end on the built-in demo with no
 * user input):
 *   1. ENUMERATE_NEOEPITOPES  somatic variants -> mutant 8..11mer neoepitopes
 *      spanning each missense/indel site, plus the matched wild-type window
 *      (for agretopicity). A real somatic VCF + reference proteome is accepted
 *      (params.vcf / params.proteome) but the DEMO path uses a small built-in
 *      {gene, wt_peptide, mut_peptide} list and needs neither.
 *   2. PREDICT_BINDING         MHC class-I binding with MHCflurry 2 (O'Donnell
 *      et al., Cell Systems 2020; open-source, Apache-2.0). Fans out ONE PROCESS
 *      PER ALLELE so AWS Batch scores every HLA allele in PARALLEL. Scores are
 *      MHCflurry's own affinity_nM + affinity_percentile (%rank) — never
 *      fabricated. Both the mutant and its matched wild-type window are scored so
 *      the ranker can compute agretopicity (mutation-specific presentation gain).
 *      Class II (HLA-DR/DP/DQ) is OUT OF SCOPE here (MHCflurry 2 is class-I only);
 *      see the mhc_binding_prediction subworkflow note for the class-II gap.
 *   3. RANK_AND_BUILD          joins predictions back to neoepitopes, ranks by
 *      %rank / affinity / agretopicity, assembles the top-N distinct mutant
 *      epitopes into a DRAFT multi-epitope vaccine protein (epitopes joined by a
 *      GPGPG/AAY linker, Met start), codon-optimizes to a human DNA CDS and mRNA
 *      (Kozak + stop), and writes the final summary.json + qc_metrics.json. It
 *      LOUD-FAILS (raise SystemExit("FATAL: ...")) if no neoepitope could be
 *      ranked, rather than emitting an empty/placeholder construct.
 *
 * HONEST SCOPE / what this is NOT:
 *   - A computational prioritization + construct DRAFT, not a validated vaccine.
 *     Binding prediction != immunogenicity: a strong MHC binder may not be
 *     presented or T-cell reactive. Confirm every epitope experimentally.
 *   - Class-I only. No TCR-recognition, no proteasomal-cleavage model beyond
 *     MHCflurry's processing score, no self-tolerance / proteome-subtraction
 *     filtering of the demo path (a stated future increment, see params.proteome).
 *   - pVACtools (pvacseq, griffithlab/pvactools) is the heavier full-VCF
 *     alternative; this subworkflow deliberately implements the lightweight
 *     peptide-list + MHCflurry chain so it runs end-to-end in one small container.
 *
 * Inputs (params):
 *   params.variants         JSON list of {gene, wt_peptide, mut_peptide} neoepitope
 *                           windows (demo default below). Full-length windows;
 *                           the differing residue(s) between wt/mut are the mutation.
 *   params.alleles          JSON list of class-I HLA alleles -> one parallel task each.
 *   params.peptide_lengths  comma list of neoepitope k-mer lengths (default "8,9,10,11").
 *   params.linker           epitope join linker for the construct (default "GPGPG").
 *   params.top_n            distinct epitopes carried into the construct (default 10).
 *   params.strong_rank      affinity_percentile <= this -> strong binder (default 2.0).
 *   params.weak_rank        affinity_percentile <= this -> weak  binder (default 10.0).
 *   params.vcf              optional real somatic VCF (future full path; demo ignores).
 *   params.proteome         optional reference proteome for self-filtering (future).
 *   params.sample_id        label (metadata only).
 *   params.outdir           output directory (default 'results').
 *
 * Container: biomate/mhcflurry image (micromamba py3.11 + `pip install mhcflurry`
 * + `mhcflurry-downloads fetch models_class1_presentation` baked in; Batch has no
 * reliable run-time network to fetch models). Enumeration + ranking use only the
 * py3 stdlib, so they share the same image. Build + push before first run,
 * mirroring the mhc_binding_prediction image. CPU only, no GPU.
 */

nextflow.enable.dsl = 2

// Note: use fully-qualified groovy.json.* (no top-level import) — Nextflow
// strict/classic parsers reject `import groovy.json.*` as a script compile error
// on some Batch head images.

// Demo defaults (overridden by BioMate's executor at launch). A small built-in
// set of illustrative missense neoepitope windows (wt vs mut differ by one
// residue) so the pipeline runs end-to-end with NO user input. These are
// SYNTHETIC teaching examples, not a real patient's calls.
params.variants = '''[
 {"gene":"KRAS","wt_peptide":"VVGAGGVGKSALTIQLIQNH","mut_peptide":"VVGAVGVGKSALTIQLIQNH"},
 {"gene":"TP53","wt_peptide":"RNTFRHSVVVPYEPPEVGSD","mut_peptide":"RNTFRHSVVVPYEPPEVHSD"},
 {"gene":"PIK3CA","wt_peptide":"EDLRQQLAFHGSWTTKRELS","mut_peptide":"EDLRQQLAFKGSWTTKRELS"}
]'''
params.alleles         = '["HLA-A*02:01","HLA-B*07:02"]'
params.peptide_lengths = '8,9,10,11'
params.linker          = 'GPGPG'
params.top_n           = '10'
params.strong_rank     = '2.0'
params.weak_rank       = '10.0'
params.vcf             = ''
params.proteome        = ''
params.sample_id       = 'demo_patient'
params.outdir          = 'results'

process ENUMERATE_NEOEPITOPES {
    tag "${params.sample_id}"
    label 'process_low'
    publishDir { "${params.outdir}/neoantigen_vaccine" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/mhcflurry:x86' : 'biomate/mhcflurry:latest'

    input:
    val variants_json

    output:
    path "neoepitopes.csv",         emit: neoepitopes
    path "peptides.json",           emit: peptides
    path "enumerate_summary.json",  emit: summary
    path "versions.yml",            emit: versions

    script:
    """
    export VARIANTS_JSON='${variants_json}'
    export PEPTIDE_LENGTHS='${params.peptide_lengths}'
    export SAMPLE_ID='${params.sample_id}'

    python3 << 'PYEOF'
import os, json, sys, csv

sample = os.environ.get("SAMPLE_ID", "sample")
try:
    variants = json.loads(os.environ.get("VARIANTS_JSON") or "[]")
except Exception as e:
    sys.exit("FATAL: could not parse params.variants JSON: %s" % e)
try:
    lengths = [int(x) for x in str(os.environ.get("PEPTIDE_LENGTHS", "8,9,10,11")).split(",") if str(x).strip()]
except Exception as e:
    sys.exit("FATAL: could not parse params.peptide_lengths: %s" % e)
lengths = sorted(set(L for L in lengths if L >= 7))
if not variants:
    sys.exit("FATAL: no variants supplied (params.variants empty)")
if not lengths:
    sys.exit("FATAL: no valid peptide lengths supplied")

AA = set("ACDEFGHIKLMNPQRSTVWY")

def clean(s):
    return str(s or "").strip().upper().replace(" ", "")

rows = []
peptide_set = set()
neo_id = 0
for vi, v in enumerate(variants):
    gene = str(v.get("gene") or v.get("name") or ("var%d" % vi)).strip()
    wt   = clean(v.get("wt_peptide") or v.get("wt") or "")
    mut  = clean(v.get("mut_peptide") or v.get("mut") or v.get("peptide") or "")
    variant_id = str(v.get("variant_id") or v.get("id") or ("%s_%d" % (gene, vi)))
    if not mut or (set(mut) - AA):
        # skip a variant with no usable mutant protein window rather than invent one
        continue
    is_indel = (len(wt) != len(mut)) or (not wt) or bool(set(wt) - AA)
    # mutation positions = residues that differ between the matched wt / mut window
    if not is_indel:
        mut_pos = [i for i in range(len(mut)) if wt[i] != mut[i]]
    else:
        mut_pos = None  # indel / no clean wt -> keep every window spanning the site
    for L in lengths:
        if L > len(mut):
            continue
        for s in range(0, len(mut) - L + 1):
            win = mut[s:s+L]
            # only keep windows that actually contain a mutated residue
            if mut_pos is not None:
                if not any(s <= p < s + L for p in mut_pos):
                    continue
            if set(win) - AA:
                continue
            wt_win = ""
            if not is_indel and (s + L) <= len(wt):
                wt_win = wt[s:s+L]
                if set(wt_win) - AA:
                    wt_win = ""
            neo_id += 1
            rows.append({
                "neo_id": "neo_%d" % neo_id,
                "gene": gene,
                "variant_id": variant_id,
                "length": L,
                "window_start": s + 1,
                "mut_peptide": win,
                "wt_peptide": wt_win,
                "is_indel": 1 if is_indel else 0,
            })
            peptide_set.add(win)
            if wt_win:
                peptide_set.add(wt_win)

if not rows:
    sys.exit("FATAL: no neoepitopes could be enumerated from the supplied variants "
             "(check that mut_peptide windows are clean protein sequences and differ "
             "from wt_peptide).")

cols = ["neo_id", "gene", "variant_id", "length", "window_start",
        "mut_peptide", "wt_peptide", "is_indel"]
with open("neoepitopes.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=cols)
    w.writeheader()
    for r in rows:
        w.writerow(r)

peptides = sorted(peptide_set)
with open("peptides.json", "w") as fh:
    json.dump(peptides, fh)

summary = {
    "sample_id": sample,
    "n_variants": len(variants),
    "n_neoepitope_windows": len(rows),
    "n_unique_peptides": len(peptides),
    "peptide_lengths": lengths,
    "status": "ok",
    "note": "Mutant 8..11mer windows spanning each missense/indel site, with the "
            "matched wild-type window kept for agretopicity. Enumeration is "
            "deterministic; no scores invented here.",
}
with open("enumerate_summary.json", "w") as fh:
    json.dump(summary, fh, indent=2)
print(json.dumps({k: summary[k] for k in ("n_variants", "n_neoepitope_windows", "n_unique_peptides", "status")}, indent=2))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        method: "neoepitope k-mer enumeration (missense/indel window spanning)"
    END_VERSIONS
    """
}

process PREDICT_BINDING {
    tag "${allele}"
    label 'process_low'
    publishDir { "${params.outdir}/neoantigen_vaccine/binding/${allele.replaceAll('[^A-Za-z0-9]', '_')}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/mhcflurry:x86' : 'biomate/mhcflurry:latest'

    input:
    tuple val(allele), path(peptides_json)

    output:
    tuple val(allele), path("predictions.csv"), emit: predictions
    tuple val(allele), path("summary.json"),    emit: summary

    script:
    """
    export ALLELE='${allele}'
    export PEPTIDES_FILE='${peptides_json}'
    export SAMPLE_ID='${params.sample_id}'
    export STRONG_RANK='${params.strong_rank}'
    export WEAK_RANK='${params.weak_rank}'

    python3 << 'PYEOF'
import os, json, sys, csv

allele   = os.environ["ALLELE"].strip()
sample   = os.environ.get("SAMPLE_ID", "sample")
strong_r = float(os.environ.get("STRONG_RANK", "2.0") or 2.0)
weak_r   = float(os.environ.get("WEAK_RANK", "10.0") or 10.0)
try:
    with open(os.environ["PEPTIDES_FILE"]) as fh:
        peptides = json.load(fh)
except Exception as e:
    sys.exit("FATAL: could not read enumerated peptides JSON: %s" % e)
peptides = [str(p).strip().upper() for p in peptides if str(p).strip()]
if not allele:
    sys.exit("FATAL: empty allele")
if not peptides:
    sys.exit("FATAL: no peptides supplied for binding prediction")

# MHCflurry scores 8..15mers; keep those, record the rest as unscorable (null)
scorable   = [p for p in peptides if 8 <= len(p) <= 15 and p.isalpha()]
unscorable = [p for p in peptides if p not in scorable]

try:
    from mhcflurry import Class1PresentationPredictor
    import mhcflurry as _mf
except Exception as e:
    sys.exit("FATAL: MHCflurry not available in this image (%s). The "
             "biomate/mhcflurry image must be built with `pip install mhcflurry` "
             "and `mhcflurry-downloads fetch models_class1_presentation`." % e)

predictor = Class1PresentationPredictor.load()

rows = []
if scorable:
    try:
        df = predictor.predict(peptides=scorable, alleles=[allele], verbose=0,
                               include_affinity_percentile=True)
    except Exception as e:
        sys.exit("FATAL: MHCflurry predict failed for allele %s: %s" % (allele, e))

    def col(r, *names):
        for n in names:
            if n in r and r[n] is not None:
                return r[n]
        return None

    for _, r in df.iterrows():
        rr = r.to_dict()
        aff  = col(rr, "affinity")
        pct  = col(rr, "affinity_percentile")
        pres = col(rr, "presentation_score")
        proc = col(rr, "processing_score")
        pctf = float(pct) if pct is not None else None
        binder = None
        if pctf is not None:
            binder = "strong" if pctf <= strong_r else ("weak" if pctf <= weak_r else "none")
        rows.append({
            "peptide": col(rr, "peptide"),
            "hla_allele": allele,
            "affinity_nM": round(float(aff), 2) if aff is not None else None,
            "affinity_percentile": round(pctf, 4) if pctf is not None else None,
            "presentation_score": round(float(pres), 4) if pres is not None else None,
            "processing_score": round(float(proc), 4) if proc is not None else None,
            "binder": binder,
        })

for p in unscorable:
    rows.append({"peptide": p, "hla_allele": allele, "affinity_nM": None,
                 "affinity_percentile": None, "presentation_score": None,
                 "processing_score": None, "binder": None})

if not rows:
    sys.exit("FATAL: MHCflurry produced no predictions for allele %s" % allele)

cols = ["peptide", "hla_allele", "affinity_nM", "affinity_percentile",
        "presentation_score", "processing_score", "binder"]
with open("predictions.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=cols)
    w.writeheader()
    for r in rows:
        w.writerow(r)

summary = {
    "sample_id": sample,
    "allele": allele,
    "tool": "MHCflurry 2",
    "tool_version": getattr(_mf, "__version__", "unknown"),
    "mhc_class": "I",
    "n_peptides": len(peptides),
    "n_scored": sum(1 for r in rows if r["affinity_percentile"] is not None),
    "n_unscorable": len(unscorable),
    "n_strong_binders": sum(1 for r in rows if r["binder"] == "strong"),
    "n_weak_binders": sum(1 for r in rows if r["binder"] == "weak"),
    "status": "ok",
}
with open("summary.json", "w") as fh:
    json.dump(summary, fh, indent=2)
print(json.dumps(summary, indent=2))
PYEOF
    """
}

process RANK_AND_BUILD {
    tag "${params.sample_id}"
    label 'process_low'
    publishDir { "${params.outdir}/neoantigen_vaccine" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/mhcflurry:x86' : 'biomate/mhcflurry:latest'

    input:
    path "neoepitopes.csv"
    path "pred_*.csv"

    output:
    path "ranked_neoepitopes.csv", emit: ranked
    path "vaccine_construct.json", emit: construct
    path "summary.json",           emit: summary
    path "qc_metrics.json",        emit: qc

    script:
    """
    export SAMPLE_ID='${params.sample_id}'
    export LINKER='${params.linker}'
    export TOP_N='${params.top_n}'
    export STRONG_RANK='${params.strong_rank}'
    export WEAK_RANK='${params.weak_rank}'

    python3 << 'PYEOF'
import os, json, sys, csv, glob

sample   = os.environ.get("SAMPLE_ID", "sample")
linker   = str(os.environ.get("LINKER", "GPGPG")).strip().upper() or "GPGPG"
top_n    = int(float(os.environ.get("TOP_N", "10") or 10))
strong_r = float(os.environ.get("STRONG_RANK", "2.0") or 2.0)
weak_r   = float(os.environ.get("WEAK_RANK", "10.0") or 10.0)

AA = set("ACDEFGHIKLMNPQRSTVWY")

def fnum(v):
    try:
        if v is None or v == "" or str(v).lower() == "none":
            return None
        return float(v)
    except Exception:
        return None

# ---- load MHCflurry predictions, keyed by (peptide, allele) ----
pred = {}
alleles = set()
for fn in sorted(glob.glob("pred_*.csv")):
    with open(fn, newline="") as fh:
        for r in csv.DictReader(fh):
            pep = (r.get("peptide") or "").strip().upper()
            al  = (r.get("hla_allele") or "").strip()
            if not pep or not al:
                continue
            alleles.add(al)
            pred[(pep, al)] = {
                "affinity_nM": fnum(r.get("affinity_nM")),
                "affinity_percentile": fnum(r.get("affinity_percentile")),
                "presentation_score": fnum(r.get("presentation_score")),
                "binder": r.get("binder"),
            }
alleles = sorted(alleles)

# ---- load neoepitope mapping ----
neos = []
with open("neoepitopes.csv", newline="") as fh:
    for r in csv.DictReader(fh):
        neos.append(r)

# ---- join: one ranked row per (neoepitope window, allele) that was scored ----
ranked = []
for neo in neos:
    mut = (neo.get("mut_peptide") or "").strip().upper()
    wt  = (neo.get("wt_peptide") or "").strip().upper()
    for al in alleles:
        pm = pred.get((mut, al))
        if pm is None or pm.get("affinity_percentile") is None:
            continue
        pw = pred.get((wt, al)) if wt else None
        wt_nM = pw.get("affinity_nM") if pw else None
        mut_nM = pm.get("affinity_nM")
        # agretopicity (differential agretopicity index): wt_nM / mut_nM.
        # >1 => mutant binds MHC more strongly than self (mutation-specific gain).
        agret = None
        if wt_nM is not None and mut_nM not in (None, 0):
            agret = round(wt_nM / mut_nM, 3)
        ranked.append({
            "gene": neo.get("gene"),
            "variant_id": neo.get("variant_id"),
            "peptide": mut,
            "wt_peptide": wt,
            "length": neo.get("length"),
            "allele": al,
            "affinity_nM": mut_nM,
            "affinity_percentile": pm.get("affinity_percentile"),
            "presentation_score": pm.get("presentation_score"),
            "binder": pm.get("binder"),
            "wt_affinity_nM": wt_nM,
            "agretopicity": agret,
        })

# rank: best (lowest) %rank first, then lowest affinity_nM, then highest agretopicity
def sort_key(r):
    pr = r["affinity_percentile"] if r["affinity_percentile"] is not None else 1e9
    af = r["affinity_nM"] if r["affinity_nM"] is not None else 1e9
    ag = r["agretopicity"] if r["agretopicity"] is not None else 0.0
    return (pr, af, -ag)

ranked.sort(key=sort_key)
for i, r in enumerate(ranked, 1):
    r["rank"] = i

if not ranked:
    # LOUD FAIL: nothing bound well enough to rank -> no construct possible
    sys.exit("FATAL: no neoepitope could be ranked (no MHCflurry prediction joined "
             "to any enumerated mutant peptide). Check that PREDICT_BINDING produced "
             "predictions and that peptide lengths overlap MHCflurry's 8..15mer range.")

cols = ["rank", "gene", "variant_id", "peptide", "wt_peptide", "length", "allele",
        "affinity_nM", "affinity_percentile", "presentation_score", "binder",
        "wt_affinity_nM", "agretopicity"]
with open("ranked_neoepitopes.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=cols)
    w.writeheader()
    for r in ranked:
        w.writerow({k: r.get(k) for k in cols})

# ---- assemble the multi-epitope vaccine construct (top-N distinct mut peptides) ----
seen, chosen = set(), []
for r in ranked:
    p = r["peptide"]
    if p and (set(p) - AA) == set() and p not in seen:
        seen.add(p)
        chosen.append(r)
    if len(chosen) >= top_n:
        break

epi_seqs = [r["peptide"] for r in chosen]
protein = "M" + linker.join(epi_seqs)   # Met start, epitopes joined by the linker

# high-frequency human codon per residue (incl. any linker residues)
CODON = {'A':'GCC','R':'CGG','N':'AAC','D':'GAC','C':'TGC','Q':'CAG','E':'GAG','G':'GGC',
         'H':'CAC','I':'ATC','L':'CTG','K':'AAG','M':'ATG','F':'TTC','P':'CCC','S':'AGC',
         'T':'ACC','W':'TGG','Y':'TAC','V':'GTG'}
cds = "".join(CODON[a] for a in protein if a in CODON)
dna = "GCCACC" + cds + "TAA"   # Kozak + CDS + stop (DNA alphabet)
mrna = dna.replace("T", "U")

construct = {
    "sample_id": sample,
    "built": True,
    "n_epitopes": len(chosen),
    "linker": "%s (epitope linker)" % linker,
    "epitopes": [
        {"rank": r["rank"], "gene": r["gene"], "peptide": r["peptide"],
         "allele": r["allele"], "affinity_nM": r["affinity_nM"],
         "affinity_percentile": r["affinity_percentile"],
         "agretopicity": r["agretopicity"]}
        for r in chosen
    ],
    "protein_construct": protein,
    "protein_length_aa": len(protein),
    "cds_dna": dna,
    "mrna": mrna,
    "mrna_length_nt": len(mrna),
    "note": "DRAFT multi-epitope neoantigen vaccine: top distinct MHC class-I "
            "neoepitopes joined by linkers (M start, Kozak GCCACC, human "
            "high-frequency codons, stop). IN-SILICO design only — binding "
            "prediction is not immunogenicity. Requires proteome self-filtering, "
            "folding/expression and immunogenicity validation before any use. No "
            "signal peptide / adjuvant / UTRs added here.",
}
with open("vaccine_construct.json", "w") as fh:
    json.dump(construct, fh, indent=2)

n_strong = sum(1 for r in ranked if r.get("binder") == "strong")
n_weak   = sum(1 for r in ranked if r.get("binder") == "weak")
summary = {
    "sample_id": sample,
    "pipeline": "neoantigen_vaccine_design",
    "n_alleles": len(alleles),
    "alleles": alleles,
    "n_ranked_neoepitope_allele_pairs": len(ranked),
    "n_strong_binders": n_strong,
    "n_weak_binders": n_weak,
    "top_neoepitope": {
        "gene": ranked[0].get("gene"), "peptide": ranked[0].get("peptide"),
        "allele": ranked[0].get("allele"), "affinity_nM": ranked[0].get("affinity_nM"),
        "affinity_percentile": ranked[0].get("affinity_percentile"),
        "agretopicity": ranked[0].get("agretopicity"),
    },
    "construct_epitopes": len(chosen),
    "construct_length_aa": len(protein),
    "construct_length_nt": len(mrna),
    "status": "ok",
    "note": "End-to-end in-silico neoantigen vaccine design (MHCflurry 2 class-I). "
            "A ranked shortlist + draft construct to validate experimentally, NOT a "
            "validated vaccine.",
}
with open("summary.json", "w") as fh:
    json.dump(summary, fh, indent=2)

qc = {
    "status": "ok",
    "n_alleles": len(alleles),
    "n_predictions": len(pred),
    "n_ranked_pairs": len(ranked),
    "n_strong_binders": n_strong,
    "n_weak_binders": n_weak,
    "construct_epitopes": len(chosen),
    "construct_length_aa": len(protein),
    "construct_length_nt": len(mrna),
    "has_construct": bool(chosen),
    "strong_rank_threshold": strong_r,
    "weak_rank_threshold": weak_r,
}
with open("qc_metrics.json", "w") as fh:
    json.dump(qc, fh, indent=2)

print(json.dumps({k: summary[k] for k in ("n_alleles", "n_ranked_neoepitope_allele_pairs",
      "n_strong_binders", "construct_epitopes", "status")}, indent=2))
PYEOF
    """
}

workflow NEOANTIGEN_VACCINE_DESIGN {
    take:
    ch_variants   // value channel: the variants JSON string
    ch_alleles    // channel: one class-I allele per element -> parallel binding

    main:
    ENUMERATE_NEOEPITOPES(ch_variants)

    // fan out: score the enumerated peptide set against EACH allele in parallel
    ch_allele_pep = ch_alleles.combine(ENUMERATE_NEOEPITOPES.out.peptides)
    PREDICT_BINDING(ch_allele_pep)

    RANK_AND_BUILD(
        ENUMERATE_NEOEPITOPES.out.neoepitopes,
        PREDICT_BINDING.out.predictions.map { allele, csv -> csv }.collect()
    )

    emit:
    neoepitopes = ENUMERATE_NEOEPITOPES.out.neoepitopes
    binding     = PREDICT_BINDING.out.predictions
    ranked      = RANK_AND_BUILD.out.ranked
    construct   = RANK_AND_BUILD.out.construct
    summary     = RANK_AND_BUILD.out.summary
    qc          = RANK_AND_BUILD.out.qc
    versions    = ENUMERATE_NEOEPITOPES.out.versions
}

// Entry workflow for standalone execution.
workflow {
    def variants_json = params.variants instanceof String
        ? params.variants
        : groovy.json.JsonOutput.toJson(params.variants)

    def alleles = params.alleles instanceof String
        ? new groovy.json.JsonSlurper().parseText(params.alleles)
        : params.alleles

    ch_variants = Channel.value(variants_json as String)
    ch_alleles  = Channel.fromList(alleles).map { a -> a as String }

    NEOANTIGEN_VACCINE_DESIGN(ch_variants, ch_alleles)

    NEOANTIGEN_VACCINE_DESIGN.out.summary.view { f -> "neoantigen vaccine design done: ${f}" }
}
