#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifcounter — motif_matching_and_enrichment
// Estimate a background model, normalize a motif, identify individual and average motif hits/scores, and test for motif enrichment in a set of DNA sequences.
// Input: seq.fasta, motif
// Container: quay.io/biocontainers/bioconductor-motifcounter:1.34.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, motifcounter
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load DNA sequences and estimate a Markov background model using readBackground
//  * 2. [Core Analysis] Normalize the position frequency matrix using normalizeMotif
//  * 3. [Core Analysis] Set the false positive probability threshold using motifcounterOptions
//  * 4. [Core Analysis] Compute position- and strand-specific scores and hits for individual sequences using scoreSequence, scoreDist, and motifHits
//  * 5. [Core Analysis] Compute average score and hit profiles across multiple sequences using scoreProfile and motifHitProfile
//  * 6. [Core Analysis] Test for motif enrichment across the sequence set using motifEnrichment

nextflow.enable.dsl = 2

process BIOC_MOTIFCOUNTER_MOTIF_MATCHING_AND_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        library(motifcounter)
        library(Biostrings)
        
        # ==========================================
        # 1. Load DNA sequences and estimate background model
        # ==========================================
        if (!file.exists("seq.fasta")) {
          stop("Error: Required input file 'seq.fasta' not found in the working directory.")
        }
        
        order <- 1
        seqs <- Biostrings::readDNAStringSet("seq.fasta")
        bg <- readBackground(seqs, order)
        
        # Save background model
        saveRDS(bg, "background_model.rds")
        
        # ==========================================
        # 2. Load and normalize the motif (PFM)
        # ==========================================
        if (!file.exists("motif")) {
          stop("Error: Required input file 'motif' not found in the working directory.")
        }
        
        # Robustly read the motif file (supports RDS or tabular text format)
        motif <- tryCatch({
          readRDS("motif")
        }, error = function(e) {
          as.matrix(read.table("motif", header = FALSE))
        })
        
        # Ensure motif is a numeric matrix
        motif <- matrix(as.numeric(motif), nrow = nrow(motif), ncol = ncol(motif))
        
        # Handle transposition if matrix is oriented incorrectly (should be 4 rows x N columns)
        if (nrow(motif) != 4 && ncol(motif) == 4) {
          motif <- t(motif)
        }
        
        if (nrow(motif) != 4) {
          stop("Error: Motif matrix must have exactly 4 rows representing A, C, G, and T.")
        }
        
        # Ensure rownames are set correctly for motifcounter
        rownames(motif) <- c("A", "C", "G", "T")
        
        # Normalize the motif
        new_motif <- normalizeMotif(motif)
        
        # Update the motif variable to the normalized version to ensure subsequent steps use it
        motif <- new_motif
        
        # ==========================================
        # 3. Set false positive probability threshold
        # ==========================================
        motifcounterOptions(alpha = 0.01)
        
        # ==========================================
        # 4. Individual sequence analysis
        # ==========================================
        # Map the input sequences to 'oct4peaks' to match the documented code variable names
        oct4peaks <- seqs
        
        # Verify that all sequences are of equal length
        if (length(unique(width(oct4peaks))) > 1) {
          stop("Error: All sequences must be of equal length.")
        }
        
        # Compute position- and strand-specific scores and hits
        scores <- scoreSequence(oct4peaks[[1]], motif, bg)
        sd <- scoreDist(motif, bg)
        mhits <- motifHits(oct4peaks[[1]], motif, bg)
        
        # Save individual sequence results
        saveRDS(scores, "individual_scores.rds")
        saveRDS(sd, "score_distribution.rds")
        saveRDS(mhits, "individual_hits.rds")
        
        # Create visualization plots
        pdf("motif_analysis_plots.pdf", width = 12, height = 10)
        par(mfrow = c(2, 2))
        
        # Plot 1: Individual sequence scores
        plot(1:length(scores\$fscores), scores\$fscores, type = "l", 
             col = "blue", xlab = "position", ylab = "score", 
             ylim = c(min(sd\$score), max(sd\$score)), main = "Individual Sequence Scores")
        points(scores\$rscores, col = "red", type = "l")
        legend("topright", c("forw.", "rev."), col = c("blue", "red"), lty = c(1, 1))
        
        # Plot 2: Theoretical score distribution
        plot(sd\$dist, sd\$scores, type = "l", xlab = "probability", ylab = "score",
             main = "Theoretical Score Distribution")
        
        # ==========================================
        # 5. Profile analysis across multiple sequences
        # ==========================================
        # Compute average score and hit profiles
        scores_profile_data <- scoreProfile(oct4peaks, motif, bg)
        scores <- scores_profile_data # Keep exact documented variable assignment
        saveRDS(scores, "profile_scores.rds")
        
        mhits_profile_data <- motifHitProfile(oct4peaks, motif, bg)
        mhits <- mhits_profile_data # Keep exact documented variable assignment
        saveRDS(mhits, "profile_hits.rds")
        
        # Plot 3: Average score profile
        plot(1:length(scores\$fscores), scores\$fscores, type = "l", 
             col = "blue", xlab = "position", ylab = "score", main = "Average Score Profile")
        points(scores\$rscores, col = "red", type = "l")
        legend("bottomleft", legend = c("forward", "reverse"), col = c("blue", "red"), lty = c(1, 1))
        
        # Plot 4: Average hit profile
        plot(1:length(mhits\$fhits), mhits\$fhits, type = "l", 
             col = "blue", xlab = "position", ylab = "frequency", main = "Average Motif Hit Profile")
        points(mhits\$rhits, col = "red", type = "l")
        legend("bottomleft", legend = c("forward", "reverse"), col = c("blue", "red"), lty = c(1, 1))
        
        dev.off()
        
        # ==========================================
        # 6. Test for motif enrichment
        # ==========================================
        result <- motifEnrichment(oct4peaks, motif, bg)
        
        # Save enrichment results
        saveRDS(result, "enrichment_result.rds")
        write.csv(as.data.frame(result), "enrichment_result.csv", row.names = FALSE)
        
        # Print summary to console
        cat("--- Motif Enrichment Analysis Complete ---\n")
        cat(sprintf("P-value: %e\n", result\$pvalue))
        cat(sprintf("Fold-enrichment: %.4f\n", result\$fold))

    writeLines(c(
        '"BIOC_MOTIFCOUNTER_MOTIF_MATCHING_AND_ENRICHMENT":',
        paste0('    motifcounter: ', as.character(packageVersion('motifcounter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motif_matching_and_enrichment.csv versions.yml
    """
}

workflow BIOC_MOTIFCOUNTER_MOTIF_MATCHING_AND_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seq.fasta, motif ] ]

    main:
    BIOC_MOTIFCOUNTER_MOTIF_MATCHING_AND_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MOTIFCOUNTER_MOTIF_MATCHING_AND_ENRICHMENT.out.tables
    plots    = BIOC_MOTIFCOUNTER_MOTIF_MATCHING_AND_ENRICHMENT.out.plots
    objects  = BIOC_MOTIFCOUNTER_MOTIF_MATCHING_AND_ENRICHMENT.out.objects
    versions = BIOC_MOTIFCOUNTER_MOTIF_MATCHING_AND_ENRICHMENT.out.versions
}
