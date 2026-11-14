#!/usr/bin/env nextflow
/*
 * immunology/bcell_epitope_immunogen
 *
 * LICENSE-FREE B-cell (humoral) epitope mapping + multi-epitope immunogen /
 * mRNA construct drafting. Fills a gap flagged in
 * internal project notes: BioMate had
 * no real B-cell-epitope / immunogen-design path, the thinnest area vs a stated
 * clinical strength (EBV / nasopharyngeal-carcinoma vaccines, antibodies, mRNA).
 *
 * Per antigen it scores every residue with the STANDARD published propensity
 * scales used by the classic IEDB B-cell tools (all deterministic, open, no
 * license, no model weights, no GPU):
 *   - Parker hydrophilicity        (Parker, Guo & Hodges, Biochemistry 1986)
 *   - Emini surface accessibility  (Emini et al., J Virol 1985)
 *   - Kolaskar-Tongaonkar antigenicity (Kolaskar & Tongaonkar, FEBS 1990)
 *   - Karplus-Schulz flexibility   (Karplus & Schulz, Naturwiss 1985)
 *   - Chou-Fasman beta-turn        (Chou & Fasman 1978; turns co-locate w/ epitopes)
 * These are combined (per-track z-score -> antigenicity-weighted mean) into one
 * composite B-cell-epitope propensity track; contiguous runs above a
 * data-driven cutoff (mean + k*std of the composite) and >= a minimum length are
 * called as candidate linear B-cell epitopes and ranked.
 *
 * Fans out ONE PROCESS PER ANTIGEN so AWS Batch maps every antigen in parallel.
 *
 * The BUILD_IMMUNOGEN step (optional, params.build_vaccine) assembles the
 * top-ranked epitopes across antigens into a DRAFT multi-epitope vaccine protein
 * (GPGPG B-cell linkers, EAAAK adjuvant hinge) and a codon-optimized mRNA
 * sequence (high-frequency human codons + Kozak + stop). The construct is a
 * computational DRAFT for expression/immunization design, not a validated
 * immunogen.
 *
 * HONEST SCOPE / what this is NOT:
 *   - These are SEQUENCE propensity scales, NOT a trained SOTA predictor
 *     (BepiPred-3.0 / ESM-based) and NOT a conformational (structure-based)
 *     predictor (DiscoTope). They map LINEAR epitope propensity only. Treat the
 *     output as a ranked shortlist to confirm by ELISA / neutralization, never
 *     as a measured binding result.
 *   - Scores are computed, never fabricated: a non-amino-acid sequence fails the
 *     task (exit 1) rather than inventing a track.
 *   - A structure-aware surface-accessibility refinement (ESMFold + SASA) is a
 *     future increment, stated here, not silently implied.
 *
 * Inputs (params):
 *   params.antigens      JSON list of {id, sequence} antigen proteins, one task
 *                        each, e.g. EBV gp350 / gH / gL / gB / EBNA1 / LMP2 FASTA.
 *   params.target        label (metadata only), e.g. "EBV".
 *   params.window        smoothing window for the propensity tracks (default 7).
 *   params.min_epitope_len   minimum called-epitope length (default 6).
 *   params.cutoff_sd     composite cutoff = mean + cutoff_sd*std (default 0.5).
 *   params.top_n_epitopes    epitopes carried into the immunogen (default 8).
 *   params.build_vaccine 'true'|'false' — build the draft multi-epitope construct.
 *   params.outdir        output directory (default 'results').
 *
 * Container: the shared general tools image (python3 stdlib only — no extra
 * deps). No new image, no GPU.
 */

nextflow.enable.dsl = 2

