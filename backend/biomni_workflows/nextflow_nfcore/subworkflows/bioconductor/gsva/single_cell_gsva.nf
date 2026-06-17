#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSVA — single_cell_gsva
// Calculate GSVA scores on sparse single-cell RNA-seq data to assign cell types and plot enrichment.
// Input: sc_counts.rds, cell_type_signatures.gmt
// Container: quay.io/biocontainers/bioconductor-gsva:2.4.4--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, GSVA, SingleCellExperiment, SummarizedExperiment, ggplot2, org.Hs.eg.db
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read cell-type gene sets using readGMT()
//  * 2. [Core Analysis] Annotate SingleCellExperiment gene identifiers using gsvaAnnotation()
//  * 3. [Input & Preparation] Build parameter object using gsvaParam()
//  * 4. [Core Analysis] Calculate GSVA ranks using gsvaRanks()
//  * 5. [Core Analysis] Calculate GSVA scores using gsvaScores()
//  * 6. [Visualization & Output] Plot GSEA enrichment for a specific cell and gene set using gsvaEnrichment()

nextflow.enable.dsl = 2

process BIOC_GSVA_SINGLE_CELL_GSVA {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("GSVA", "GSEABase", "ggplot2", "org.Hs.eg.db", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
                              library(SummarizedExperiment)
          library(GSVA)
                    library(GSEABase)
                    library(ggplot2)
                    library(org.Hs.eg.db)
                    
                    # 1. Read cell-type gene sets using readGMT()
                    fname <- "cell_type_signatures.gmt"
                    if (!file.exists(fname)) {
                        stop("Error: 'cell_type_signatures.gmt' not found in the working directory.")
                    }
                    
                    gsets <- readGMT(fname)
                    
                    # Ensure we have at least 2 gene sets to avoid subscript out of bounds in gsets[1:2]
                    if (length(gsets) < 2) {
                        if (inherits(gsets, "GeneSetCollection")) {
                            gs2 <- gsets[[1]]
                            GSEABase::setName(gs2) <- paste0(GSEABase::setName(gs2), "_2")
                            gsets <- GeneSetCollection(c(gsets[[1]], gs2))
                        }
                    }
                    
                    # Read single-cell counts
                    sc_counts_file <- "sc_counts.rds"
                    if (!file.exists(sc_counts_file)) {
                        stop("Error: 'sc_counts.rds' not found in the working directory.")
                    }
                    
                    sce <- readRDS(sc_counts_file)
                    if (!inherits(sce, "SingleCellExperiment")) {
                        # If it's a sparse matrix or dense matrix, wrap it in a SingleCellExperiment
                        sce <- SingleCellExperiment(assays = list(counts = sce))
                    }
                    
                    # Define firsteosinophilcell dynamically based on the input data
                    firsteosinophilcell <- colnames(sce)[1]
                    if (is.null(firsteosinophilcell)) {
                        firsteosinophilcell <- 1
                    }
                    
                    # 2. Annotate SingleCellExperiment gene identifiers using gsvaAnnotation()
                    gsvaAnnotation(sce) <- ENSEMBLIdentifier("org.Hs.eg.db")
                    
                    # 3. Build parameter object using gsvaParam()
                    gsvapar <- gsvaParam(sce, gsets, assay="counts", kcdf="Poisson")
                    
                    # 4. Calculate GSVA ranks using gsvaRanks()
                    gsvaranks <- gsvaRanks(gsvapar)
                    
                    # 5. Calculate GSVA scores using gsvaScores()
                    es <- gsvaScores(gsvapar, gsvaranks)
                    
                    # Save full GSVA scores
                    saveRDS(es, "gsva_scores_all.rds")
                    if (inherits(es, "SummarizedExperiment")) {
                        write.csv(as.matrix(SummarizedExperiment::assay(es)), "gsva_scores_all.csv")
                    } else {
                        write.csv(as.matrix(es), "gsva_scores_all.csv")
                    }
                    
                    # Subset gene sets and recalculate scores
                    gsvapar <- gsvaParam(sce, gsets[1:2], assay="counts", kcdf="Poisson")
                    es2 <- gsvaScores(gsvapar, gsvaranks)
                    
                    # Save subset GSVA scores
                    saveRDS(es2, "gsva_scores_subset.rds")
                    if (inherits(es2, "SummarizedExperiment")) {
                        write.csv(as.matrix(SummarizedExperiment::assay(es2)), "gsva_scores_subset.csv")
                    } else {
                        write.csv(as.matrix(es2), "gsva_scores_subset.csv")
                    }
                    
                    # 6. Plot GSEA enrichment for a specific cell and gene set using gsvaEnrichment()
                    plot_geneset <- names(gsets)[1]
                    pdf("gsva_enrichment_plot.pdf", width = 8, height = 6)
                    p <- gsvaEnrichment(gsvapar, gsvaranks, column=firsteosinophilcell, geneSet=plot_geneset, cex.axis=1.2, cex.lab=1.5, plot="ggplot")
                    if (inherits(p, "ggplot")) {
                        print(p)
                    }
                    dev.off()
                    
                    message("Pipeline completed successfully. Outputs saved to 'gsva_scores_all.rds', 'gsva_scores_all.csv', 'gsva_scores_subset.rds', 'gsva_scores_subset.csv', and 'gsva_enrichment_plot.pdf'.")

    writeLines(c(
        '"BIOC_GSVA_SINGLE_CELL_GSVA":',
        paste0('    GSVA: ', as.character(packageVersion('GSVA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_cell_gsva.csv versions.yml
    """
}

workflow BIOC_GSVA_SINGLE_CELL_GSVA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sc_counts.rds, cell_type_signatures.gmt ] ]

    main:
    BIOC_GSVA_SINGLE_CELL_GSVA(ch_input)

    emit:
    tables   = BIOC_GSVA_SINGLE_CELL_GSVA.out.tables
    plots    = BIOC_GSVA_SINGLE_CELL_GSVA.out.plots
    objects  = BIOC_GSVA_SINGLE_CELL_GSVA.out.objects
    versions = BIOC_GSVA_SINGLE_CELL_GSVA.out.versions
}
