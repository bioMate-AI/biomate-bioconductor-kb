#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: circseqaligntk — synthetic_read_generation_and_evaluation
// Generate synthetic circular RNA-Seq reads with custom peak and length distributions, align them, and evaluate workflow accuracy by calculating RMSE against the 
// Input: genome_seq.fa
// Container: quay.io/biocontainers/bioconductor-circseqaligntk:1.12.0--r45hdfd78af_0
// R packages: CircSeqAlignTk, ggplot2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_GENERATION_AND_EVALUATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-circseqaligntk:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("CircSeqAlignTk", "ggplot2")
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
    library(CircSeqAlignTk)
    library(ggplot2)
    
    # Define the working directory and output workspace
    ws <- file.path(getwd(), "circseq_output")
    if (!dir.exists(ws)) {
      dir.create(ws, recursive = TRUE)
    }
    
    # Define the user input file path
    genome_seq <- "genome_seq.fa"
    
    # Verify that the required input file exists
    if (!file.exists(genome_seq)) {
      stop(paste("Required input file '", genome_seq, "' not found in the working directory.", sep = ""))
    }
    
    # --- Generate synthetic reads with custom peaks, lengths, and ---
    # We pass the user-provided genome_seq to avoid using the package's default bundled genome.
    sim <- generate_reads(seq = genome_seq,
                          adapter = NA,
                          mismatch_prob = 0,
                          output = file.path(ws, 'synthetic_reads.fq.gz'))
    
    # --- Build circular-aware index files using build_index() ---
    ref_index <- build_index(input = genome_seq, 
                             output = file.path(ws, 'index'))
    
    # --- Align the synthetic reads using align_reads() ---
    aln <- align_reads(input = file.path(ws, 'synthetic_reads.fq.gz'),
                       index = ref_index, 
                       output = file.path(ws, 'align_results'))
    
    # --- Calculate predicted coverage using calc_coverage() ---
    alncov <- calc_coverage(aln)
    
    # --- Extract true coverage from the simulation object and ---
    fwd_pred <- slot(alncov, 'forward')
    fwd_true <- slot(slot(sim, 'coverage'), 'forward')
    fwd_rmse <- sqrt(sum((fwd_pred - fwd_true) ^ 2) / length(fwd_true))
    
    rev_pred <- slot(alncov, 'reverse')
    rev_true <- slot(slot(sim, 'coverage'), 'reverse')
    rev_rmse <- sqrt(sum((rev_pred - rev_true) ^ 2) / length(rev_true))
    
    # Write named output files for the meaningful results
    # Save RMSE results to a CSV file
    rmse_df <- data.frame(
      Strand = c("Forward", "Reverse"),
      RMSE = c(fwd_rmse, rev_rmse)
    )
    write.csv(rmse_df, file = file.path(ws, "rmse_results.csv"), row.names = FALSE)
    
    # Save the coverage plot as a PDF
    pdf(file = file.path(ws, "coverage_plot.pdf"), width = 8, height = 6)
    print(plot(alncov))
    dev.off()
    
    # Save the simulation and coverage objects as RDS files
    saveRDS(sim, file = file.path(ws, "simulation_object.rds"))
    saveRDS(alncov, file = file.path(ws, "predicted_coverage.rds"))
    
    # Print summary to console
    cat("Workflow completed successfully.\n")
    cat(paste("Forward Strand RMSE:", fwd_rmse, "\n"))
    cat(paste("Reverse Strand RMSE:", rev_rmse, "\n"))
    cat(paste("Outputs saved to directory:", ws, "\n"))

    writeLines(c(
        '"BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_GENERATION_AND_EVALUATION":',
        paste0('        circseqaligntk: ', as.character(packageVersion("circseqaligntk")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_synthetic_read_generation_and_evaluation.csv versions.yml
    """
}

workflow BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_GENERATION_AND_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome_seq.fa ] ]

    main:
    BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_GENERATION_AND_EVALUATION(ch_input)

    emit:
    tables   = BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_GENERATION_AND_EVALUATION.out.tables
    plots    = BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_GENERATION_AND_EVALUATION.out.plots
    objects  = BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_GENERATION_AND_EVALUATION.out.objects
    versions = BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_GENERATION_AND_EVALUATION.out.versions
}
