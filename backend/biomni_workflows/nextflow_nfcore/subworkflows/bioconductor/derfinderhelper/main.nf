#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: derfinderHelper — derfinder_helper_fstats
// Calculate genome-wide F-statistics and p-values comparing nested models for RNA-seq count data using derfinderHelper to accelerate the computation.
// Input: counts.csv, coldata.csv
// Container: 1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: IRanges, S4Vectors, derfinderHelper
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Stage 1: Load required libraries
    suppressPackageStartupMessages({
        library(S4Vectors)
        library(derfinderHelper)
    })
    
    # Stage 2: Read and preprocess input data
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
        stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Ensure sample alignment between counts and metadata
    common_samples <- intersect(coldata\$sample, colnames(counts))
    if (length(common_samples) == 0) {
        stop("No matching samples found between 'counts.csv' and 'coldata.csv'.")
    }
    
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), , drop = FALSE]
    
    # Filter out low-expression genes to improve statistical power
    keep <- rowSums(counts > 5) >= (ncol(counts) / 2)
    counts_filtered <- counts[keep, , drop = FALSE]
    
    if (nrow(counts_filtered) == 0) {
        warning("No genes passed the filtering criteria. Proceeding with unfiltered data.")
        counts_filtered <- counts
    }
    
    # Stage 3: Prepare data structure for derfinderHelper
    # derfinderHelper expects a DataFrame of Rle objects for memory efficiency
    rle_list <- lapply(seq_len(ncol(counts_filtered)), function(i) {
        Rle(as.numeric(counts_filtered[[i]]))
    })
    names(rle_list) <- colnames(counts_filtered)
    toyData <- DataFrame(rle_list)
    
    # Stage 4: Build nested model matrices
    # We adjust for sample depth (library size) as a covariate
    sampleDepth <- colSums(counts_filtered)
    condition <- factor(coldata\$condition)
    
    # Alternative model (includes condition of interest)
    mod <- model.matrix(~ sampleDepth + condition)
    # Null model (nested, excludes condition of interest)
    mod0 <- model.matrix(~ sampleDepth)
    
    # Stage 5: Calculate F-statistics using derfinderHelper
    # Using 'Matrix' method as recommended for optimal speed and memory usage
    fstats_rle <- fstats.apply(
        data = toyData, 
        mod = mod, 
        mod0 = mod0, 
        scalefac = 1, 
        method = "Matrix"
    )
    
    # Convert Run-Length Encoded (Rle) F-statistics back to numeric vector
    f_values <- as.numeric(fstats_rle)
    
    # Stage 6: Compute statistical significance (p-values)
    df1 <- ncol(mod) - ncol(mod0)
    df2 <- nrow(mod) - ncol(mod)
    
    p_values <- pf(f_values, df1, df2, lower.tail = FALSE)
    adj_p_values <- p.adjust(p_values, method = "BH")
    
    # Stage 7: Export results and diagnostic plots
    results <- data.frame(
        gene_id = rownames(counts_filtered),
        f_statistic = f_values,
        p_value = p_values,
        adj_p_value = adj_p_values,
        stringsAsFactors = FALSE
    )
    
    write.csv(results, "fstats_results.csv", row.names = FALSE)
    
    # Generate diagnostic plot
    pdf("fstats_distribution.pdf", width = 7, height = 5)
    hist(
        p_values, 
        breaks = 50, 
        col = "skyblue", 
        border = "white",
        main = "P-value Distribution (F-test)", 
        xlab = "p-value",
        ylab = "Frequency"
    )
    dev.off()
    
    cat("Analysis complete. Results written to 'fstats_results.csv' and 'fstats_distribution.pdf'.\n")

    writeLines(c(
        '"BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS":',
        paste0('    derfinderHelper: ', as.character(packageVersion('derfinderHelper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_derfinder_helper_fstats.csv versions.yml
    """
}

workflow BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS(ch_input)

    emit:
    tables   = BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS.out.tables
    plots    = BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS.out.plots
    objects  = BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS.out.objects
    versions = BIOC_DERFINDERHELPER_DERFINDER_HELPER_FSTATS.out.versions
}
