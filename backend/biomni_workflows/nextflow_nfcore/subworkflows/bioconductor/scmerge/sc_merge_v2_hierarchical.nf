#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scMerge — sc_merge_v2_hierarchical
// Perform multi-level hierarchical batch integration using scMerge2h.
// Input: example_sce, segList_ensemblGeneID
// Container: quay.io/biocontainers/bioconductor-scmerge:1.26.0--r45hdfd78af_0
// R packages: SingleCellExperiment, scMerge, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, scMerge, scater
// Visualizations: PCA plot
// QC: diagnostic MA/PCA QC, cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct hierarchical index list
//  * 2. [Input & Preparation] Construct batch information list
//  * 3. [Core Analysis] Run scMerge2h with specified ruvK for each level
//  * 4. [Core Analysis] Extract the final level adjusted matrix

nextflow.enable.dsl = 2

process BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL {
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
    .bm_deps <- c("SingleCellExperiment", "scMerge", "scater")
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
        
        # Load required libraries
        suppressPackageStartupMessages({
          library(scMerge)
          library(scater)
        })
        
        # Helper function to read input files from the working directory
        read_input <- function(filename) {
          if (file.exists(filename)) {
            return(readRDS(filename))
          } else if (file.exists(paste0(filename, ".rds"))) {
            return(readRDS(paste0(filename, ".rds")))
          } else {
            stop(paste("Required input file not found:", filename))
          }
        }
        
        # 1. Read user input files
        example_sce <- read_input("example_sce")
        segList_ensemblGeneID <- read_input("segList_ensemblGeneID")
        
        # 2. Construct hierarchical index list
        h_idx_list <- list(level1 = split(seq_len(ncol(example_sce)), example_sce\$batch),
                           level2 = list(seq_len(ncol(example_sce))))
        
        # 3. Construct batch information list
        batch_list <- list(level1 = split(example_sce\$sample, example_sce\$batch),
                           level2 = list(example_sce\$batch))
        
        # 4. Run scMerge2h with specified ruvK for each level
        scMerge2_res <- scMerge2h(exprsMat = logcounts(example_sce),
                                  batch_list = batch_list,
                                  h_idx_list = h_idx_list,
                                  ctl = unlist(segList_ensemblGeneID),
                                  ruvK_list = c(2, 5),
                                  verbose = FALSE)
        
        # 5. Extract the final level adjusted matrix
        assay(example_sce, "scMerge2") <- scMerge2_res[[length(h_idx_list)]]
        
        # 6. Write outputs
        # Save the integrated SingleCellExperiment object
        saveRDS(example_sce, "integrated_example_sce.rds")
        
        # Save the adjusted matrix as a CSV file
        write.csv(as.matrix(assay(example_sce, "scMerge2")), "scMerge2_adjusted_matrix.csv", row.names = TRUE)
        
        # Generate and save PCA plot of the integrated data
        pdf("scMerge2_pca_plot.pdf", width = 7, height = 6)
        set.seed(2022)
        example_sce <- scater::runPCA(example_sce, exprs_values = "scMerge2")
        p <- scater::plotPCA(example_sce, colour_by = "sample", shape_by = "batch")
        print(p)
        dev.off()

    writeLines(c(
        '"BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL":',
        paste0('    scMerge: ', as.character(packageVersion('scMerge')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sc_merge_v2_hierarchical.csv versions.yml
    """
}

workflow BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_sce, segList_ensemblGeneID ] ]

    main:
    BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL(ch_input)

    emit:
    tables   = BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL.out.tables
    plots    = BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL.out.plots
    objects  = BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL.out.objects
    versions = BIOC_SCMERGE_SC_MERGE_V2_HIERARCHICAL.out.versions
}
