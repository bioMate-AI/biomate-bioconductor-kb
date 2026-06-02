#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sangerseqR
// This package contains several tools for analyzing Sanger Sequencing data files in R, including readi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sangerseqR/inst/doc/sangerseqRWalkthrough.R
// Upstream  : none
// Downstream: sangeranalyseR
//
// Install: BiocManager::install("sangerseqR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SANGERSEQR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sangerseqr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sangerseqr:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sangerseqr:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sangerseqr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sangerseqr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sangerseqr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sangerseqR)
    library(jsonlite)

    # --- Base Calling [] ---
    # Key functions: makeBaseCalls, primarySeq, secondarySeq
    het_calls <- makeBaseCalls(het_sanger, ratio=0.33)
    p_seq <- primarySeq(het_calls, string=TRUE)
    s_seq <- secondarySeq(het_calls, string=TRUE)


    # --- Chromatogram Visualisation [] ---
    # Key functions: chromatogram
    chromatogram(het_sanger, width=80, height=3, trim5=50, trim3=100,
                 showcalls="both")
    chromatogram(het_calls, width=80, height=3, trim5=50, trim3=100,
                 showcalls="both")


    # --- Allele Phasing [] ---
    # Key functions: setAllelePhase, primarySeq
    ref_seq <- Biostrings::subseq(primarySeq(homo_sanger, string=TRUE),
                                  start=30, width=500)
    het_alleles <- setAllelePhase(het_calls, ref_seq, trim5=50, trim3=300)


    # --- Sequence Alignment [] ---
    # Key functions: primarySeq, secondarySeq
    pa <- Biostrings::pairwiseAlignment(
        primarySeq(het_alleles)[1:400],
        secondarySeq(het_alleles)[1:400],
        type="global-local"
    )
    Biostrings::writePairwiseAlignments(pa)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sangerseqr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sangerseqr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sangerseqr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SANGERSEQR:", paste0("    sangerseqr: ", packageVersion("sangerseqR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sangerseqr_results.csv
    touch ${prefix}_sangerseqr_output.rds
    echo "BIOC_SANGERSEQR:" > versions.yml
    echo "    sangerseqr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SANGERSEQR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SANGERSEQR(ch_input)

    emit:
    results  = BIOC_SANGERSEQR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SANGERSEQR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SANGERSEQR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SANGERSEQR.out.versions  // channel: path(versions.yml)
}
