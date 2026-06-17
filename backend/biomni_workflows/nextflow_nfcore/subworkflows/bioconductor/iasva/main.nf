#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iasva — hidden_heterogeneity_detection
// Detect hidden sources of variation in single-cell or bulk RNA-Seq data, identify marker genes associated with these sources, and optimize parameters.
// Input: counts, anns
// Container: quay.io/biocontainers/bioconductor-iasva:1.28.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DescTools, RColorBrewer, Rtsne, SummarizedExperiment, corrplot, iasva, irlba, pheatmap, sva
// Visualizations: heatmap, bar plot, t-SNE plot
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate geometric library size as a known covariate
//  * 2. [Input & Preparation] Construct the model matrix of known factors
//  * 3. [Visualization & Output] Create a SummarizedExperiment object from the counts
//  * 4. [Core Analysis] Run IA-SVA (using iasva or fast_iasva) to detect surrogate variables
//  * 5. [Core Analysis] Find marker genes associated with the detected surrogate variables using find_markers
//  * 6. [Core Analysis] Tune the R-squared threshold using study_R2

nextflow.enable.dsl = 2

process BIOC_IASVA_HIDDEN_HETEROGENEITY_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("irlba", "iasva", "sva", "Rtsne", "pheatmap", "corrplot", "DescTools", "RColorBrewer", "SummarizedExperiment")
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
        library(irlba) 
        library(iasva)
        library(sva)
        library(Rtsne)
        library(pheatmap)
        library(corrplot)
        library(DescTools)
        library(RColorBrewer)
        
        # Set seed for reproducibility
        set.seed(100)
        color.vec <- brewer.pal(3, "Set1")
        
        # ==========================================
        # 1. READ USER INPUT FILES
        # ==========================================
        
        # Read counts file
        if (file.exists("counts.rds")) {
          counts <- readRDS("counts.rds")
        } else if (file.exists("counts.csv")) {
          counts <- as.matrix(read.csv("counts.csv", row.names = 1))
        } else if (file.exists("counts.tsv")) {
          counts <- as.matrix(read.delim("counts.tsv", row.names = 1))
        } else if (file.exists("counts")) {
          counts <- tryCatch(readRDS("counts"), error = function(e) {
            tryCatch(as.matrix(read.table("counts", header = TRUE, row.names = 1)), error = function(e2) {
              stop("Could not read 'counts' file. Please provide counts.rds, counts.csv, counts.tsv, or counts.")
            })
          })
        } else {
          stop("Required input file 'counts' (or counts.rds/csv/tsv) not found in the working directory.")
        }
        
        # Read anns file
        if (file.exists("anns.rds")) {
          anns <- readRDS("anns.rds")
        } else if (file.exists("anns.csv")) {
          anns <- read.csv("anns.csv", row.names = 1)
        } else if (file.exists("anns.tsv")) {
          anns <- read.delim("anns.tsv", row.names = 1)
        } else if (file.exists("anns")) {
          anns <- tryCatch(readRDS("anns"), error = function(e) {
            tryCatch(read.table("anns", header = TRUE, row.names = 1), error = function(e2) {
              stop("Could not read 'anns' file. Please provide anns.rds, anns.csv, anns.tsv, or anns.")
            })
          })
        } else {
          stop("Required input file 'anns' (or anns.rds/csv/tsv) not found in the working directory.")
        }
        
        # ==========================================
        # 2. COVARIATE CALCULATION & MODEL SETUP
        # ==========================================
        
        # Calculate geometric library size
        geo_lib_size <- colSums(log(counts + 1))
        
        # Save geometric library size plot
        pdf("geometric_library_size.pdf", width = 7, height = 4)
        barplot(geo_lib_size, xlab = "Cell", ylab = "Geometric Lib Size", las = 2)
        dev.off()
        
        lcounts <- log(counts + 1)
        
        # PC1 and Geometric library size correlation
        pc1 <- irlba(lcounts - rowMeans(lcounts), 1)\$v[, 1]
        cat("Correlation between PC1 and Geometric Library Size:\n")
        print(cor(geo_lib_size, pc1))
        
        # Construct model matrix of known factors
        if ("Patient_ID" %in% colnames(anns)) {
          known_factor <- anns\$Patient_ID
        } else if (ncol(anns) > 0) {
          known_factor <- anns[, 1]
        } else {
          known_factor <- rep(1, ncol(counts))
        }
        mod <- model.matrix(~known_factor + geo_lib_size)
        
        # Create a SummarizedExperiment object
        summ_exp <- SummarizedExperiment(assays = counts)
        
        # ==========================================
        # 3. RUN IA-SVA TO DETECT SURROGATE VARIABLES
        # ==========================================
        
        # Run standard IA-SVA
        iasva.res <- iasva(summ_exp, mod[, -1, drop = FALSE], verbose = FALSE, 
                           permute = FALSE, num.sv = 5)
        iasva.sv <- iasva.res\$sv
        
        cat("Correlation between Geometric Library Size and SV1:\n")
        print(cor(geo_lib_size, iasva.sv[, 1]))
        
        # Generate diagnostic plots for IA-SVA
        pdf("iasva_plots.pdf", width = 7, height = 7)
        plot(iasva.sv[, 1], iasva.sv[, 2], xlab = "SV1", ylab = "SV2")
        
        if (length(unique(iasva.sv[, 1])) >= 2) {
          cell_type <- as.factor(kmeans(iasva.sv[, 1], centers = 2)\$cluster)
          levels(cell_type) <- c("Cell1", "Cell2")
        } else {
          cell_type <- as.factor(rep("Cell1", nrow(iasva.sv)))
        }
        
        pairs(iasva.sv, main = "IA-SVA", pch = 21, col = color.vec[cell_type],
              bg = color.vec[cell_type], oma = c(4,4,6,12))
        legend("right", legend = levels(cell_type), fill = color.vec, bty = "n")
        
        plot(iasva.sv[, 1:2], main = "IA-SVA", pch = 21, xlab = "SV1", ylab = "SV2",
             col = color.vec[cell_type], bg = color.vec[cell_type])
        
        corrplot(cor(iasva.sv))
        dev.off()
        
        # ==========================================
        # 4. FIND MARKER GENES
        # ==========================================
        
        # Find marker genes associated with SV1
        marker.counts <- find_markers(summ_exp, as.matrix(iasva.sv[, 1]))
        cat("Number of marker genes identified:\n")
        if (is.null(marker.counts)) {
          print(0)
        } else {
          print(nrow(marker.counts))
        }
        
        if (!is.null(marker.counts) && nrow(marker.counts) > 0) {
          # Save marker gene heatmap
          pdf("marker_heatmap.pdf", width = 7, height = 10)
          anno.col <- data.frame(cell_type = cell_type)
          rownames(anno.col) <- colnames(marker.counts)
          pheatmap(log(marker.counts + 1), show_colnames = FALSE,
                   clustering_method = "ward.D2", cutree_cols = 2,
                   annotation_col = anno.col)
          dev.off()
        } else {
          cat("No marker genes found, skipping heatmap.\n")
        }
        
        # ==========================================
        # 5. RUN TSNE COMPARISONS
        # ==========================================
        
        pdf("tsne_plots.pdf", width = 7, height = 7)
        # tSNE on all genes
        set.seed(100)
        perp_all <- max(1, min(30, floor((ncol(lcounts) - 1) / 3)))
        tsne.res <- Rtsne(t(lcounts), dims = 2, perplexity = perp_all)
        plot(tsne.res\$Y, main = "tSNE", xlab = "tSNE Dim1", ylab = "tSNE Dim2",
             pch = 21, col = color.vec[cell_type], bg = color.vec[cell_type],
             oma = c(4, 4, 6, 12))
        legend("bottomright", legend = levels(cell_type), fill = color.vec, bty = "n")
        
        # tSNE post IA-SVA (on marker genes)
        if (!is.null(marker.counts) && nrow(marker.counts) > 0) {
          set.seed(100)
          post_data <- unique(t(log(marker.counts + 1)))
          perp_post <- max(1, min(30, floor((nrow(post_data) - 1) / 3)))
          tsne.res.post <- Rtsne(post_data, dims = 2, perplexity = perp_post)
          plot(tsne.res.post\$Y, main = "tSNE post IA-SVA", xlab = "tSNE Dim1",
               ylab = "tSNE Dim2", pch = 21, col = color.vec[cell_type],
               bg = color.vec[cell_type], oma = c(4, 4, 6, 12))
          legend("bottomright", legend = levels(cell_type), fill = color.vec, bty = "n")
        } else {
          cat("No marker genes found, skipping post IA-SVA tSNE.\n")
        }
        dev.off()
        
        # ==========================================
        # 6. FAST IA-SVA & PARAMETER TUNING
        # ==========================================
        
        # Run faster implementation of IA-SVA
        iasva.res.fast <- fast_iasva(summ_exp, mod[, -1, drop = FALSE], num.sv = 5)
        
        # Tune R-squared threshold and save the diagnostic plot
        pdf("study_R2_plot.pdf", width = 7, height = 7)
        study_res <- study_R2(summ_exp, iasva.sv)
        dev.off()
        
        # ==========================================
        # 7. SAVE OUTPUT FILES
        # ==========================================
        
        write.csv(iasva.sv, "iasva_surrogate_variables.csv", row.names = TRUE)
        if (!is.null(marker.counts)) {
          write.csv(marker.counts, "marker_gene_counts.csv", row.names = TRUE)
        }
        saveRDS(iasva.res, "iasva_results.rds")
        saveRDS(iasva.res.fast, "fast_iasva_results.rds")
        saveRDS(study_res, "study_R2_results.rds")
        
        cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_IASVA_HIDDEN_HETEROGENEITY_DETECTION":',
        paste0('    iasva: ', as.character(packageVersion('iasva')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hidden_heterogeneity_detection.csv versions.yml
    """
}

workflow BIOC_IASVA_HIDDEN_HETEROGENEITY_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts, anns ] ]

    main:
    BIOC_IASVA_HIDDEN_HETEROGENEITY_DETECTION(ch_input)

    emit:
    tables   = BIOC_IASVA_HIDDEN_HETEROGENEITY_DETECTION.out.tables
    plots    = BIOC_IASVA_HIDDEN_HETEROGENEITY_DETECTION.out.plots
    objects  = BIOC_IASVA_HIDDEN_HETEROGENEITY_DETECTION.out.objects
    versions = BIOC_IASVA_HIDDEN_HETEROGENEITY_DETECTION.out.versions
}
