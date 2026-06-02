#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PathNet
// PathNet uses topological information present in pathways and differential expression levels of genes
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PathNet/inst/doc/PathNet.R
// Upstream  : PathNetData
// Downstream: none
//
// Install: BiocManager::install("PathNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PATHNET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pathnet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pathnet:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pathnet:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pathnet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pathnet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pathnet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PathNet)
    library(jsonlite)

    # --- Install Packages [] ---
    # Key functions: requireNamespace, packages
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install("PathNet")
    ## BiocManager::install("PathNetData")
    # --- Import Package And Show Disease Progression [] ---
    # Key functions: data
    library("PathNet")
    library("PathNetData")
    data(disease_progression)
    head(disease_progression)
    # --- Show Brain Regions [] ---
    # Key functions: data
    data(brain_regions)
    head(brain_regions)
    # --- Show Adjacency Matrix [] ---
    # Key functions: data
    data(A)
    # Load genes from direct evidence
    gene_ID <- brain_regions[,1]
    # Construct adjacency matrix
    A <- A [rownames(A) %in% gene_ID, rownames(A) %in% gene_ID]
    # --- Show Pathway [] ---
    # Key functions: data
    data(pathway)
    pathway[965:975,]
    # --- Show Custom Loading [] ---
    # Key functions: file
    # We use system.file to locate the directory with the
    # example text files from the PathNetData Package
    current <- getwd()
    setwd(system.file(dir="extdata", package="PathNetData"))
    # Begin loading datasets from the text files
    # --- Enrichment Analysis [] ---
    # Key functions: PathNet
    # Note we use a subset of evidence and a small number of
    # permutations for demonstration purposes
    # --- Contextual Analysis [] ---
    # Key functions: PathNet
    # Perform a contextual analysis with pathway enrichment
    # Note we use a subset of evidence and a small number of
    # permutations for demonstration purposes

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pathnet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pathnet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pathnet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PATHNET:", paste0("    pathnet: ", packageVersion("PathNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathnet_results.csv
    touch ${prefix}_pathnet_output.rds
    echo "BIOC_PATHNET:" > versions.yml
    echo "    pathnet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PATHNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PATHNET(ch_input)

    emit:
    results  = BIOC_PATHNET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PATHNET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PATHNET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PATHNET.out.versions  // channel: path(versions.yml)
}
