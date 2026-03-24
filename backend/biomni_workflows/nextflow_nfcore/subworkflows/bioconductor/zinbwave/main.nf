#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: zinbwave
// Implements a general and flexible zero-inflated negative binomial model that can be used to provide 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/zinbwave/inst/doc/intro.R
// Upstream  : BiocParallel, DESeq2, Rtsne, Seurat, biomaRt
// Downstream: none
//
// Install: BiocManager::install("zinbwave")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ZINBWAVE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-zinbwave"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-zinbwave:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-zinbwave:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(dgelist)

    output:
    tuple val(meta), path("${meta.id}_zinbwave_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_zinbwave_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_zinbwave_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSet)
    library(DGEList)
    library(FindClusters)
    library(FindNeighbors)
    library(ReprocessedFluidigmData)
    library(Rtsne)
    library(jsonlite)

    # --- Connect to BioMart [] ---
    # Key functions: useMart, useDataset, getBM, DGEList, calcNormFactors, estimateDisp, glmFit, glmWeightedF
    mart <- useMart("ensembl")
    mart <- useDataset("hsapiens_gene_ensembl", mart = mart)
    bm <- getBM(attributes=c('hgnc_symbol', 'start_position',
    # --- Filter by row sum threshold [] ---
    # Key functions: rowSums
    filter <- rowSums(assay(fluidigm)>5)>5
    table(filter)
    # --- Construct kNN graph for clustering [] ---
    # Key functions: FindNeighbors, FindClusters
    seu <- FindNeighbors(seu, reduction = "zinbwave",
    seu <- FindClusters(object = seu)
    # --- Custom ggplot2 visualization [] ---
    # Key functions: reducedDim, ggplot, scale_color_brewer, Rtsne, zinbsurf
    fluidigm_surf <- zinbsurf(fluidigm, K = 2, epsilon = 1000,
    W2 <- reducedDim(fluidigm_surf)
    data.frame(W2, bio=colData(fluidigm)$Biological_Condition,
    # --- Assay data access [] ---
    # Key functions: register, ReprocessedFluidigmData, assay, assayNames, zinbwave, rowData, zinbFit
    assay(fluidigm) %>% log1p %>% rowVars -> vars
    names(vars) <- rownames(fluidigm)
    vars <- sort(vars, decreasing = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_zinbwave_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_zinbwave_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_zinbwave_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ZINBWAVE:", paste0("    zinbwave: ", packageVersion("zinbwave"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zinbwave_results.csv
    touch ${prefix}_zinbwave_output.rds
    echo "BIOC_ZINBWAVE:" > versions.yml
    echo "    zinbwave: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ZINBWAVE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(dgelist) ]

    main:
    BIOC_ZINBWAVE(ch_input)

    emit:
    results  = BIOC_ZINBWAVE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ZINBWAVE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ZINBWAVE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ZINBWAVE.out.versions  // channel: path(versions.yml)
}
