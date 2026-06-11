#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CircSeqAlignTk — synthetic_read_simulation_and_evaluation
// Generate synthetic circular RNA-Seq reads with custom coverage peaks, lengths, and mismatches, and evaluate alignment accuracy by calculating RMSE against true 
// Input: FR851463.fa
// Container: quay.io/biocontainers/bioconductor-circseqaligntk:1.12.0--r45hdfd78af_0
// R packages: CircSeqAlignTk
// Bioconductor: 3.20 | R: 4.4
// Requires: CircSeqAlignTk
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate synthetic reads
//  * 2. [Input & Preparation] Build index and align simulated reads
//  * 3. [Core Analysis] Calculate predicted coverage
//  * 4. [Core Analysis] Compare predicted coverage to true simulated coverage by calculating Root Mean Squared Error (RMSE)

nextflow.enable.dsl = 2

process BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_SIMULATION_AND_EVALUATION {
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
    .bm_deps <- c("CircSeqAlignTk")
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
    library(CircSeqAlignTk)
    
    # Define workspace directory
    ws <- "workspace"
    if (!dir.exists(ws)) {
      dir.create(ws, recursive = TRUE)
    }
    
    # Read the user-provided circular genome sequence from the working directory
    genome_seq <- 'FR851463.fa'
    
    # Define custom coverage peaks
    peaks <- data.frame(
      mean = c(0, 25, 70, 90, 150, 240, 260, 270, 330, 350),
      std = c(5, 5, 5, 5, 10, 5, 5, 1, 2, 1),
      strand = c('+', '+', '-', '-', '+', '+', '-', '+', '+', '-'),
      prob = c(0.10, 0.10, 0.18, 0.05, 0.03, 0.18, 0.15, 0.10, 0.06, 0.05)
    )
    
    # Define custom sRNA lengths
    srna_length <- data.frame(
      length = c(21, 22, 23, 24),
      prob = c(0.45, 0.40, 0.10, 0.05)
    )
    
    # 1. Generate synthetic reads
    sim <- generate_reads(seq = genome_seq,
                          adapter = NA,
                          mismatch_prob = 0.05,
                          srna_length = srna_length,
                          peaks = peaks,
                          output = file.path(ws, 'synthetic_reads.fq.gz'))
    
    # 2. Build index and align simulated reads
    ref_index <- build_index(input = genome_seq, 
                             output = file.path(ws, 'index'))
    
    aln <- align_reads(input = file.path(ws, 'synthetic_reads.fq.gz'),
                       index = ref_index, 
                       output = file.path(ws, 'align_results'))
    
    # 3. Calculate predicted coverage
    alncov <- calc_coverage(aln)
    
    # 4. Compare predicted coverage to true simulated coverage by calculating RMSE
    # coverage of reads in forward strand
    fwd_pred <- slot(alncov, 'forward')
    fwd_true <- slot(slot(sim, 'coverage'), 'forward')
    fwd_rmse <- sqrt(sum((fwd_pred - fwd_true) ^ 2) / length(fwd_true))
    
    # coverage of reads in reverse strand
    rev_pred <- slot(alncov, 'reverse')
    rev_true <- slot(slot(sim, 'coverage'), 'reverse')
    rev_rmse <- sqrt(sum((rev_pred - rev_true) ^ 2) / length(rev_true))
    
    # Save RMSE results to a CSV file
    rmse_df <- data.frame(
      Strand = c("Forward", "Reverse"),
      RMSE = c(fwd_rmse, rev_rmse)
    )
    write.csv(rmse_df, file = "rmse_evaluation_results.csv", row.names = FALSE)
    
    # Save the coverage visualization as a PDF plot
    pdf("coverage_comparison_plot.pdf", width = 8, height = 6)
    plot(alncov)
    dev.off()
    
    # Save key R objects for downstream analysis
    saveRDS(sim, file = "simulated_reads_object.rds")
    saveRDS(alncov, file = "calculated_coverage_object.rds")

    writeLines(c(
        '"BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_SIMULATION_AND_EVALUATION":',
        paste0('    CircSeqAlignTk: ', as.character(packageVersion('CircSeqAlignTk')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_synthetic_read_simulation_and_evaluation.csv versions.yml
    """
}

workflow BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_SIMULATION_AND_EVALUATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ FR851463.fa ] ]

    main:
    BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_SIMULATION_AND_EVALUATION(ch_input)

    emit:
    tables   = BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_SIMULATION_AND_EVALUATION.out.tables
    plots    = BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_SIMULATION_AND_EVALUATION.out.plots
    objects  = BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_SIMULATION_AND_EVALUATION.out.objects
    versions = BIOC_CIRCSEQALIGNTK_SYNTHETIC_READ_SIMULATION_AND_EVALUATION.out.versions
}
