#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EnrichDO
// To implement disease ontology (DO) enrichment analysis, this package is designed and presents a doub
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EnrichDO/inst/doc/EnrichDO.R
// Upstream  : devtools
// Downstream: none
//
// Install: BiocManager::install("EnrichDO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENRICHDO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-enrichdo"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-enrichdo:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-enrichdo:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_enrichdo_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_enrichdo_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_enrichdo_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EnrichDO)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )

    # --- Label=init [] ---
    # Key functions: doEnrich, show
    demo.data=c(1636,351,102,2932,3077,348,4137,54209,5663,5328,23621,3416,3553)
    demo_result<-doEnrich(interestGenes=demo.data)
    show(demo_result)

    # --- Eval=true [] ---
    # Key functions: showDoTerms, doEnrich, fisherTest, holm
    head(doterms)
    showDoTerms(doterms)

    ## -----------------------------------------------------------------------------
    weighted_demo<-doEnrich(interestGenes=demo.data,
                               test="fisherTest",
                               method="holm",
                               m=1,
                               minGsize=10,
                               maxGsize=2000,
                               delta=0.05,
                               penalize=TRUE)

    ## -----------------------------------------------------------------------------
    penalF_demo<-doEnrich(interestGenes=demo.data, penalize=FALSE)

    # --- Eval=true [] ---
    # Key functions: writeDoTerms, tempdir, doterms.txt
    writeDoTerms(doterms,file=file.path(tempdir(), "doterms.txt"))

    # --- Eval=true [] ---
    # Key functions: writeResult, tempdir, result.txt
    writeResult(EnrichResult = demo_result,file=file.path(tempdir(), "result.txt"), Q=1, P=1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_enrichdo_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_enrichdo_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_enrichdo_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ENRICHDO:", paste0("    enrichdo: ", packageVersion("EnrichDO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enrichdo_results.csv
    touch ${prefix}_enrichdo_output.rds
    echo "BIOC_ENRICHDO:" > versions.yml
    echo "    enrichdo: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ENRICHDO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ENRICHDO(ch_input)

    emit:
    results  = BIOC_ENRICHDO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ENRICHDO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ENRICHDO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ENRICHDO.out.versions  // channel: path(versions.yml)
}
