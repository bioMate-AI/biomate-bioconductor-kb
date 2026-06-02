#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: msqrob2
// msqrob2 provides a robust linear mixed model framework for assessing differential abundance in MS-ba
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/msqrob2/inst/doc/cptac.R
// Upstream  : QFeatures, gridExtra, limma, plotly, tidyverse
// Downstream: none
//
// Install: BiocManager::install("msqrob2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSQROB2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msqrob2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msqrob2:1.14.1--r44_0' :
        'quay.io/biocontainers/bioconductor-msqrob2:1.14.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msqrob2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msqrob2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msqrob2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(msqrob2)
    library(jsonlite)

    # --- Which [] ---
    # Key functions: colData, unlist, factor
    ---------------------------------------------------------------------
    cond <- which(strsplit(colnames(pe)[[1]][1], split = "")[[1]] == "A") # find where condition is stored
    colData(pe)$condition <- substr(colnames(pe), cond, cond) %>%
        unlist() %>%
        as.factor()
    # --- Rowdata [] ---
    # Key functions: rowData, rowSums, assay
    ---------------------------------------------------------------------
    rowData(pe[["peptideRaw"]])$nNonZero <- rowSums(assay(pe[["peptideRaw"]]) > 0)
    # --- Zeroisna [] ---
    # Key functions: zeroIsNA
    ---------------------------------------------------------------------
    pe <- zeroIsNA(pe, "peptideRaw") # convert 0 to NA
    # --- Logtransform [] ---
    # Key functions: logTransform, plotDensities, assay
    ---------------------------------------------------------------------
    pe <- logTransform(pe, base = 2, i = "peptideRaw", name = "peptideLog")
    limma::plotDensities(assay(pe[["peptideLog"]]))
    # --- Rowdata [] ---
    # Key functions: rowData, smallestUniqueGroups
    ---------------------------------------------------------------------
    Protein_filter <- rowData(pe[["peptideLog"]])$Proteins %in% smallestUniqueGroups(rowData(pe[["peptideLog"]])$Proteins)
    pe <- pe[Protein_filter,,]
    # --- Filterfeatures [] ---
    # Key functions: filterFeatures
    ---------------------------------------------------------------------
    pe <- filterFeatures(pe, ~ Reverse != "+")
    pe <- filterFeatures(pe, ~ Potential.contaminant != "+")
    # --- Normalize [] ---
    # Key functions: normalize
    ---------------------------------------------------------------------
    pe <- normalize(pe,
        i = "peptideLog",
        name = "peptideNorm",
        method = "center.median"
    # --- Plotdensities [] ---
    # Key functions: plotDensities, assay
    ---------------------------------------------------------------------
    limma::plotDensities(assay(pe[["peptideNorm"]]))
    # --- Boxplot [] ---
    # Key functions: assay, palette
    ---------------------------------------------------------------------
    boxplot(assay(pe[["peptideNorm"]]),
        col = palette()[-1],
        main = "Peptide distribtutions after normalisation", ylab = "intensity"
    )
    # --- Plotmds [] ---
    # Key functions: plotMDS, assay, colData
    ---------------------------------------------------------------------
    limma::plotMDS(assay(pe[["peptideNorm"]]), col = as.numeric(colData(pe)$condition))
    # --- Getcoef [] ---
    # Key functions: getCoef, rowData
    ---------------------------------------------------------------------
    getCoef(rowData(pe[["protein"]])$msqrobModels[[1]])
    # --- Makecontrast [] ---
    # Key functions: makeContrast, hypothesisTest
    ---------------------------------------------------------------------
    L <- makeContrast("conditionB=0", parameterNames = c("conditionB"))
    pe <- hypothesisTest(object = pe, i = "protein", contrast = L)
    # --- Rowdata [] ---
    # Key functions: rowData, rownames_to_column, filter, pull, heatmap, assay
    ---------------------------------------------------------------------
    sigNames <- rowData(pe[["protein"]])$conditionB %>%
        rownames_to_column("protein") %>%
        filter(adjPval < 0.05) %>%
        pull(protein)
    # --- Plotmds [] ---
    # Key functions: plotMDS, assay, colData
    ---------------------------------------------------------------------
    limma::plotMDS(assay(pe[["proteinMedian"]]),
        col = as.numeric(colData(pe)$condition)
    )
    # --- Try [] ---
    # Key functions: msqrob
    ---------------------------------------------------------------------
    try(pe <- msqrob(
        object = pe, i = "protein", formula = ~condition,
        modelColumnName = "ridge", ridge = TRUE
    )) # note: intentional error

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msqrob2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msqrob2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msqrob2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSQROB2:", paste0("    msqrob2: ", packageVersion("msqrob2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msqrob2_results.csv
    touch ${prefix}_msqrob2_output.rds
    echo "BIOC_MSQROB2:" > versions.yml
    echo "    msqrob2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSQROB2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSQROB2(ch_input)

    emit:
    results  = BIOC_MSQROB2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSQROB2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSQROB2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSQROB2.out.versions  // channel: path(versions.yml)
}
