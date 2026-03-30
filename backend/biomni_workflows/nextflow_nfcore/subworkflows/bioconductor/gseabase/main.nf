#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSEABase
// This package provides classes and methods to support Gene Set Enrichment Analysis (GSEA).
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSEABase/inst/doc/GSEABase.R
// Upstream  : ReportingTools, annotate
// Downstream: AGDEX, BicARE, CCPROMISE, Cepo, cpvSNP
//
// Install: BiocManager::install("GSEABase")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSEABASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gseabase"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gseabase:1.68.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gseabase:1.68.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gseabase_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gseabase_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gseabase_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneColorSet)
    library(GeneSet)
    library(GeneSetCollection)
    library(HTMLReport)
    library(jsonlite)

    # --- GeneSet analysis [] ---
    # Key functions: GeneSet, showMethods, mapIdentifiers, textConnection, close, unlink, GeneColorSet, GeneSetCollection
    library(annotate)                       # getEG
    eids <- unique(getEG(geneIds(egs), "hgu95av2"))
    eids <- eids[!is.na(eids)]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gseabase_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gseabase_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gseabase_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSEABASE:", paste0("    gseabase: ", packageVersion("GSEABase"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gseabase_results.csv
    touch ${prefix}_gseabase_output.rds
    echo "BIOC_GSEABASE:" > versions.yml
    echo "    gseabase: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSEABASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSEABASE(ch_input)

    emit:
    results  = BIOC_GSEABASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSEABASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSEABASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSEABASE.out.versions  // channel: path(versions.yml)
}
