// ============================================================
// SAGE — fast fragment-indexed DDA peptide-spectrum-match search
//
// Sage (Lazear, J Proteome Res 2023; https://github.com/lazear/sage) is a
// clean-room Rust reimplementation of MSFragger's fragment-ion indexing:
//   multi-level index (fragment mass -> precursor mass) that skips any candidate
//   sharing no fragments -> ~2,500 PSMs/CPU-sec, blazing narrow AND open search.
//
// License: MIT (Sage) — clean for BioMate commercial hosting (the survey's
//   license-clean fast engine; NO MSFragger which is academic-license only).
// Container: quay.io/biocontainers/sage-proteomics (Bioconda, public, no Docker
//   Hub rate limit; same pattern as the OpenMS modules).
//
// I/O contract (matches proteomics_db_search's engine seam):
//   in : (meta, mzml, fasta)  — fasta already target+decoy (DecoyDatabase upstream)
//   out: (meta, results.sage.tsv)  — the PSM table (one row per PSM)
//        (meta, results.sage.pin)  — Percolator/mokapot input (rescoring feature matrix)
//
// Sage writes its own config JSON; we template it from ext.args-style params so
// enzyme/mods/tolerances match the Comet arm EXACTLY (fair-comparison control).
// The decoy prefix is 'DECOY_' to match OPENMS_DECOYDATABASE (-decoy_string DECOY_).
// Design: docs/20260907_PROTEOMICS_DB_SEARCH_OPTIMIZATION_SURVEY.md §12 Wave 1 [L1]
// ============================================================
process SAGE {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/sage-proteomics:0.14.7--h031d066_0' :
        'quay.io/biocontainers/sage-proteomics:0.14.7--h031d066_0' }"

    input:
    tuple val(meta), path(mzml), path(fasta)

    output:
    tuple val(meta), path("${meta.id}.sage.tsv"), emit: psms
    tuple val(meta), path("${meta.id}.sage.pin"), emit: pin
    path "versions.yml"                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // Search settings mirror proteomics_dda_search/nextflow.config so every engine
    // searches identically. Sage takes ppm tolerances as [-x, +x]; fragment tol here
    // is given in Da in the config to match Comet's fragment_tolerance_da when set,
    // else default to a symmetric ppm window via params.
    def prec_ppm  = task.ext.precursor_tolerance_ppm ?: 10
    def frag_da   = task.ext.fragment_tolerance_da   ?: 0.02
    def missed    = task.ext.missed_cleavages        ?: 2
    // variable mods: Sage uses residue -> [mass] maps. Oxidation(M)=+15.9949; carbamidomethyl(C)=+57.0215 (fixed as static_mods).
    """
    cat > sage_config.json <<'JSON'
    {
      "database": {
        "bucket_size": 8192,
        "enzyme": { "missed_cleavages": ${missed}, "min_len": 6, "max_len": 50, "cleave_at": "KR", "restrict": "P" },
        "fragment_min_mz": 150.0,
        "fragment_max_mz": 2000.0,
        "peptide_min_mass": 500.0,
        "peptide_max_mass": 5000.0,
        "ion_kinds": ["b", "y"],
        "min_ion_index": 2,
        "static_mods": { "C": 57.0215 },
        "variable_mods": { "M": [15.9949] },
        "max_variable_mods": 2,
        "decoy_tag": "DECOY_",
        "generate_decoys": false,
        "fasta": "${fasta}"
      },
      "precursor_tol": { "ppm": [-${prec_ppm}, ${prec_ppm}] },
      "fragment_tol":  { "da": [-${frag_da}, ${frag_da}] },
      "isotope_errors": [-1, 3],
      "deisotope": false,
      "chimera": false,
      "predict_rt": true,
      "min_peaks": 15,
      "max_peaks": 150,
      "report_psms": 1,
      "output_directory": "."
    }
    JSON

    sage sage_config.json -f ${fasta} --write-pin -o . ${mzml}

    # Sage names outputs results.sage.tsv / results.sage.pin; rename to per-run ids.
    mv results.sage.tsv ${meta.id}.sage.tsv
    mv results.sage.pin ${meta.id}.sage.pin

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sage: \$(sage --version 2>&1 | sed 's/sage //g' | head -1)
    END_VERSIONS
    """

    stub:
    """
    printf 'psm_id\\tpeptide\\tproteins\\tscannr\\tsage_discriminant_score\\tspectrum_q\\tlabel\\n1\\tPEPTIDEK\\tsp|P1|A\\tscan=1\\t1.5\\t0.001\\t1\\n' > ${meta.id}.sage.tsv
    printf 'SpecId\\tLabel\\tScanNr\\tPeptide\\tProteins\\n1\\t1\\t1\\t-.PEPTIDEK.-\\tsp|P1|A\\n' > ${meta.id}.sage.pin
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sage: stub
    END_VERSIONS
    """
}
