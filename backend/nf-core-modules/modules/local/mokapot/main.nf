// ============================================================
// MOKAPOT — semi-supervised rescoring (Percolator reimplementation, Python)
//
// Mokapot (Fondrie & Noble, J Proteome Res 2021; https://github.com/wfondrie/mokapot)
// trains a semi-supervised model (à la Percolator) on the engine's PSM feature matrix
// (a Percolator-input ".pin" file) to sharpen the target/decoy boundary, then assigns
// calibrated q-values. This is the survey's RECALL lever — a "free" sensitivity boost
// that adds no new spectra, just better discrimination (§4, §12 Wave 2).
//
// License: Apache-2.0 (mokapot) — clean for BioMate commercial hosting.
// Container: quay.io/biocontainers/mokapot (Bioconda, public).
//
// I/O contract:
//   in : (meta, pin)  — a Percolator-input feature matrix (Sage --write-pin, or a
//                        Comet/OpenMS-emitted pin). Decoys flagged by Label=-1.
//   out: (meta, *.mokapot.psms.txt)      — PSMs with mokapot q-values
//        (meta, *.mokapot.peptides.txt)  — peptide-level q-values
//
// The rescoring=mokapot toggle in proteomics_db_search routes each engine's pin
// through here; rescoring=none skips it (q-values then come from target-decoy on the
// raw score in the downstream scorer).
// Design: docs/20260907_PROTEOMICS_DB_SEARCH_OPTIMIZATION_SURVEY.md §4, §12 [L2,L4]
// ============================================================
process MOKAPOT {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    // Combined image (OpenMS+Sage+Mokapot) when set — required so the multi-engine
    // proteomics_dda_search runs as ONE forced container under BioMate's executor.
    // Falls back to the per-tool Mokapot biocontainer for standalone Nextflow runs.
    container "${
        ( workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/mokapot:0.10.0--pyhdfd78af_0' :
        'quay.io/biocontainers/mokapot:0.10.0--pyhdfd78af_0' ) }"

    input:
    tuple val(meta), path(pin)

    output:
    tuple val(meta), path("${meta.id}.mokapot.psms.txt")    , emit: psms
    tuple val(meta), path("${meta.id}.mokapot.peptides.txt"), emit: peptides
    path "versions.yml"                                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def test_fdr = task.ext.test_fdr ?: 0.01
    """
    mokapot \\
        --dest_dir . \\
        --file_root ${meta.id} \\
        --test_fdr ${test_fdr} \\
        --seed 42 \\
        ${pin}

    # mokapot emits <root>.mokapot.psms.txt / <root>.mokapot.peptides.txt
    # (already correctly named by --file_root); guard the target-only default filenames.
    [ -f ${meta.id}.mokapot.psms.txt ]     || mv *mokapot.psms.txt     ${meta.id}.mokapot.psms.txt
    [ -f ${meta.id}.mokapot.peptides.txt ] || mv *mokapot.peptides.txt ${meta.id}.mokapot.peptides.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mokapot: \$(python -c "import mokapot; print(mokapot.__version__)")
    END_VERSIONS
    """

    stub:
    """
    printf 'PSMId\\tpeptide\\tmokapot q-value\\tmokapot PEP\\tProteins\\n1\\tPEPTIDEK\\t0.001\\t0.0005\\tsp|P1|A\\n' > ${meta.id}.mokapot.psms.txt
    printf 'PSMId\\tpeptide\\tmokapot q-value\\tmokapot PEP\\tProteins\\n1\\tPEPTIDEK\\t0.001\\t0.0005\\tsp|P1|A\\n' > ${meta.id}.mokapot.peptides.txt
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mokapot: stub
    END_VERSIONS
    """
}
