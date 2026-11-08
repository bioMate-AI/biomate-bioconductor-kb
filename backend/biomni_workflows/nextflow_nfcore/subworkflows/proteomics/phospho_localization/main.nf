#!/usr/bin/env nextflow
/*
 * proteomics/phospho_localization
 *
 * Phosphosite identification + site-localization scoring from MS/MS spectra.
 * This is the pipeline behind the cold-start ability
 * "Identify phosphorylation sites in my MS/MS spectra" (previously no PTM /
 * phospho-localization workflow existed — the request dead-ended).
 *
 * Pipeline Steps:
 * 1. COMET_SEARCH        -- MS/MS database search (Comet) with variable STY
 *                           phospho mod (+79.9663) -> peptide-spectrum matches (pepXML)
 * 2. LUCIPHOR_LOCALIZE   -- False-localization-rate (FLR) controlled phosphosite
 *                           localization scoring (LuciPHOr2) over the Comet PSMs
 * 3. SUMMARISE           -- Site table + aggregate QC JSON for the gate monitor
 *
 * Outputs:
 *   comet.pep.xml               -- Comet PSMs (variable phospho on S/T/Y)
 *   luciphor_results.tsv        -- Per-site localization scores + FLR
 *   phospho_sites.tsv           -- Confident phosphosites (FLR <= threshold)
 *   phospho_summary.json        -- Aggregate QC metrics for the gate monitor
 *
 * Real tools + real containers (per-process biocontainers, repo convention):
 *   comet-ms 2024011   quay.io/biocontainers/comet-ms:2024011--hb319eff_0
 *   luciphor2 2020     quay.io/biocontainers/luciphor2:2020_04_03--hdfd78af_1
 *
 * Honest-failure contract:
 *   Both engines are real and invoked directly; NO stub / synthetic PSMs.
 *   - A protein FASTA (--fasta) is REQUIRED by Comet. Missing it -> hard error
 *     before launch (no fake identifications are emitted).
 *   - If Comet returns zero PSMs, the workflow writes success:false to the
 *     summary and exits non-zero rather than fabricating sites.
 *
 * References:
 *   Comet:     Eng J.K. et al. Proteomics 2013, 13(1):22-24. doi:10.1002/pmic.201200439
 *   LuciPHOr2: Fermin D. et al. Bioinformatics 2015, 31(7):1141-1143.
 *              doi:10.1093/bioinformatics/btu788
 */

nextflow.enable.dsl = 2

// ============================================================================
// Parameters
// ============================================================================

params.input                = null          // MS/MS spectra file: mzML / mzXML (required)
params.fasta                = null          // Protein sequence DB FASTA (required by Comet)

// Search settings
params.enzyme               = 'trypsin'      // proteolytic enzyme
params.precursor_tol_ppm    = 10            // precursor mass tolerance (ppm)
params.fragment_bin_tol     = 0.02          // fragment_bin_tol (Da) — 0.02 for HCD/Orbitrap
params.phospho_residues     = 'STY'         // residues that may carry the phospho mod

// LuciPHOr2 localization
params.luciphor_flr         = 0.01          // target false-localization rate (FLR)
params.ms2_tol              = 0.02          // MS2 peak-matching tolerance (Da)

params.outdir               = './results/phospho_localization'
params.publish_dir_mode     = 'copy'
params.max_memory           = '32.GB'
params.max_cpus             = 8
params.max_time             = '24.h'

// ============================================================================
// Processes
// ============================================================================

process COMET_SEARCH {
    tag "${meta.id}"
    label 'process_medium'
    container 'quay.io/biocontainers/comet-ms:2024011--hb319eff_0'
    publishDir "${params.outdir}/comet", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(spectra)
    path fasta

    output:
    tuple val(meta), path("${meta.id}.pep.xml"), emit: pepxml
    path "comet.params",                          emit: params_used

    script:
    // Comet variable phospho mod: +79.966331 Da on the requested residues.
    """
    # Generate a default Comet params file, then patch the fields we control.
    comet -p
    mv comet.params.new comet.params

    python3 - <<'PY'
res   = "${params.phospho_residues}"
lines = []
with open("comet.params") as fh:
    for ln in fh:
        k = ln.split("=", 1)[0].strip()
        if   k == "database_name":            ln = "database_name = ${fasta}\\n"
        elif k == "peptide_mass_tolerance":   ln = "peptide_mass_tolerance = ${params.precursor_tol_ppm}\\n"
        elif k == "peptide_mass_units":       ln = "peptide_mass_units = 2\\n"        # 2 = ppm
        elif k == "fragment_bin_tol":         ln = "fragment_bin_tol = ${params.fragment_bin_tol}\\n"
        elif k == "output_pepxmlfile":        ln = "output_pepxmlfile = 1\\n"
        elif k == "variable_mod01":           ln = "variable_mod01 = 79.966331 %s 0 3 -1 0 0 0.0\\n" % res
        elif k == "decoy_search":             ln = "decoy_search = 1\\n"              # target-decoy for FDR/FLR
        lines.append(ln)
with open("comet.params", "w") as fh:
    fh.writelines(lines)
PY

    comet -Pcomet.params ${spectra}

    # Comet names the output after the input basename; normalise to meta.id.
    base=\$(basename ${spectra})
    out="\${base%.*}.pep.xml"
    if [ -f "\$out" ] && [ "\$out" != "${meta.id}.pep.xml" ]; then
        mv "\$out" "${meta.id}.pep.xml"
    fi
    """
}