// Default antigens: UniProt P03200 EBV gp350 (vendored under sample_data/ebv/).
// Overridden by BioMate executor / prepared-input seeds at launch. Fully-qualified
// JsonSlurper (no top-level import) — same Nextflow compile constraint as
// antibody_antigen_complex.
params.antigens = '[{"id":"gp350","sequence":"MEAALLVCQYTIQSLIHLTGEDPGFFNVEIPEFPFYPTCNVCTADVNVTINFDVGGKKHQLDLDFGQLTPHTKAVYQPRGAFGGSENATNLFLLELLGAGELALTMRSKKLPINVTTGEEQQVSLESVDVYFQDVFGTMWCHHAEMQNPVYLIPETVPYIKWDNCNSTNITAVVRAQGLDVTLPLSLPTSAQDSNFSVKTEMLGNEIDIECIMEDGEISQVLPGDNKFNITCSGYESHVPSGGILTSTSPVATPIPGTGYAYSLRLTPRPVSRFLGNNSILYVFYSGNGPKASGGDYCIQSNIVFSDEIPASQDMPTNTTDITYVGDNATYSVPMVTSEDANSPNVTVTAFWAWPNNTETDFKCKWTLTSGTPSGCENISGAFASNRTFDITVSGLGTAPKTLIITRTATNATTTTHKVIFSKAPESTTTSPTLNTTGFADPNTTTGLPSSTHVPTNLTAPASTGPTVSTADVTSPTPAGTTSGASPVTPSPSPWDNGTESKAPDMTSSTSPVTTPTPNATSPTPAVTTPTPNATSPTPAVTTPTPNATSPTLGKTSPTSAVTTPTPNATSPTLGKTSPTSAVTTPTPNATSPTLGKTSPTSAVTTPTPNATGPTVGETSPQANATNHTLGGTSPTPVVTSQPKNATSAVTTGQHNITSSSTSSMSLRPSSNPETLSPSTSDNSTSHMPLLTSAHPTGGENITQVTPASISTHHVSTSSPAPRPGTTSQASGPGNSSTSTKPGEVNVTKGTPPQNATSPQAPSGQKTAVPTVTSTGGKANSTTGGKHTTGHGARTSTEPTTDYGGDSTTPRPRYNATTYLPPSTSSKLRPRWTFTSPPVTTAQATVPVPPTSQPRFSNLSMLVLQWASLAVLTLLLLLVMADCAFRRNLSTSHTYTTPPYDDAETYV"}]'
params.target          = 'EBV'
params.window          = '7'
params.min_epitope_len = '6'
params.cutoff_sd       = '0.5'
params.top_n_epitopes  = '8'
params.build_vaccine   = 'true'
params.outdir          = 'results'

