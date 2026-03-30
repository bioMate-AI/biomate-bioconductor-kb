#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PSMatch
// The PSMatch package helps proteomics practitioners to load, handle and manage Peptide Spectrum Match
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PSMatch/inst/doc/AdjacencyMatrix.R
// Upstream  : QFeatures, Spectra, factoextra
// Downstream: none
//
// Install: BiocManager::install("PSMatch")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PSMATCH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-psmatch"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-psmatch:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-psmatch:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_psmatch_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_psmatch_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_psmatch_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ConnectedComponents)
    library(PSM)
    library(jsonlite)

    # --- Ident [] ---
    # Key functions: ident, PSM, filterPsmDecoy, filterPsmRank
    ---------------------------------------------------------------------
    library("PSMatch")
    id <- msdata::ident(full.names = TRUE, pattern = "TMT") |>
    PSM() |>
    filterPsmDecoy() |>
    # --- Frame [] ---
    # Key functions: frame
    ---------------------------------------------------------------------
    data.frame(id[1:10, c("sequence", "DatabaseAccess")])
    # --- Makeadjacencymatrix [] ---
    # Key functions: makeAdjacencyMatrix
    ---------------------------------------------------------------------
    adj <- makeAdjacencyMatrix(id)
    dim(adj)
    adj[1:5, 1:5]
    # --- Connectedcomponents [] ---
    # Key functions: ConnectedComponents
    ---------------------------------------------------------------------
    cc <- ConnectedComponents(adj)
    length(cc)
    cc
    # --- Connectedcomponents [] ---
    # Key functions: connectedComponents
    ---------------------------------------------------------------------
    connectedComponents(cc, 1)
    # --- Which [] ---
    # Key functions: nrows, ncols, dims
    ---------------------------------------------------------------------
    (i <- which(nrows(cc) > 2 & ncols(cc) > 2))
    dims(cc)[i, ]
    # --- Connectedcomponents [] ---
    # Key functions: connectedComponents
    ---------------------------------------------------------------------
    cx <- connectedComponents(cc, 1082)
    cx
    # --- Plotadjacencymatrix [] ---
    # Key functions: plotAdjacencyMatrix
    ---------------------------------------------------------------------
    plotAdjacencyMatrix(cx)
    # --- Character [] ---
    # Key functions: cut, colorRampPalette
    ---------------------------------------------------------------------
    cls <- as.character(cut(score, 12,
                            labels = colorRampPalette(c("white", "red"))(12)))
    names(cls) <- id$sequence
    head(cls)
    # --- Plotadjacencymatrix [] ---
    # Key functions: plotAdjacencyMatrix
    ---------------------------------------------------------------------
    plotAdjacencyMatrix(cx, pepColors = cls)
    # --- Rowdata [] ---
    # Key functions: rowData
    ---------------------------------------------------------------------
    prots <- rowData(se)$Proteins
    names(prots) <- rowData(se)$Sequence
    head(prots)
    # --- Makeadjacencymatrix [] ---
    # Key functions: makeAdjacencyMatrix, ConnectedComponents
    ---------------------------------------------------------------------
    adj <- makeAdjacencyMatrix(prots, split = ";")
    dim(adj)
    adj[1:3, 1:3]
    cc <- ConnectedComponents(adj)
    # --- Head [] ---
    # Key functions: prioritiseConnectedComponents
    ---------------------------------------------------------------------
    head(cctab <- prioritiseConnectedComponents(cc))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_psmatch_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_psmatch_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_psmatch_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PSMATCH:", paste0("    psmatch: ", packageVersion("PSMatch"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_psmatch_results.csv
    touch ${prefix}_psmatch_output.rds
    echo "BIOC_PSMATCH:" > versions.yml
    echo "    psmatch: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PSMATCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PSMATCH(ch_input)

    emit:
    results  = BIOC_PSMATCH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PSMATCH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PSMATCH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PSMATCH.out.versions  // channel: path(versions.yml)
}
