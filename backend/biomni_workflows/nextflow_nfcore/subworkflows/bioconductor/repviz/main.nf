#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RepViz
// RepViz enables the view of a genomic region in a simple and efficient way. RepViz allows simultaneou
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RepViz/inst/doc/RepViz.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RepViz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REPVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-repviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-repviz:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-repviz:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_repviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_repviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_repviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(RepViz)
    library(jsonlite)

    # --- input BAM [] ---
    # Key functions: kable
    BAM_table <- read.table(system.file("extdata","BAM_input.csv", package = "RepViz"), sep = ",")
    colnames(BAM_table) <- c("bam file","group")
    knitr::kable(BAM_table)
    # --- input BED [] ---
    # Key functions: kable
    BED_table <- read.table(system.file("extdata","BED_input.csv", package = "RepViz"), sep = ",")
    colnames(BED_table) <- c("bed file","Legend")
    knitr::kable(BED_table)
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, RepViz
    region <- GRanges("chr12:110938000-110940000")
    RepViz::RepViz(region = region,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_repviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_repviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_repviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REPVIZ:", paste0("    repviz: ", packageVersion("RepViz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_repviz_results.csv
    touch ${prefix}_repviz_output.rds
    echo "BIOC_REPVIZ:" > versions.yml
    echo "    repviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REPVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REPVIZ(ch_input)

    emit:
    results  = BIOC_REPVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REPVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REPVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REPVIZ.out.versions  // channel: path(versions.yml)
}
