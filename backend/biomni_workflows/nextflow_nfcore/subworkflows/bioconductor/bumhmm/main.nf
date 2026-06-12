#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BUMHMM — bumhmm_structure_probing_analysis
// Compute per-nucleotide posterior probabilities of RNA modification from multi-replicate structure probing data.
// Input: se, sequence
// Container: quay.io/biocontainers/bioconductor-bumhmm:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BUMHMM, Biostrings, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Select nucleotide positions for pairwise comparisons using selectNuclPos
//  * 2. [Core Analysis] Scale drop-off rates across replicates using scaleDOR
//  * 3. [Core Analysis] Compute uninterrupted stretches of nucleotides using computeStretches
//  * 4. [Core Analysis] Correct coverage bias (variance stabilization) using stabiliseVariance
//  * 5. [Input & Preparation] Define nucleotide positions for the null distribution (omitting sequence bias correction for short molecules)
//  * 6. [Core Analysis] Compute posterior probabilities of modification using computeProbs
//  * 7. [Core Analysis] Shift posterior probabilities up by one position to align with modification sites

nextflow.enable.dsl = 2

process BIOC_BUMHMM_BUMHMM_STRUCTURE_PROBING_ANALYSIS {
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
    .bm_deps <- c("BUMHMM", "Biostrings")
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
          library(BUMHMM)
          library(Biostrings)
        })
        
        # -----------------------------------------------------------------------------
        # Stage 0: Read User Input Files
        # -----------------------------------------------------------------------------
        # The pipeline reads exactly these files from the working directory:
        # - se.rds: SummarizedExperiment containing coverage, dropoff_count, and dropoff_rate assays
        # - sequence.rds: DNAString object representing the genomic/transcriptomic reference sequence
        if (!file.exists("se.rds") || !file.exists("sequence.rds")) {
          stop("Required input files 'se.rds' and/or 'sequence.rds' not found in the working directory.")
        }
        
        se <- readRDS("se.rds")
        sequence <- readRDS("sequence.rds")
        
        # -----------------------------------------------------------------------------
        # Stage 1: Select nucleotide positions for pairwise comparisons
        # -----------------------------------------------------------------------------
        Nc <- sum(se\$replicate == "control")
        Nt <- sum(se\$replicate == "treatment")
        t <- 1
        nuclSelection <- selectNuclPos(se, Nc, Nt, t)
        
        # -----------------------------------------------------------------------------
        # Stage 2: Scale drop-off rates across replicates
        # -----------------------------------------------------------------------------
        assay(se, "dropoff_rate") <- scaleDOR(se, nuclSelection, Nc, Nt)
        
        # -----------------------------------------------------------------------------
        # Stage 3: Compute uninterrupted stretches of nucleotides
        # -----------------------------------------------------------------------------
        stretches <- computeStretches(se, t)
        
        # -----------------------------------------------------------------------------
        # Stage 4: Correct coverage bias (variance stabilization)
        # -----------------------------------------------------------------------------
        varStab <- stabiliseVariance(se, nuclSelection, Nc, Nt)
        LDR_C <- varStab\$LDR_C
        LDR_CT <- varStab\$LDR_CT
        
        # -----------------------------------------------------------------------------
        # Stage 5: Define nucleotide positions for the null distribution
        # -----------------------------------------------------------------------------
        nuclPosition <- list()
        nuclPosition[[1]] <- 1:nchar(sequence)
        
        # -----------------------------------------------------------------------------
        # Stage 6: Compute posterior probabilities of modification
        # -----------------------------------------------------------------------------
        posteriors <- computeProbs(LDR_C, LDR_CT, Nc, Nt, '+', nuclPosition,
                                   nuclSelection\$analysedC, nuclSelection\$analysedCT,
                                   stretches)
        
        # -----------------------------------------------------------------------------
        # Stage 7: Shift posterior probabilities up by one position
        # -----------------------------------------------------------------------------
        shifted_posteriors <- matrix(, nrow=dim(posteriors)[1], ncol=1)
        shifted_posteriors[1:(length(shifted_posteriors) - 1)] <-
          posteriors[2:dim(posteriors)[1], 2]
        
        # -----------------------------------------------------------------------------
        # Stage 8: Write Outputs
        # -----------------------------------------------------------------------------
        # Save raw and shifted posteriors as RDS objects
        saveRDS(posteriors, "posteriors.rds")
        saveRDS(shifted_posteriors, "shifted_posteriors.rds")
        
        # Save posteriors as CSV tables
        write.csv(as.data.frame(posteriors), "posteriors.csv", row.names = FALSE)
        write.csv(as.data.frame(shifted_posteriors), "shifted_posteriors.csv", row.names = FALSE)
        
        # Generate and save the PDF plot
        pdf("bumhmm_output_plot.pdf", width = 7, height = 5)
        plot(shifted_posteriors, xlab = 'Nucleotide position',
             ylab = 'Probability of modification',
             main = 'BUMHMM output for DMS data set',
             col = "blue", pch = 20)
        dev.off()
        
        message("BUMHMM pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_BUMHMM_BUMHMM_STRUCTURE_PROBING_ANALYSIS":',
        paste0('    BUMHMM: ', as.character(packageVersion('BUMHMM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bumhmm_structure_probing_analysis.csv versions.yml
    """
}

workflow BIOC_BUMHMM_BUMHMM_STRUCTURE_PROBING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ se, sequence ] ]

    main:
    BIOC_BUMHMM_BUMHMM_STRUCTURE_PROBING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BUMHMM_BUMHMM_STRUCTURE_PROBING_ANALYSIS.out.tables
    plots    = BIOC_BUMHMM_BUMHMM_STRUCTURE_PROBING_ANALYSIS.out.plots
    objects  = BIOC_BUMHMM_BUMHMM_STRUCTURE_PROBING_ANALYSIS.out.objects
    versions = BIOC_BUMHMM_BUMHMM_STRUCTURE_PROBING_ANALYSIS.out.versions
}
