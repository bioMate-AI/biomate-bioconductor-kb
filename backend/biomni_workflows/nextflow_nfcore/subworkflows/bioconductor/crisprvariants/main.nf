#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CrispRVariants
// CrispRVariants provides tools for analysing the results of a CRISPR-Cas9 mutagenesis sequencing expe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CrispRVariants/inst/doc/user_guide.R
// Upstream  : Biostrings, GenomicFeatures, IRanges, Rsamtools, gridExtra
// Downstream: none
//
// Install: BiocManager::install("CrispRVariants")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRVARIANTS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-crisprvariants"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-crisprvariants:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-crisprvariants:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_crisprvariants_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_crisprvariants_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_crisprvariants_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CrispRVariants)
    library(jsonlite)

    # --- plot Variants [] ---
    # Key functions: plotVariants, mutationEfficiency, consensusSeqs, reverseComplement
    p <- plotVariants(crispr_set, txdb = txdb, gene.text.size = 8,
    row.ht.ratio = c(1,8), col.wdth.ratio = c(4,2),
    plotAlignments.args = list(line.weight = 0.5, ins.size = 2,
    # --- plot Freq Heatmap [] ---
    # Key functions: plotFreqHeatmap
    p <- plotFreqHeatmap(gol, top.n = 3)
    p + labs(title = "A. plotFreqHeatmap with default options")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_crisprvariants_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_crisprvariants_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_crisprvariants_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CRISPRVARIANTS:", paste0("    crisprvariants: ", packageVersion("CrispRVariants"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_crisprvariants_results.csv
    touch ${prefix}_crisprvariants_output.rds
    echo "BIOC_CRISPRVARIANTS:" > versions.yml
    echo "    crisprvariants: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CRISPRVARIANTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CRISPRVARIANTS(ch_input)

    emit:
    results  = BIOC_CRISPRVARIANTS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CRISPRVARIANTS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CRISPRVARIANTS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CRISPRVARIANTS.out.versions  // channel: path(versions.yml)
}
