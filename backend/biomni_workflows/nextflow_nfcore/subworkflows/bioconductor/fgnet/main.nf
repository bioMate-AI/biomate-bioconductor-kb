#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FGNet
// Build and visualize functional gene and term networks from clustering of enrichment analyses in mult
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FGNet/inst/doc/FGNet.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("FGNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FGNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-fgnet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-fgnet:3.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-fgnet:3.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_fgnet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_fgnet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_fgnet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FGNet)
    library(jsonlite)


    # --- Pre [] ---
    # Key functions: set
    library(knitr)
    opts_chunk$set(warning=FALSE,message=FALSE,cache=TRUE)

    # --- Eval=false [] ---
    # Key functions: getwd, unlist
    #  getwd()

    ## -----------------------------------------------------------------------------
    genesYeast <- c("ADA2", "APC1", "APC11", "APC2", "APC4", "APC5", "APC9", "CDC16", 
                    "CDC23", "CDC26", "CDC27", "CFT1", "CFT2", "DCP1", "DOC1", "FIP1", 
                    "GCN5", "GLC7", "HFI1", "KEM1", "LSM1", "LSM2", "LSM3", "LSM4", 
                    "LSM5", "LSM6", "LSM7", "LSM8", "MPE1", "NGG1", "PAP1", "PAT1", 
                    "PFS2", "PTA1", "PTI1", "REF2", "RNA14", "RPN1", "RPN10", "RPN11", 
                    "RPN13", "RPN2", "RPN3", "RPN5", "RPN6", "RPN8", "RPT1", "RPT3", 
                    "RPT6", "SGF11", "SGF29", "SGF73", "SPT20", "SPT3", "SPT7", "SPT8", 
                    "TRA1", "YSH1", "YTH1")

    library(org.Sc.sgd.db)
    geneLabels <- unlist(as.list(org.Sc.sgdGENENAME))
    genesYeast <- sort(geneLabels[which(geneLabels %in% genesYeast)])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_fgnet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_fgnet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_fgnet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FGNET:", paste0("    fgnet: ", packageVersion("FGNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fgnet_results.csv
    touch ${prefix}_fgnet_output.rds
    echo "BIOC_FGNET:" > versions.yml
    echo "    fgnet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FGNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FGNET(ch_input)

    emit:
    results  = BIOC_FGNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FGNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FGNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FGNET.out.versions  // channel: path(versions.yml)
}
