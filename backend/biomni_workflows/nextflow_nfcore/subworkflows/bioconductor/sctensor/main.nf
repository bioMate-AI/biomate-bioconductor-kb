#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scTensor — cell_cell_interaction_analysis
// Perform cell-cell interaction tensor construction, rank estimation, decomposition, and HTML report generation on single-cell RNA-Seq data.
// Input: gene_expression_matrix.csv, cell_metadata.csv
// Container: quay.io/biocontainers/bioconductor-sctensor:2.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationHub, LRBaseDbi, SingleCellExperiment, scTensor
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Retrieve the organism-specific LRBase database from
//  * 2. [Visualization & Output] Create a SingleCellExperiment object and assign 2D
//  * 3. [Visualization & Output] Register cell types and the LRBase database using
//  * 4. [Visualization & Output] Estimate optimal decomposition ranks using cellCellRanks
//  * 5. [Visualization & Output] Perform non-negative Tucker decomposition using
//  * 6. [Visualization & Output] Generate an interactive HTML report using cellCellReport

nextflow.enable.dsl = 2

process BIOC_SCTENSOR_CELL_CELL_INTERACTION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("AnnotationHub", "LRBaseDbi", "scTensor", "SingleCellExperiment")
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
            
            library("AnnotationHub")
            library("LRBaseDbi")
            suppressPackageStartupMessages(library("scTensor"))
            suppressPackageStartupMessages(library("SingleCellExperiment"))
            
            # --- Retrieve the organism-specific LRBase database from ---
            ah <- AnnotationHub()
            dbfile <- query(ah, c("LRBaseDb", "Homo sapiens"))[[1]]
            LRBase.Hsa.eg.db <- LRBaseDbi::LRBaseDb(dbfile)
            
            # Read user input files
            expr <- read.csv("gene_expression_matrix.csv", row.names = 1, check.names = FALSE)
            expr_mat <- as.matrix(expr)
            
            meta <- read.csv("cell_metadata.csv", row.names = 1, check.names = FALSE)
            
            # Align cells between expression matrix and metadata
            common_cells <- intersect(colnames(expr_mat), rownames(meta))
            if (length(common_cells) == 0) {
              stop("Error: No matching cell identifiers found between gene_expression_matrix.csv and cell_metadata.csv")
            }
            expr_mat <- expr_mat[, common_cells, drop = FALSE]
            meta <- meta[common_cells, , drop = FALSE]
            
            # Extract cell types
            cell_types <- NULL
            if ("cell_type" %in% colnames(meta)) {
              cell_types <- as.character(meta\$cell_type)
            } else if ("celltype" %in% colnames(meta)) {
              cell_types <- as.character(meta\$celltype)
            } else {
              # Fallback to the first non-numeric column, or first column
              non_num_cols <- sapply(meta, function(x) !is.numeric(x))
              if (any(non_num_cols)) {
                cell_types <- as.character(meta[[which(non_num_cols)[1]]])
              } else {
                cell_types <- as.character(meta[[1]])
              }
            }
            
            # Extract 2D coordinates (t-SNE or UMAP)
            coords <- NULL
            coord_cols <- grep("tSNE|UMAP|Dim|X|Y", colnames(meta), ignore.case = TRUE, value = TRUE)
            if (length(coord_cols) >= 2) {
              coords <- as.matrix(meta[, coord_cols[1:2]])
            } else {
              numeric_cols <- sapply(meta, is.numeric)
              if (sum(numeric_cols) >= 2) {
                coords <- as.matrix(meta[, which(numeric_cols)[1:2]])
              } else {
                coords <- matrix(0, nrow = nrow(meta), ncol = 2)
              }
            }
            colnames(coords) <- c("Dim1", "Dim2")
            
            # --- Create a SingleCellExperiment object and assign 2D ---
            sce <- SingleCellExperiment(assays=list(counts = expr_mat))
            reducedDims(sce) <- SimpleList(TSNE=coords)
            
            # Save a PDF plot of the cell types in 2D space
            pdf("cell_types_visualization.pdf")
            plot(reducedDims(sce)[[1]], col=as.factor(cell_types), pch=16, xlab="Dim1", ylab="Dim2", main="Cell Types Visualization")
            dev.off()
            
            # --- Register cell types and the LRBase database using ---
            cellCellSetting(sce, LRBase.Hsa.eg.db, cell_types)
            
            # --- Estimate optimal decomposition ranks using cellCellRanks ---
            rks <- cellCellRanks(sce)
            saveRDS(rks, "scTensor_estimated_ranks.rds")
            
            # --- Perform non-negative Tucker decomposition using ---
            set.seed(1234)
            cellCellDecomp(sce, ranks=rks\$selected)
            
            # Save the final SingleCellExperiment object containing decomposition results
            saveRDS(sce, "scTensor_sce_completed.rds")
            
            # --- Generate an interactive HTML report using cellCellReport ---
            cellCellReport(sce, out.dir = "./scTensor_report")

    writeLines(c(
        '"BIOC_SCTENSOR_CELL_CELL_INTERACTION_ANALYSIS":',
        paste0('    scTensor: ', as.character(packageVersion('scTensor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_cell_interaction_analysis.csv versions.yml
    """
}

workflow BIOC_SCTENSOR_CELL_CELL_INTERACTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_expression_matrix.csv, cell_metadata.csv ] ]

    main:
    BIOC_SCTENSOR_CELL_CELL_INTERACTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCTENSOR_CELL_CELL_INTERACTION_ANALYSIS.out.tables
    plots    = BIOC_SCTENSOR_CELL_CELL_INTERACTION_ANALYSIS.out.plots
    objects  = BIOC_SCTENSOR_CELL_CELL_INTERACTION_ANALYSIS.out.objects
    versions = BIOC_SCTENSOR_CELL_CELL_INTERACTION_ANALYSIS.out.versions
}
