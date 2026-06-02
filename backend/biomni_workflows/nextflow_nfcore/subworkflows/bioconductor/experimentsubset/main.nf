#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ExperimentSubset
// Experiment objects such as the SummarizedExperiment or SingleCellExperiment are data containers for 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ExperimentSubset/inst/doc/ExperimentSubset.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ExperimentSubset")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EXPERIMENTSUBSET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-experimentsubset"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-experimentsubset:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-experimentsubset:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_experimentsubset_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_experimentsubset_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_experimentsubset_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentSubset)
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: rpois, SingleCellExperiment, ExperimentSubset
    ---------------------------------------------------------------------
    counts <- matrix(rpois(100, lambda = 10), ncol=10, nrow=10)
    sce <- SingleCellExperiment(list(counts = counts))
    es <- ExperimentSubset(sce)
    es
    # --- Matrix [] ---
    # Key functions: rpois, ExperimentSubset
    ---------------------------------------------------------------------
    counts <- matrix(rpois(100, lambda = 10), ncol=10, nrow=10)
    ExperimentSubset(list(counts = counts))
    # --- Createsubset [] ---
    # Key functions: createSubset
    ---------------------------------------------------------------------
    es <- createSubset(es,
                       subsetName = "subset1",
                       rows = c(1:2),
                       cols = c(1:5),
    # --- Assay [] ---
    # Key functions: assay, setSubsetAssay
    ---------------------------------------------------------------------
    subset1Assay <- assay(es, "subset1")
    subset1Assay[,] <- subset1Assay[,] + 1
    es <- setSubsetAssay(es,
                      subsetName = "subset1",
    # --- Getsubsetassay [] ---
    # Key functions: getSubsetAssay
    ---------------------------------------------------------------------
    #get assay from 'subset1'
    getSubsetAssay(es, "subset1")
    #get internal 'subset1Assay'
    getSubsetAssay(es, "subset1Assay")
    # --- Subsetsummary [] ---
    # Key functions: subsetSummary
    ---------------------------------------------------------------------
    subsetSummary(es)
    # --- Coldata [] ---
    # Key functions: colData, subsetDim, subsetColData
    ---------------------------------------------------------------------
    #store colData to parent object
    colData(es) <- cbind(colData(es), sampleID = seq(1:dim(es)[2]))
    #store colData to 'subset1' using option 1
    colData(es, subsetName = "subset1") <- cbind(
    # --- Matrix [] ---
    # Key functions: rpois, SingleCellExperiment, ExperimentSubset, createSubset, assay
    ---------------------------------------------------------------------
    #creating a dummy ES object
    counts <- matrix(rpois(100, lambda = 10), ncol=10, nrow=10)
    sce <- SingleCellExperiment(list(counts = counts))
    es <- ExperimentSubset(sce)
    # --- Assay [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    #assay getter has parameters 'x' which is the input object, 'i' which can either
    #be a assay name in the parent object, a subset name or a subset assay name
    #getting 'counts' from parent es object
    assay(
    # --- Matrix [] ---
    # Key functions: rpois, SingleCellExperiment, ExperimentSubset, subsetSummary
    ---------------------------------------------------------------------
    counts <- matrix(rpois(100, lambda = 10), ncol=10, nrow=10)
    sce <- SingleCellExperiment(list(counts = counts))
    es <- ExperimentSubset(sce)
    subsetSummary(es)
    # --- Createsubset [] ---
    # Key functions: createSubset, subsetSummary
    ---------------------------------------------------------------------
    es <- createSubset(es,
                       subsetName = "subset1",
                       rows = c(1:5),
                       cols = c(1:5),
    # --- Assay [] ---
    # Key functions: assay
    ---------------------------------------------------------------------
    subset2Assay <- assay(es, "subset2")
    subset2Assay[,] <- subset2Assay[,] + 1
    # --- Setsubsetassay [] ---
    # Key functions: setSubsetAssay, assay, subsetSummary
    ---------------------------------------------------------------------
    #approach 1
    es <- setSubsetAssay(es,
                      subsetName = "subset2",
                      inputMatrix = subset2Assay,
    # --- Altexp [] ---
    # Key functions: altExp, SingleCellExperiment, assay
    ---------------------------------------------------------------------
    altExp(x = es,
           e = "subset2_alt1",
           subsetName = "subset2") <- SingleCellExperiment(assay = list(
             counts = assay(es, "subset2")
    # --- Subsetsummary [] ---
    # Key functions: subsetSummary
    ---------------------------------------------------------------------
    subsetSummary(es)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_experimentsubset_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_experimentsubset_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_experimentsubset_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EXPERIMENTSUBSET:", paste0("    experimentsubset: ", packageVersion("ExperimentSubset"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_experimentsubset_results.csv
    touch ${prefix}_experimentsubset_output.rds
    echo "BIOC_EXPERIMENTSUBSET:" > versions.yml
    echo "    experimentsubset: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EXPERIMENTSUBSET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EXPERIMENTSUBSET(ch_input)

    emit:
    results  = BIOC_EXPERIMENTSUBSET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EXPERIMENTSUBSET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EXPERIMENTSUBSET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EXPERIMENTSUBSET.out.versions  // channel: path(versions.yml)
}
