#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PrInCE — detect_complexes_workflow
// Identify known protein complexes that show statistically significant co-elution in a proteomics dataset using a permutation-based approach.
// Input: co_elution_matrix.csv, gold_standard_complexes.rds
// Container: quay.io/biocontainers/bioconductor-prince:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PrInCE
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] CSV table of Z-scores
//  * 2. [Core Analysis] RDS object of Z-scores
//  * 3. [Core Analysis] PDF plot of Z-scores distribution

nextflow.enable.dsl = 2

process BIOC_PRINCE_DETECT_COMPLEXES_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("PrInCE")
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
    library(PrInCE)
    
    # Verify input files exist
    if (!file.exists("co_elution_matrix.csv")) {
      stop("Error: co_elution_matrix.csv not found in the working directory.")
    }
    if (!file.exists("gold_standard_complexes.rds")) {
      stop("Error: gold_standard_complexes.rds not found in the working directory.")
    }
    
    # Read user input files
    scott <- as.matrix(read.csv("co_elution_matrix.csv", row.names = 1, check.names = FALSE))
    gold_standard <- readRDS("gold_standard_complexes.rds")
    
    # Analyze cleaned profiles
    filtered = filter_profiles(scott)
    chromatograms = clean_profiles(filtered)
    
    # Detect significantly co-eluting complexes
    set.seed(0)
    z_scores = detect_complexes(chromatograms, gold_standard)
    
    # Remove complexes that could not be analyzed
    z_scores = na.omit(z_scores)
    
    # Print summary statistics to standard output
    cat("How many could be tested?\n")
    print(length(z_scores))
    
    cat("\nHow many were significant at uncorrected, two-tailed p < 0.05?\n")
    print(sum(z_scores > 1.96))
    
    cat("\nPrint the top complexes:\n")
    print(head(sort(z_scores, decreasing = TRUE)))
    
    # Write outputs
    # --- CSV table of Z-scores ---
    z_scores_df <- data.frame(
      Complex = names(z_scores),
      Z_Score = as.numeric(z_scores),
      stringsAsFactors = FALSE
    )
    write.csv(z_scores_df, "z_scores_results.csv", row.names = FALSE)
    
    # --- RDS object of Z-scores ---
    saveRDS(z_scores, "z_scores_results.rds")
    
    # --- PDF plot of Z-scores distribution ---
    pdf("z_scores_distribution.pdf", width = 7, height = 5)
    hist(z_scores, 
         breaks = 20, 
         col = "skyblue", 
         border = "white",
         main = "Distribution of Complex Co-elution Z-Scores", 
         xlab = "Z-Score")
    abline(v = 1.96, col = "red", lty = 2, lwd = 2)
    legend("topright", legend = "Z = 1.96 (p < 0.05)", col = "red", lty = 2, lwd = 2)
    dev.off()

    writeLines(c(
        '"BIOC_PRINCE_DETECT_COMPLEXES_WORKFLOW":',
        paste0('    PrInCE: ', as.character(packageVersion('PrInCE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detect_complexes_workflow.csv versions.yml
    """
}

workflow BIOC_PRINCE_DETECT_COMPLEXES_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ co_elution_matrix.csv, gold_standard_complexes.rds ] ]

    main:
    BIOC_PRINCE_DETECT_COMPLEXES_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_PRINCE_DETECT_COMPLEXES_WORKFLOW.out.tables
    plots    = BIOC_PRINCE_DETECT_COMPLEXES_WORKFLOW.out.plots
    objects  = BIOC_PRINCE_DETECT_COMPLEXES_WORKFLOW.out.objects
    versions = BIOC_PRINCE_DETECT_COMPLEXES_WORKFLOW.out.versions
}
