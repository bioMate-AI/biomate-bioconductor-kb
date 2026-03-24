#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HMMcopy
// Corrects GC and mappability biases for readcounts (i.e. coverage) in non-overlapping windows of fixe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HMMcopy/inst/doc/HMMcopy.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HMMcopy")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HMMCOPY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hmmcopy"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hmmcopy:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hmmcopy:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hmmcopy_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hmmcopy_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hmmcopy_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HMMsegment)
    library(jsonlite)

    # --- Correctreadcount [] ---
    # Key functions: correctReadcount
    normal_copy <- correctReadcount(normal_reads)
    normal_copy[1000:1010, ]
    # --- Hmmsegment [] ---
    # Key functions: HMMsegment
    tumour_segments <- HMMsegment(tumour_copy)
    # --- Log [] ---
    # Key functions: lob
    somatic_copy <- tumour_copy
    # LOGARITHM IDENTITY: log(a) - log(b) == lob(a / b)
    somatic_copy$copy <- tumour_copy$copy - normal_copy$copy
    # --- Hmmsegment [] ---
    # Key functions: HMMsegment, plotSegments
    somatic_segments <- HMMsegment(somatic_copy, newmu_param, verbose = FALSE)
    par(cex.main = 0.5, cex.lab = 0.5, cex.axis = 0.5, mar = c(2, 1.5, 0, 0), mgp = c(1, 0.5, 0))
    plotSegments(somatic_copy, somatic_segments, pch = ".",
      ylab = "Tumour Copy Number", xlab = "Chromosome Position")
    # --- Tolatex [] ---
    # Key functions: toLatex
    toLatex(sessionInfo())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hmmcopy_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hmmcopy_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hmmcopy_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HMMCOPY:", paste0("    hmmcopy: ", packageVersion("HMMcopy"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hmmcopy_results.csv
    touch ${prefix}_hmmcopy_output.rds
    echo "BIOC_HMMCOPY:" > versions.yml
    echo "    hmmcopy: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HMMCOPY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HMMCOPY(ch_input)

    emit:
    results  = BIOC_HMMCOPY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HMMCOPY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HMMCOPY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HMMCOPY.out.versions  // channel: path(versions.yml)
}
