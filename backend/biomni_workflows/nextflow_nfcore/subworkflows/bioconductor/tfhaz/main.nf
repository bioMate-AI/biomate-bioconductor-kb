#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TFHAZ — tfhaz_analysis
// Find and analyze transcription factor high accumulation DNA zones from genomic coordinates of TF binding regions.
// Input: tf_regions.GRanges
// Container: quay.io/biocontainers/bioconductor-tfhaz:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, TFHAZ
// Visualizations: PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate TF accumulation along the chromosome bases using accumulation
//  * 2. [Visualization & Output] Plot the accumulation vector using plot_accumulation
//  * 3. [Core Analysis] Find dense DNA zones across multiple thresholds using dense_zones
//  * 4. [Visualization & Output] Plot the number of dense zones across thresholds using plot_n_zones
//  * 5. [Core Analysis] Analyze the effect of window size w using w_analysis
//  * 6. [Core Analysis] Perform PCA on different accumulation types using n_zones_PCA
//  * 7. [Core Analysis] Identify final high accumulation zones (TFHAZ) using high_accumulation_zones

nextflow.enable.dsl = 2

process BIOC_TFHAZ_TFHAZ_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("TFHAZ", "GenomicRanges")
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
        library(TFHAZ)
        library(GenomicRanges)
        
        # Read user input
        Ishikawa <- readRDS("tf_regions.GRanges")
        
        # Standardize metadata column name to "TF" if needed
        if (!"TF" %in% colnames(mcols(Ishikawa))) {
          if (ncol(mcols(Ishikawa)) >= 1) {
            colnames(mcols(Ishikawa))[1] <- "TF"
          } else {
            stop("Input GRanges object must contain at least one metadata column with TF names.")
          }
        }
        
        # Print dimensions and head
        print(dim(as.data.frame(Ishikawa)))
        print(head(Ishikawa))
        
        # Dynamically select the first chromosome in use
        chr_use <- seqlevelsInUse(Ishikawa)[1]
        
        # 1. Calculate TF accumulation along the chromosome bases using accumulation
        TF_acc_21_w_0 <- accumulation(Ishikawa, "TF", chr_use, 0)
        TF_acc_w_0 <- TF_acc_21_w_0
        
        # 2. Plot the accumulation vector using plot_accumulation
        # This function automatically saves the plot to a .png file
        plot_accumulation(TF_acc_21_w_0)
        
        # 3. Find dense DNA zones across multiple thresholds using dense_zones
        TF_dense_21_w_0 <- dense_zones(TF_acc_w_0, 1, chr = chr_use)
        print(TF_dense_21_w_0)
        TF_dense_w_0 <- TF_dense_21_w_0
        
        # 4. Plot the number of dense zones across thresholds using plot_n_zones
        pdf("plot_n_zones.pdf")
        plot_n_zones(TF_dense_w_0, chr = chr_use)
        dev.off()
        
        # 5. Analyze the effect of window size w using w_analysis
        # We need to compute the dense zones for w = 10, 100, 1000, 10000
        TF_acc_w_10 <- accumulation(Ishikawa, "TF", chr_use, 10)
        TF_dense_w_10 <- dense_zones(TF_acc_w_10, 1, chr = chr_use)
        
        TF_acc_w_100 <- accumulation(Ishikawa, "TF", chr_use, 100)
        TF_dense_w_100 <- dense_zones(TF_acc_w_100, 1, chr = chr_use)
        
        TF_acc_w_1000 <- accumulation(Ishikawa, "TF", chr_use, 1000)
        TF_dense_w_1000 <- dense_zones(TF_acc_w_1000, 1, chr = chr_use)
        
        TF_acc_w_10000 <- accumulation(Ishikawa, "TF", chr_use, 10000)
        TF_dense_w_10000 <- dense_zones(TF_acc_w_10000, 1, chr = chr_use)
        
        l <- list(TF_dense_w_10, TF_dense_w_100, TF_dense_w_1000, TF_dense_w_10000)
        
        pdf("w_analysis.pdf")
        w_analysis(l, chr = chr_use)
        dev.off()
        
        # 6. Perform PCA on different accumulation types using n_zones_PCA
        # We need reg_dense_w_10 and base_dense_w_10
        reg_acc_w_10 <- accumulation(Ishikawa, "region", chr_use, 10)
        base_acc_w_10 <- accumulation(Ishikawa, "base", chr_use, 10)
        
        # Calculate dynamic threshold steps to ensure identical number of thresholds for PCA
        N <- nrow(TF_dense_w_10\$zones_count[[chr_use]])
        
        max_reg <- max(reg_acc_w_10\$accvector)
        step_reg <- if (N > 1 && max_reg > 1) (max_reg - 1) / (N - 1) else max_reg
        reg_dense_w_10 <- dense_zones(reg_acc_w_10, step_reg, chr = chr_use)
        
        max_base <- max(base_acc_w_10\$accvector)
        step_base <- if (N > 1 && max_base > 1) (max_base - 1) / (N - 1) else max_base
        base_dense_w_10 <- dense_zones(base_acc_w_10, step_base, chr = chr_use)
        
        pdf("n_zones_PCA.pdf")
        pca_results <- n_zones_PCA(TF_dense_w_10, reg_dense_w_10, base_dense_w_10, chr = chr_use)
        dev.off()
        
        # 7. Identify final high accumulation zones (TFHAZ) using high_accumulation_zones
        TF_acc_21_w_0 <- accumulation(Ishikawa, "TF", chr_use, 0)
        TFHAZ_21_w_0 <- high_accumulation_zones(TF_acc_21_w_0, method = "overlaps", threshold = "std")
        print(TFHAZ_21_w_0)
        
        # Save outputs
        saveRDS(TF_acc_21_w_0, "TF_acc_21_w_0.rds")
        saveRDS(TF_dense_21_w_0, "TF_dense_21_w_0.rds")
        saveRDS(TFHAZ_21_w_0, "TFHAZ_21_w_0.rds")
        saveRDS(pca_results, "pca_results.rds")
        
        write.csv(as.data.frame(TFHAZ_21_w_0\$zones), "TFHAZ_high_accumulation_zones.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_TFHAZ_TFHAZ_ANALYSIS":',
        paste0('    TFHAZ: ', as.character(packageVersion('TFHAZ')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tfhaz_analysis.csv versions.yml
    """
}

workflow BIOC_TFHAZ_TFHAZ_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tf_regions.GRanges ] ]

    main:
    BIOC_TFHAZ_TFHAZ_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TFHAZ_TFHAZ_ANALYSIS.out.tables
    plots    = BIOC_TFHAZ_TFHAZ_ANALYSIS.out.plots
    objects  = BIOC_TFHAZ_TFHAZ_ANALYSIS.out.objects
    versions = BIOC_TFHAZ_TFHAZ_ANALYSIS.out.versions
}
