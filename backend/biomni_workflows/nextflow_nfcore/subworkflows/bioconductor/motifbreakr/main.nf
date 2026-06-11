#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifbreakR — predict_motif_disruption
// Predict the disruptiveness of single nucleotide polymorphisms on transcription factor binding sites.
// Input: variants.vcf, genome_assembly
// Container: quay.io/biocontainers/bioconductor-motifbreakr:2.24.0--r45hdfd78af_0
// R packages: BiocParallel, BSgenome, genome_name, motifbreakR, MotifDb
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, BiocParallel, MotifDb, motifbreakR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the target genome and SNP data
//  * 2. [Core Analysis] Select transcription factor motifs from public sources
//  * 3. [Core Analysis] Run the disruptiveness prediction using one of the three available algorithms (weighted-sum, log-probabilities, or relative entrop
//  * 4. [Core Analysis] Compare the alleles to judge information gain or loss

nextflow.enable.dsl = 2

process BIOC_MOTIFBREAKR_PREDICT_MOTIF_DISRUPTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("BiocParallel", "BSgenome", "genome_name", "motifbreakR", "MotifDb")
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
            library(motifbreakR)
            library(BSgenome)
            library(MotifDb)
            library(BiocParallel)
            
            # ==========================================
            # 1. Load the target genome and SNP data
            # ==========================================
            
            # Read the genome assembly package name from the user-provided file
            genome_file <- "genome_assembly"
            if (!file.exists(genome_file)) {
              stop("Required input file 'genome_assembly' not found in the working directory.")
            }
            genome_name <- trimws(readLines(genome_file, n = 1))
            
            # Load the specified BSgenome package
            if (!requireNamespace(genome_name, quietly = TRUE)) {
              stop(paste("The required genome package", genome_name, "is not installed."))
            }
            library(genome_name, character.only = TRUE)
            genome <- get(genome_name)
            
            # Read the user-provided VCF file
            vcf_file <- "variants.vcf"
            if (!file.exists(vcf_file)) {
              stop("Required input file 'variants.vcf' not found in the working directory.")
            }
            
            # Import SNPs using motifbreakR's snps.from.file
            snps <- snps.from.file(
              file = vcf_file,
              format = "vcf",
              search.genome = genome
            )
            
            # ==========================================
            # 2. Select transcription factor motifs
            # ==========================================
            
            # Extract species name from the genome package name to filter motifs
            # e.g., "BSgenome.Hsapiens.UCSC.hg19" -> "Hsapiens"
            species_match <- regmatches(genome_name, regexpr("(?<=\\\\.)[A-Za-z0-9]+(?=\\\\.)", genome_name, perl = TRUE))
            if (length(species_match) == 0) {
              species_name <- "Hsapiens"
            } else {
              species_name <- species_match
            }
            
            # Query MotifDb for the corresponding species
            motifs <- MotifDb[grep(species_name, names(MotifDb), ignore.case = TRUE)]
            if (length(motifs) == 0) {
              # Fallback to all available motifs if species-specific query returns empty
              motifs <- MotifDb
            }
            
            # ==========================================
            # 3. Run the disruptiveness prediction
            # ==========================================
            
            # Run motifbreakR using the relative entropy / information content algorithm ("ic")
            results <- motifbreakR(
              snpList = snps,
              pwmList = motifs,
              threshold = 0.85,
              method = "ic",
              bpparam = BiocParallel::SerialParam()
            )
            
            # ==========================================
            # 4. Compare alleles to judge information gain/loss
            # ==========================================
            
            # Calculate p-values for the predictions to evaluate significance
            tryCatch({
              results <- calculatePvalue(results)
            }, error = function(e) {
              message("p-value calculation skipped or failed: ", e\$message)
            })
            
            # ==========================================
            # 5. Write Outputs
            # ==========================================
            
            # Save the complete results object as an RDS file
            saveRDS(results, "motif_disruption_results.rds")
            
            # Export the results as a CSV table
            results_df <- as.data.frame(results)
            write.csv(results_df, "motif_disruption_results.csv", row.names = FALSE)
            
            # Generate diagnostic plots for the top predicted disruption if results exist
            if (length(results) > 0) {
              pdf("motif_disruption_plots.pdf", width = 10, height = 8)
              
              # Extract the first SNP
              snp_id <- names(results)[1]
              
              tryCatch({
                plotMB(results = results, rsid = snp_id, effect = c("strong", "weak"))
              }, error = function(e) {
                message("Plotting failed: ", e\$message)
              })
              
              dev.off()
            }

    writeLines(c(
        '"BIOC_MOTIFBREAKR_PREDICT_MOTIF_DISRUPTION":',
        paste0('    motifbreakR: ', as.character(packageVersion('motifbreakR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predict_motif_disruption.csv versions.yml
    """
}

workflow BIOC_MOTIFBREAKR_PREDICT_MOTIF_DISRUPTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ variants.vcf, genome_assembly ] ]

    main:
    BIOC_MOTIFBREAKR_PREDICT_MOTIF_DISRUPTION(ch_input)

    emit:
    tables   = BIOC_MOTIFBREAKR_PREDICT_MOTIF_DISRUPTION.out.tables
    plots    = BIOC_MOTIFBREAKR_PREDICT_MOTIF_DISRUPTION.out.plots
    objects  = BIOC_MOTIFBREAKR_PREDICT_MOTIF_DISRUPTION.out.objects
    versions = BIOC_MOTIFBREAKR_PREDICT_MOTIF_DISRUPTION.out.versions
}
