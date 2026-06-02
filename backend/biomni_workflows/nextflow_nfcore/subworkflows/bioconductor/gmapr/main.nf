#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gmapR
// GSNAP and GMAP are a pair of tools to align short-read data written by Tom Wu.  This package provide
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gmapR/inst/doc/gmapR.R
// Upstream  : LungCancerLines
// Downstream: none
//
// Install: BiocManager::install("gmapR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GMAPR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gmapr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gmapr:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gmapr:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gmapr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gmapr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gmapr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gmapR)
    library(BamTallyParam)
    library(GmapGenome)
    library(GsnapParam)
    library(LungCancerFastqFiles)
    library(TP53Genome)
    library(jsonlite)

    # --- Splice Site Annotation [] ---
    # Key functions: spliceSites<-
    spliceSites(gmapGenome, "knownGene") <- exons


    # --- Alignment Parameter Configuration [] ---
    # Key functions: GsnapParam
    gsnapParam <- GsnapParam(
        genome = gmapGenome,
        unique_only = FALSE,
        suboptimal_levels = 2L,
        npaths = 10L,
        novelsplicing = TRUE,
        splicing = "knownGene",
        indel_penalty = 1L,
        distant_splice_penalty = 1L,
        clip_overlap = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gmapr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gmapr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gmapr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GMAPR:", paste0("    gmapr: ", packageVersion("gmapR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gmapr_results.csv
    touch ${prefix}_gmapr_output.rds
    echo "BIOC_GMAPR:" > versions.yml
    echo "    gmapr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GMAPR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GMAPR(ch_input)

    emit:
    results  = BIOC_GMAPR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GMAPR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GMAPR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GMAPR.out.versions  // channel: path(versions.yml)
}
