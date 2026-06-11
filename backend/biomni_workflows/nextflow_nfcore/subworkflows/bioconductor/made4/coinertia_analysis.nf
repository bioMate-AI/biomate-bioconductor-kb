#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: made4 — coinertia_analysis
// Perform Joint Dimension Reduction (Coinertia Analysis) of two simulated subsets of expression data to identify global co-structures and platform/pathway similar
// Input: counts.csv, coldata.csv
// Container: 1.84.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ade4, made4
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MADE4_COINERTIA_ANALYSIS {
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
    
    # Load required libraries
    library(made4)
    library(ade4)
    
    # ---------------------------------------------------------
    # --- Load and Preprocess Data ---
    # ---------------------------------------------------------
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) == 0) {
        stop("Error: No matching samples found between counts.csv and coldata.csv")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    classvec <- as.factor(coldata\$condition)
    
    # Convert to data frame
    counts_df <- made4::asDataFrame(counts)
    
    # ---------------------------------------------------------
    # --- Split Dataset to Simulate Two Platforms/Assays ---
    # ---------------------------------------------------------
    # To demonstrate Coinertia Analysis (CIA), we split the gene expression matrix 
    # into two distinct subsets of genes (e.g., odd and even rows) representing 
    # two different pathways or profiling platforms on the same samples.
    n_genes <- nrow(counts_df)
    if (n_genes >= 10) {
        half <- floor(n_genes / 2)
        df1 <- counts_df[1:half, ]
        df2 <- counts_df[(half + 1):n_genes, ]
    } else {
        # Fallback with simulated noise if there are too few genes
        df1 <- counts_df
        df2 <- counts_df + rnorm(prod(dim(counts_df)), mean = 0, sd = 0.1)
    }
    
    # ---------------------------------------------------------
    # --- Coinertia Analysis (CIA) ---
    # ---------------------------------------------------------
    # Run CIA to find co-structure between the two datasets
    coin <- made4::cia(df1, df2)
    
    # Save global similarity metrics (RV coefficient)
    rv_val <- coin\$coinertia\$RV
    cia_summary <- data.frame(
        Metric = "RV_Coefficient",
        Value = rv_val
    )
    write.csv(cia_summary, "cia_results.csv", row.names = FALSE)
    
    # ---------------------------------------------------------
    # --- Visualization ---
    # ---------------------------------------------------------
    pdf("cia_plot.pdf", width = 10, height = 8)
    tryCatch({
        plot(coin, classvec = classvec, clab = 0, cpoint = 3)
    }, error = function(e) {
        warning("CIA plot failed: ", e\$message)
        plot.new()
        text(0.5, 0.5, "CIA Plot Failed", cex = 1.5)
    })
    dev.off()
    
    message("Coinertia Analysis pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MADE4_COINERTIA_ANALYSIS":',
        paste0('    made4: ', as.character(packageVersion('made4')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_coinertia_analysis.csv versions.yml
    """
}

workflow BIOC_MADE4_COINERTIA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MADE4_COINERTIA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MADE4_COINERTIA_ANALYSIS.out.tables
    plots    = BIOC_MADE4_COINERTIA_ANALYSIS.out.plots
    objects  = BIOC_MADE4_COINERTIA_ANALYSIS.out.objects
    versions = BIOC_MADE4_COINERTIA_ANALYSIS.out.versions
}