process LUCIPHOR_LOCALIZE {
    tag "${meta.id}"
    label 'process_medium'
    container 'quay.io/biocontainers/luciphor2:2020_04_03--hdfd78af_1'
    publishDir "${params.outdir}", mode: params.publish_dir_mode

    input:
    tuple val(meta), path(pepxml), path(spectra)

    output:
    tuple val(meta), path("${meta.id}.luciphor_results.tsv"), emit: results
    tuple val(meta), path("${meta.id}.phospho_sites.tsv"),    emit: sites
    tuple val(meta), path("${meta.id}.phospho_summary.json"), emit: summary

    script:
    """
    # LuciPHOr2 config: score phospho (79.966331 on S/T/Y) at target FLR.
    cat > luciphor_input.txt <<CFG
    SPECTRUM_PATH = \$PWD
    SPECTRUM_SUFFIX = ${spectra.extension}
    INPUT_DATA = ${pepxml}
    INPUT_TYPE = 1
    ALGORITHM = 1
    TSV_HEADER = 1
    MS2_TOL = ${params.ms2_tol}
    MS2_TOL_UNITS = 0
    MIN_NUM_PSMS_MODEL = 50
    TARGET_MOD = S 79.966331
    TARGET_MOD = T 79.966331
    TARGET_MOD = Y 79.966331
    VAR_MOD = M 15.994915
    DECOY_MASS = 79.966331
    MAX_CHARGE_STATE = 5
    MAX_PEP_LEN = 40
    NUM_THREADS = ${task.cpus}
    OUTPUT_FILE = ${meta.id}.luciphor_results.tsv
    CFG

    # LuciPHOr2 is distributed as a jar in the biocontainer.
    luciphor2 luciphor_input.txt || java -jar \$(command -v luciphor2 || echo /usr/local/share/luciphor2*/luciphor2.jar) luciphor_input.txt

    python3 - "${meta.id}" "${params.luciphor_flr}" <<'PY'
import csv, json, sys
sample, flr_thr = sys.argv[1], float(sys.argv[2])
res_file = sample + ".luciphor_results.tsv"

rows = []
try:
    with open(res_file, newline="") as fh:
        rdr = csv.DictReader(fh, delimiter="\\t")
        for r in rdr:
            rows.append(r)
except FileNotFoundError:
    rows = []

# LuciPHOr2 emits a globalFLR / localFLR column; keep sites at or below threshold.
def flr_of(r):
    for k in ("globalFLR", "globalFDR", "localFLR"):
        if k in r and r[k] not in ("", None):
            try: return float(r[k])
            except ValueError: pass
    return 1.0

confident = [r for r in rows if flr_of(r) <= flr_thr]

if rows:
    with open(sample + ".phospho_sites.tsv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=rows[0].keys(), delimiter="\\t")
        w.writeheader(); w.writerows(confident)
else:
    open(sample + ".phospho_sites.tsv", "w").write("")

summ = {
    "success": bool(rows),
    "sample": sample,
    "n_localized_psms": len(rows),
    "n_confident_sites": len(confident),
    "flr_threshold": flr_thr,
}
json.dump(summ, open(sample + ".phospho_summary.json", "w"), indent=2)
if not rows:
    sys.stderr.write("phospho_localization: LuciPHOr2 produced no localized PSMs — "
                     "check that Comet returned phospho-modified PSMs.\\n")
    sys.exit(1)
PY
    """
}

// ============================================================================
// Workflow
// ============================================================================

workflow PHOSPHO_LOCALIZATION_WORKFLOW {
    take:
    ch_spectra   // channel: [ meta, spectra ]
    fasta        // path

    main:
    COMET_SEARCH(ch_spectra, fasta)
    // Re-pair each pepXML with its originating spectra file for LuciPHOr2.
    ch_loc = COMET_SEARCH.out.pepxml.join(ch_spectra)
    LUCIPHOR_LOCALIZE(ch_loc)

    emit:
    results = LUCIPHOR_LOCALIZE.out.results
    sites   = LUCIPHOR_LOCALIZE.out.sites
    summary = LUCIPHOR_LOCALIZE.out.summary
}

workflow {
    if (!params.input) error "Please provide --input <MS/MS spectra: mzML/mzXML>"
    if (!params.fasta) error "phospho_localization requires --fasta <protein sequence DB> for the Comet search"

    def fasta = file(params.fasta)

    Channel.fromPath(params.input)
        .map { f -> [ [id: f.baseName], f ] }
        .set { ch_spectra }

    PHOSPHO_LOCALIZATION_WORKFLOW(ch_spectra, fasta)
    PHOSPHO_LOCALIZATION_WORKFLOW.out.summary.view { "Phospho summary: $it" }
}
