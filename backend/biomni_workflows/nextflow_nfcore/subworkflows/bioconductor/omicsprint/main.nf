#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: omicsPrint
// omicsPrint provides functionality for cross omic genetic fingerprinting, for example, to verify samp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/omicsPrint/inst/doc/omicsPrint.R
// Upstream  : GEOquery, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("omicsPrint")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMICSPRINT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omicsprint"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omicsprint:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omicsprint:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omicsprint_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omicsprint_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omicsprint_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(omicsPrint)
    library(jsonlite)

    # --- Toydata [] ---
    # Key functions: sample, rbinom, swap

    # --- Allelesharing [] ---
    # Key functions: alleleSharing
    data <- alleleSharing(x, verbose=TRUE)
    # --- Inferrelations [] ---
    # Key functions: inferRelations
    mismatches <- inferRelations(data)
    mismatches
    # --- Extendedrelations [] ---
    # Key functions: grid
    relations <- expand.grid(idx = colnames(x), idy= colnames(x))
    relations$relation_type <- "unrelated"
    relations$relation_type[relations$idx == relations$idy] <- "identical"
    relations$relation_type[c(2,5)] <- "identical" ##replicate
    relations$relation_type[c(3,7,9,10)] <- "parent offspring"
    # --- Addrelations [] ---
    # Key functions: alleleSharing, inferRelations
    data <- alleleSharing(x, relations=relations)
    data
    mismatches <- inferRelations(data)
    mismatches
    # --- Xyallelesharing1 [] ---
    # Key functions: sample, alleleSharing
    rownames(x) <- paste0("rs", 1:100)
    y <- x[sample(1:100, 80),]
    data <- alleleSharing(x, y)
    # --- Xyallelesharing2 [] ---
    # Key functions: inferRelations
    data
    mismatches <- inferRelations(data)
    mismatches
    # --- Addrelations2 [] ---
    # Key functions: alleleSharing, inferRelations
    data <- alleleSharing(x, y, relations)
    data
    mismatches <- inferRelations(data)
    mismatches
    # --- Downloadretry [] ---
    # Key functions: tempfile, getGEO
    library(GEOquery)
    library(SummarizedExperiment)
    file <- tempfile(fileext = ".txt.gz")
    cnt <- 0
    value <- -1
    # --- make Summarized Experiment From Expression Set [] ---
    # Key functions: makeSummarizedExperimentFromExpressionSet
    se <- makeSummarizedExperimentFromExpressionSet(gset)
    se
    # --- Makerelationships [] ---
    # Key functions: grid, colData
    r <- expand.grid(idx=colnames(se), idy=colnames(se))
    r$Xpair <- sapply(strsplit(as.character(colData(se)[r$idx, "source_name_ch1"]),
                               split = "_"), head, 1)
    r$Ypair <- sapply(strsplit(as.character(colData(se)[r$idy, "source_name_ch1"]),
                               split = "_"), head, 1)
    # --- Selectcpgs [] ---
    # Key functions: mcols
    data(hm450.manifest.pop.GoNL)
    cpgs <- names(hm450.manifest.pop.GoNL[
        mcols(hm450.manifest.pop.GoNL)$MASK.snp5.EAS])
    se <- se[cpgs,]
    # --- Genotyping [] ---
    # Key functions: beta2genotype
    dnamCalls <- beta2genotype(se, assayName = "exprs")
    dim(dnamCalls)
    dnamCalls[1:5, 1:5]
    # --- Allelesharing [] ---
    # Key functions: alleleSharing, inferRelations
    data <- alleleSharing(dnamCalls, relations = r, verbose = TRUE)
    mismatches <- inferRelations(data)
    mismatches

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omicsprint_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omicsprint_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omicsprint_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMICSPRINT:", paste0("    omicsprint: ", packageVersion("omicsPrint"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omicsprint_results.csv
    touch ${prefix}_omicsprint_output.rds
    echo "BIOC_OMICSPRINT:" > versions.yml
    echo "    omicsprint: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMICSPRINT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMICSPRINT(ch_input)

    emit:
    results  = BIOC_OMICSPRINT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMICSPRINT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMICSPRINT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMICSPRINT.out.versions  // channel: path(versions.yml)
}
