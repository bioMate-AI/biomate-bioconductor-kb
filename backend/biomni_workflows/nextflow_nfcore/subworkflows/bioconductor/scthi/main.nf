#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scTHI — ligand_receptor_analysis
// Identify and visualize significant ligand-receptor interactions between two cell clusters from single-cell RNA-seq data.
// Input: expMat, cell_metadata
// Container: quay.io/biocontainers/bioconductor-scthi:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: scTHI
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define cell clusters of interest
//  * 2. [Core Analysis] Run scTHI_score to compute interaction scores and p-values
//  * 3. [Visualization & Output] Plot results using scTHI_plotResult
//  * 4. [Core Analysis] Run t-SNE using scTHI_runTsne
//  * 5. [Visualization & Output] Visualize clusters on t-SNE using scTHI_plotCluster
//  * 6. [Visualization & Output] Visualize specific interaction pairs on t-SNE using scTHI_plotPairs

nextflow.enable.dsl = 2

process BIOC_SCTHI_LIGAND_RECEPTOR_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("scTHI")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(scTHI)
    
    # 1. Read User Input Files
    # The pipeline expects 'expMat' and 'cell_metadata' in the working directory.
    # We support RDS, CSV, TSV, or TXT formats.
    
    if (file.exists("expMat.rds")) {
      expMat <- readRDS("expMat.rds")
    } else if (file.exists("expMat.csv")) {
      expMat <- as.matrix(read.csv("expMat.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("expMat.tsv")) {
      expMat <- as.matrix(read.delim("expMat.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("expMat.txt")) {
      expMat <- as.matrix(read.table("expMat.txt", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: Could not find expMat file (expMat.rds, expMat.csv, expMat.tsv, or expMat.txt) in the working directory.")
    }
    
    if (file.exists("cell_metadata.rds")) {
      cell_metadata <- readRDS("cell_metadata.rds")
    } else if (file.exists("cell_metadata.csv")) {
      cell_metadata <- read.csv("cell_metadata.csv", row.names = 1, check.names = FALSE)
    } else if (file.exists("cell_metadata.tsv")) {
      cell_metadata <- read.delim("cell_metadata.tsv", row.names = 1, check.names = FALSE)
    } else if (file.exists("cell_metadata.txt")) {
      cell_metadata <- read.table("cell_metadata.txt", header = TRUE, row.names = 1, check.names = FALSE)
    } else {
      stop("Error: Could not find cell_metadata file (cell_metadata.rds, cell_metadata.csv, cell_metadata.tsv, or cell_metadata.txt) in the working directory.")
    }
    
    # Align cells between expression matrix and metadata
    common_cells <- intersect(colnames(expMat), rownames(cell_metadata))
    if (length(common_cells) == 0) {
      stop("Error: No common cells found between expMat columns and cell_metadata row names.")
    }
    expMat <- expMat[, common_cells, drop = FALSE]
    cell_metadata <- cell_metadata[common_cells, , drop = FALSE]
    
    # 2. Define Cell Clusters of Interest
    # Identify the column containing cell type annotations
    type_col <- "Type"
    if (!(type_col %in% colnames(cell_metadata))) {
      potential_cols <- grep("type|cluster|group", colnames(cell_metadata), ignore.case = TRUE, value = TRUE)
      if (length(potential_cols) > 0) {
        type_col <- potential_cols[1]
      } else {
        type_col <- colnames(cell_metadata)[1]
      }
    }
    
    # Extract Malignant and Immune cell names
    Malignant_cells <- rownames(cell_metadata)[tolower(cell_metadata[[type_col]]) == "malignant"]
    if (length(Malignant_cells) == 0) {
      unique_groups <- unique(cell_metadata[[type_col]])
      Malignant_cells <- rownames(cell_metadata)[cell_metadata[[type_col]] == unique_groups[1]]
    }
    Malignant <- Malignant_cells[1:min(100, length(Malignant_cells))]
    
    Immune <- rownames(cell_metadata)[tolower(cell_metadata[[type_col]]) %in% c("immune cell", "immune")]
    if (length(Immune) == 0) {
      unique_groups <- unique(cell_metadata[[type_col]])
      if (length(unique_groups) > 1) {
        Immune <- rownames(cell_metadata)[cell_metadata[[type_col]] == unique_groups[2]]
      } else {
        Immune <- rownames(cell_metadata)[cell_metadata[[type_col]] == unique_groups[1]]
      }
    }
    
    # 3. Run scTHI_score to compute interaction scores and p-values
    H3K27.result <- scTHI_score(
      expMat = expMat,
      cellCusterA = Malignant,
      cellCusterB = Immune,
      cellCusterAName = "Malignant",
      cellCusterBName = "Immune",
      topRank = 10,
      PValue = TRUE,
      pvalueCutoff = 0.05,
      nPermu = 10,
      ncore = 1
    )
    
    # Save the result table
    if (!is.null(H3K27.result\$result)) {
      write.csv(H3K27.result\$result, "scTHI_result_table.csv", row.names = TRUE)
    }
    
    # 4. Plot results using scTHI_plotResult
    pdf("scTHI_plotResult_score.pdf")
    scTHI_plotResult(scTHIresult = H3K27.result,
                    cexNames = 0.7,
                    plotType = "score")
    dev.off()
    
    pdf("scTHI_plotResult_pair.pdf")
    scTHI_plotResult(scTHIresult = H3K27.result,
                    cexNames = 0.7,
                    plotType = "pair")
    dev.off()
    
    # 5. Run t-SNE using scTHI_runTsne
    H3K27.result <- scTHI_runTsne(scTHIresult = H3K27.result)
    
    # Save the complete result object
    saveRDS(H3K27.result, "scTHI_result.rds")
    
    # 6. Visualize clusters on t-SNE using scTHI_plotCluster
    pdf("scTHI_plotCluster.pdf")
    scTHI_plotCluster(scTHIresult = H3K27.result,
                    cexPoint = 0.8,
                    legendPos = "bottomleft")
    dev.off()
    
    # 7. Visualize specific interaction pairs on t-SNE using scTHI_plotPairs
    tryCatch({
      pdf("scTHI_plotPairs.pdf")
      scTHI_plotPairs(
        scTHIresult = H3K27.result,
        cexPoint = 0.8,
        interactionToplot = "THY1_ITGAX:ITGB2"
      )
      dev.off()
    }, error = function(e) {
      warning("Could not plot 'THY1_ITGAX:ITGB2'. Attempting to plot the top detected interaction instead.")
      if (!is.null(H3K27.result\$result) && nrow(H3K27.result\$result) > 0) {
        top_pair <- rownames(H3K27.result\$result)[1]
        pdf("scTHI_plotPairs.pdf")
        scTHI_plotPairs(
          scTHIresult = H3K27.result,
          cexPoint = 0.8,
          interactionToplot = top_pair
        )
        dev.off()
      } else {
        warning("No significant interactions found to plot.")
      }
    })

    writeLines(c(
        '"BIOC_SCTHI_LIGAND_RECEPTOR_ANALYSIS":',
        paste0('    scTHI: ', as.character(packageVersion('scTHI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ligand_receptor_analysis.csv versions.yml
    """
}

workflow BIOC_SCTHI_LIGAND_RECEPTOR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expMat, cell_metadata ] ]

    main:
    BIOC_SCTHI_LIGAND_RECEPTOR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCTHI_LIGAND_RECEPTOR_ANALYSIS.out.tables
    plots    = BIOC_SCTHI_LIGAND_RECEPTOR_ANALYSIS.out.plots
    objects  = BIOC_SCTHI_LIGAND_RECEPTOR_ANALYSIS.out.objects
    versions = BIOC_SCTHI_LIGAND_RECEPTOR_ANALYSIS.out.versions
}
