#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DAMEfinder
// 'DAMEfinder' offers functionality for taking methtuple or bismark outputs to calculate ASM scores an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DAMEfinder/inst/doc/DAMEfinder_workflow.R
// Upstream  : GenomicRanges, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("DAMEfinder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DAMEFINDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-damefinder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-damefinder:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-damefinder:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_damefinder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_damefinder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_damefinder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(jsonlite)

    # --- Create GenomicRanges object [] ---
    # Key functions: colData, GRanges, dame_track, methyl_circle_plot, methyl_circle_plotCpG
    put SNP in GRanges (you can find the SNP with the dame_track function)
    snp <- GRanges(19, IRanges(267039, width = 1)) #always set the width if your
    bam.file <- system.file("extdata", "CRC1_chr19_trim.bam",
    # --- Dame track analysis [] ---
    # Key functions: dame_track, dame_track_mean, methyl_MDS_plot
    grp <- factor(c(rep("CRC",3),rep("NORM",2)), levels = c("NORM", "CRC"))
    methyl_MDS_plot(ASMscore, group = grp)
    utils::sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_damefinder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_damefinder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_damefinder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DAMEFINDER:", paste0("    damefinder: ", packageVersion("DAMEfinder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_damefinder_results.csv
    touch ${prefix}_damefinder_output.rds
    echo "BIOC_DAMEFINDER:" > versions.yml
    echo "    damefinder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DAMEFINDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DAMEFINDER(ch_input)

    emit:
    results  = BIOC_DAMEFINDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DAMEFINDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DAMEFINDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DAMEFINDER.out.versions  // channel: path(versions.yml)
}