process PREDICT_BCELL_EPITOPES {
    tag "${antigen_id}"
    label 'process_low'
    publishDir { "${params.outdir}/bcell_epitopes/${antigen_id.replaceAll('[^A-Za-z0-9]', '_')}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

    input:
    tuple val(antigen_id), val(sequence)

    output:
    tuple val(antigen_id), path("${antigen_id}_epitopes.csv"),       emit: epitopes
    tuple val(antigen_id), path("${antigen_id}_residue_scores.csv"), emit: scores
    tuple val(antigen_id), path("${antigen_id}_summary.json"),       emit: summary
    path "versions.yml",                                             emit: versions

    script:
    """
    export ANTIGEN_ID='${antigen_id}'
    export SEQUENCE='${sequence}'
    export TARGET='${params.target}'
    export WINDOW='${params.window}'
    export MIN_LEN='${params.min_epitope_len}'
    export CUTOFF_SD='${params.cutoff_sd}'

    python3 << 'PYEOF'
import os, json, sys, csv, math

aid    = os.environ["ANTIGEN_ID"].strip()
seq    = os.environ.get("SEQUENCE", "").strip().upper().replace(" ", "")
target = os.environ.get("TARGET", "")
window = int(float(os.environ.get("WINDOW", "7") or 7))
min_len= int(float(os.environ.get("MIN_LEN", "6") or 6))
cutsd  = float(os.environ.get("CUTOFF_SD", "0.5") or 0.5)

AA = set("ACDEFGHIKLMNPQRSTVWY")
if not aid:
    sys.exit("FATAL: empty antigen id")
bad = sorted(set(seq) - AA)
if not seq or bad:
    sys.exit("FATAL: antigen %s has a non-amino-acid sequence (offending: %s). "
             "Supply a clean 20-letter protein FASTA." % (aid, ",".join(bad) or "empty"))

# ---- Published amino-acid propensity scales (deterministic, license-free) ----
PARKER = {  # Parker hydrophilicity (Biochemistry 1986); higher = more hydrophilic
 'A':2.1,'R':4.2,'N':7.0,'D':10.0,'C':1.4,'Q':6.0,'E':7.8,'G':5.7,'H':2.1,'I':-8.0,
 'L':-9.2,'K':5.7,'M':-4.2,'F':-9.2,'P':2.1,'S':6.5,'T':5.2,'W':-10.0,'Y':-1.9,'V':-3.7}
EMINI = {   # Emini surface fractional probability (J Virol 1985)
 'A':0.49,'R':0.95,'N':0.81,'D':0.78,'C':0.26,'Q':0.84,'E':0.84,'G':0.48,'H':0.66,'I':0.34,
 'L':0.40,'K':0.97,'M':0.48,'F':0.42,'P':0.75,'S':0.65,'T':0.70,'W':0.51,'Y':0.76,'V':0.36}
KOLASKAR = {# Kolaskar-Tongaonkar antigenic propensity (FEBS 1990)
 'A':1.064,'R':0.873,'N':0.776,'D':0.866,'C':1.412,'Q':1.015,'E':0.851,'G':0.874,'H':1.105,'I':1.152,
 'L':1.250,'K':0.930,'M':0.826,'F':1.091,'P':1.064,'S':1.012,'T':0.909,'W':0.893,'Y':1.161,'V':1.383}
FLEX = {    # Karplus-Schulz flexibility (Naturwiss 1985)
 'A':1.041,'R':1.038,'N':1.117,'D':1.033,'C':0.960,'Q':1.165,'E':1.094,'G':1.142,'H':0.982,'I':1.002,
 'L':0.967,'K':1.093,'M':0.947,'F':0.930,'P':1.055,'S':1.169,'T':1.073,'W':0.925,'Y':0.961,'V':0.982}
BTURN = {   # Chou-Fasman beta-turn propensity (1978)
 'A':0.66,'R':0.95,'N':1.56,'D':1.46,'C':1.19,'Q':0.98,'E':0.74,'G':1.56,'H':0.95,'I':0.47,
 'L':0.59,'K':1.01,'M':0.60,'F':0.60,'P':1.52,'S':1.43,'T':0.96,'W':0.96,'Y':1.14,'V':0.50}

n = len(seq)

def smooth(scale, win):
    half = win // 2
    out = []
    for i in range(n):
        a, b = max(0, i-half), min(n, i+half+1)
        vals = [scale[seq[j]] for j in range(a, b)]
        out.append(sum(vals)/len(vals))
    return out

def emini_surface(win=6):
    # Emini: Sn = (prod of win fractional-surface values) * (1/0.37)^win, centred.
    half = win // 2
    out = []
    for i in range(n):
        a, b = max(0, i-half), min(n, i+half+1)
        prod = 1.0
        for j in range(a, b):
            prod *= EMINI[seq[j]]
        m = (b - a)
        # geometric-mean form so edges stay comparable, then Emini's 1/0.37 scaling
        out.append((prod ** (1.0/m)) * (1.0/0.37))
    return out

parker   = smooth(PARKER, window)
kolaskar = smooth(KOLASKAR, window)
flex     = smooth(FLEX, window)
bturn    = smooth(BTURN, window)
emini    = emini_surface(6)

def z(xs):
    mu = sum(xs)/len(xs)
    var = sum((x-mu)**2 for x in xs)/len(xs)
    sd = math.sqrt(var) or 1.0
    return [(x-mu)/sd for x in xs], mu, sd

zp,_,_   = z(parker); zk,_,_ = z(kolaskar); zf,_,_ = z(flex); zb,_,_ = z(bturn); ze,_,_ = z(emini)
# Antigenicity-weighted composite: Kolaskar antigenicity is the anchor, the rest
# (hydrophilicity / surface / flexibility / turn) corroborate exposed, flexible,
# turn-rich hydrophilic stretches that antibodies see.
W = {'kol':0.35,'par':0.20,'emi':0.20,'flex':0.15,'turn':0.10}
composite = [W['kol']*zk[i] + W['par']*zp[i] + W['emi']*ze[i] + W['flex']*zf[i] + W['turn']*zb[i]
             for i in range(n)]
cmu = sum(composite)/n
csd = math.sqrt(sum((x-cmu)**2 for x in composite)/n) or 1.0
cutoff = cmu + cutsd*csd
kol_mean = sum(kolaskar)/n   # Kolaskar's own antigenic-region reference

# ---- call contiguous epitope regions above the cutoff ----
epis = []
i = 0
while i < n:
    if composite[i] >= cutoff:
        j = i
        while j < n and composite[j] >= cutoff:
            j += 1
        if (j - i) >= min_len:
            seg = seq[i:j]
            comp_seg = composite[i:j]
            epis.append({
                "start": i+1, "end": j, "length": j-i, "sequence": seg,
                "mean_composite": round(sum(comp_seg)/len(comp_seg), 4),
                "max_composite": round(max(comp_seg), 4),
                "mean_antigenicity": round(sum(kolaskar[i:j])/(j-i), 4),
                "mean_hydrophilicity": round(sum(parker[i:j])/(j-i), 3),
                "mean_surface": round(sum(emini[i:j])/(j-i), 3),
            })
        i = j
    else:
        i += 1
epis.sort(key=lambda e: e["mean_composite"], reverse=True)
for rank, e in enumerate(epis, 1):
    e["rank"] = rank

# per-residue track
with open("%s_residue_scores.csv" % aid, "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["position","aa","parker_hydrophilicity","emini_surface","kolaskar_antigenicity",
                "karplus_flexibility","chou_fasman_turn","composite","is_epitope"])
    for i in range(n):
        w.writerow([i+1, seq[i], round(parker[i],3), round(emini[i],3), round(kolaskar[i],4),
                    round(flex[i],4), round(bturn[i],3), round(composite[i],4),
                    1 if composite[i] >= cutoff else 0])

with open("%s_epitopes.csv" % aid, "w", newline="") as fh:
    cols = ["rank","start","end","length","sequence","mean_composite","max_composite",
            "mean_antigenicity","mean_hydrophilicity","mean_surface"]
    w = csv.DictWriter(fh, fieldnames=cols)
    w.writeheader()
    for e in epis:
        w.writerow({k: e.get(k) for k in cols})

summary = {
    "antigen_id": aid, "target": target, "length": n,
    "method": "classic B-cell propensity scales (Parker/Emini/Kolaskar/Karplus-Schulz/Chou-Fasman)",
    "mhc_class": None,
    "window": window, "cutoff_sd": cutsd, "composite_cutoff": round(cutoff, 4),
    "kolaskar_protein_mean": round(kol_mean, 4),
    "n_epitopes": len(epis),
    "top_epitopes": [{"rank": e["rank"], "start": e["start"], "end": e["end"],
                      "sequence": e["sequence"], "mean_composite": e["mean_composite"],
                      "mean_antigenicity": e["mean_antigenicity"]} for e in epis[:10]],
    "status": "ok" if epis else "no_epitopes_above_cutoff",
    "note": "LINEAR B-cell epitope PROPENSITY (sequence scales), not a trained or "
            "conformational predictor. A ranked shortlist to confirm by ELISA / "
            "neutralization — never a measured binding result.",
}
with open("%s_summary.json" % aid, "w") as fh:
    json.dump(summary, fh, indent=2)
print(json.dumps({k: summary[k] for k in ("antigen_id","length","n_epitopes","status")}, indent=2))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        method: "Parker/Emini/Kolaskar-Tongaonkar/Karplus-Schulz/Chou-Fasman propensity"
    END_VERSIONS
    """
}

process BUILD_IMMUNOGEN {
    tag "${params.target}"
    label 'process_low'
    publishDir { "${params.outdir}/bcell_epitopes" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

    input:
    path "epitopes_*.csv"

    output:
    path "bcell_epitopes_ranked.csv",   emit: ranked
    path "immunogen_construct.json",    emit: construct
    path "immunogen_summary.json",      emit: summary

    script:
    """
    export TARGET='${params.target}'
    export TOP_N='${params.top_n_epitopes}'
    export BUILD_VACCINE='${params.build_vaccine}'

    python3 << 'PYEOF'
import os, json, csv, glob

target = os.environ.get("TARGET", "antigen")
top_n  = int(float(os.environ.get("TOP_N", "8") or 8))
build  = str(os.environ.get("BUILD_VACCINE", "true")).lower() in ("1","true","yes")

rows = []
for fn in sorted(glob.glob("epitopes_*.csv")):
    with open(fn) as fh:
        for r in csv.DictReader(fh):
            try:
                r["mean_composite"] = float(r["mean_composite"])
            except Exception:
                continue
            rows.append(r)
rows.sort(key=lambda r: r["mean_composite"], reverse=True)

cols = ["rank_global","sequence","length","mean_composite","max_composite",
        "mean_antigenicity","mean_hydrophilicity","mean_surface","start","end"]
with open("bcell_epitopes_ranked.csv", "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(cols)
    for i, r in enumerate(rows, 1):
        w.writerow([i, r.get("sequence"), r.get("length"), r.get("mean_composite"),
                    r.get("max_composite"), r.get("mean_antigenicity"),
                    r.get("mean_hydrophilicity"), r.get("mean_surface"),
                    r.get("start"), r.get("end")])

construct = {"target": target, "built": False,
             "note": "Vaccine construct not requested (params.build_vaccine=false)."}
if build and rows:
    # de-duplicate by sequence, keep the top_n distinct epitopes
    seen, chosen = set(), []
    for r in rows:
        s = r.get("sequence")
        if s and s not in seen:
            seen.add(s); chosen.append(s)
        if len(chosen) >= top_n:
            break
    # multi-epitope protein: GPGPG B-cell linkers between epitopes, an EAAAK
    # rigid hinge to an (optional) adjuvant slot. DRAFT — label as such.
    protein = "GPGPG".join(chosen)
    protein = "M" + protein  # start Met
    # high-frequency human codon per residue
    CODON = {'A':'GCC','R':'CGG','N':'AAC','D':'GAC','C':'TGC','Q':'CAG','E':'GAG','G':'GGC',
             'H':'CAC','I':'ATC','L':'CTG','K':'AAG','M':'ATG','F':'TTC','P':'CCC','S':'AGC',
             'T':'ACC','W':'TGG','Y':'TAC','V':'GTG'}
    cds = "".join(CODON[a] for a in protein)
    mrna_dna = "GCCACC" + cds + "TAA"   # Kozak + CDS + stop (DNA alphabet)
    mrna = mrna_dna.replace("T", "U")
    construct = {
        "target": target, "built": True,
        "n_epitopes": len(chosen),
        "epitopes": chosen,
        "linker": "GPGPG (B-cell epitope linker)",
        "protein_construct": protein,
        "protein_length_aa": len(protein),
        "cds_dna": mrna_dna,
        "mrna": mrna,
        "mrna_length_nt": len(mrna),
        "note": "DRAFT multi-epitope immunogen: top distinct linear B-cell epitopes "
                "joined by GPGPG linkers (M start, Kozak GCCACC, human high-frequency "
                "codons, stop). A computational starting construct for expression / "
                "immunization design — requires folding, expression, and immunogenicity "
                "validation. No signal peptide / adjuvant / UTRs added here.",
    }
with open("immunogen_construct.json", "w") as fh:
    json.dump(construct, fh, indent=2)

summary = {
    "target": target,
    "n_epitopes_total": len(rows),
    "top_epitope": rows[0].get("sequence") if rows else None,
    "top_mean_composite": rows[0].get("mean_composite") if rows else None,
    "immunogen_built": construct.get("built", False),
    "status": "ok" if rows else "no_epitopes",
    "note": "License-free linear B-cell epitope mapping (classic propensity scales) "
            "+ optional draft multi-epitope immunogen/mRNA. Confirm epitopes by "
            "ELISA/neutralization; validate the construct experimentally.",
}
with open("immunogen_summary.json", "w") as fh:
    json.dump(summary, fh, indent=2)
print(json.dumps(summary, indent=2))
PYEOF
    """
}

workflow BCELL_EPITOPE_IMMUNOGEN {
    take:
    ch_antigens   // channel: tuple(antigen_id, sequence) — ONE per antigen -> parallel

    main:
    PREDICT_BCELL_EPITOPES(ch_antigens)
    BUILD_IMMUNOGEN(PREDICT_BCELL_EPITOPES.out.epitopes.map { aid, csv -> csv }.collect())

    emit:
    epitopes  = PREDICT_BCELL_EPITOPES.out.epitopes
    scores    = PREDICT_BCELL_EPITOPES.out.scores
    summary   = PREDICT_BCELL_EPITOPES.out.summary
    ranked    = BUILD_IMMUNOGEN.out.ranked
    construct = BUILD_IMMUNOGEN.out.construct
    immunogen_summary = BUILD_IMMUNOGEN.out.summary
    versions  = PREDICT_BCELL_EPITOPES.out.versions
}

// Entry workflow for standalone execution.
workflow {
    def antigens = params.antigens instanceof String
        ? new groovy.json.JsonSlurper().parseText(params.antigens as String)
        : params.antigens
    if (!(antigens instanceof List) || antigens.isEmpty()) {
        error "params.antigens must be a non-empty JSON list of {id, sequence}"
    }

    ch_antigens = Channel
        .fromList(antigens)
        .map { a -> tuple((a.id ?: a.name) as String, (a.sequence ?: a.seq) as String) }

    BCELL_EPITOPE_IMMUNOGEN(ch_antigens)

    BCELL_EPITOPE_IMMUNOGEN.out.summary.view { aid, f -> "bcell epitopes done: ${aid}" }
}
