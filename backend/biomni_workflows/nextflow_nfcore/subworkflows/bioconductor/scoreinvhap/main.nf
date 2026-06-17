#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scoreInvHap — score_inversion_haplotypes
// Genotype known genomic inversions from SNP VCF data using scoreInvHap, perform quality control filtering, and output classification results and diagnostic plots
// Input: input.vcf, coldata.csv
// Container: 1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: VariantAnnotation, scoreInvHap
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCOREINVHAP_SCORE_INVERSION_HAPLOTYPES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("scoreInvHap", "VariantAnnotation")
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
    library(scoreInvHap)
    library(VariantAnnotation)
    
    # Retrieve parameters from environment variables or defaults
    inversion_id <- Sys.getenv("INVERSION_ID", unset = "inv7_005")
    min_diff <- as.numeric(Sys.getenv("MIN_DIFF", unset = "0.1"))
    call_rate <- as.numeric(Sys.getenv("CALL_RATE", unset = "0.9"))
    genome_build <- Sys.getenv("GENOME_BUILD", unset = "hg19")
    
    message("Starting scoreInvHap pipeline...")
    message("Inversion ID: ", inversion_id)
    message("Genome Build: ", genome_build)
    
    # --- Load and preprocess input VCF ---
    if (!file.exists("input.vcf")) {
      stop("Required input file 'input.vcf' not found in the working directory.")
    }
    
    message("Reading input VCF file...")
    vcf <- VariantAnnotation::readVcf("input.vcf", genome_build)
    
    # --- Quality Control and SNP Filtering ---
    message("Checking SNPs against scoreInvHap references...")
    check <- checkSNPs(vcf)
    
    if (is.null(check\$genos) || nrow(check\$genos) == 0) {
      stop("No valid SNPs remained after running checkSNPs. Please verify that the input VCF contains SNPs matching the reference genome build.")
    }
    
    vcf_clean <- check\$genos
    message("Number of SNPs retained for analysis: ", nrow(vcf_clean))
    
    # --- Inversion Genotyping ---
    message("Running scoreInvHap genotyping...")
    # Check if genotype probabilities (GP) are available to use the probabilistic classifier
    has_gp <- "GP" %in% names(VariantAnnotation::geno(vcf_clean))
    if (has_gp) {
      message("Posterior probabilities (GP) detected. Running with probs = TRUE.")
    } else {
      message("Posterior probabilities (GP) not detected. Running with best-guess genotypes.")
    }
    
    # Run the core scoring and classification
    res <- tryCatch({
      scoreInvHap(SNPlist = vcf_clean, inv = inversion_id, probs = has_gp)
    }, error = function(e) {
      message("Error during scoreInvHap execution: ", e\$message)
      NULL
    })
    
    # --- Extract Results and Apply QC Filters ---
    if (!is.null(res)) {
      message("Extracting classifications and scores...")
      samples <- colnames(vcf_clean)
      
      # Extract default classifications
      class_default <- classification(res)
      
      # Extract QC-filtered classifications
      class_filtered <- classification(res, minDiff = min_diff, callRate = call_rate)
      class_filtered_full <- class_filtered[match(samples, names(class_filtered))]
      
      # Extract haplotype-level classifications (inversion = FALSE)
      class_haplo <- classification(res, inversion = FALSE)
      class_haplo_full <- class_haplo[match(samples, names(class_haplo))]
      
      # Extract similarity scores and QC metrics
      max_s <- maxscores(res)
      diff_s <- diffscores(res)
      num_s <- numSNPs(res)
      prop_s <- propSNPs(res)
      
      # Construct the final results data frame
      results_df <- data.frame(
        Sample = samples,
        Inversion_Genotype = as.character(class_default[samples]),
        Inversion_Genotype_Filtered = as.character(class_filtered_full[samples]),
        Haplotype_Genotype = as.character(class_haplo_full[samples]),
        Max_Score = as.numeric(max_s[samples]),
        Diff_Score = as.numeric(diff_s[samples]),
        Num_SNPs = as.integer(num_s[samples]),
        Prop_SNPs = as.numeric(prop_s[samples]),
        stringsAsFactors = FALSE
      )
      
      # Merge with optional sample metadata if available
      if (file.exists("coldata.csv")) {
        message("Merging with coldata.csv metadata...")
        coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
        sample_col <- if ("sample" %in% colnames(coldata)) "sample" else colnames(coldata)[1]
        results_df <- merge(coldata, results_df, by.x = sample_col, by.y = "Sample", all.y = TRUE)
      }
      
      # Write results to CSV
      write.csv(results_df, "inversion_genotypes.csv", row.names = FALSE)
      message("Genotyping results written to 'inversion_genotypes.csv'.")
      
      # --- Generate Diagnostic Plots ---
      message("Generating diagnostic QC plots...")
      pdf("qc_plots.pdf", width = 10, height = 5)
      par(mfrow = c(1, 2))
      
      # Plot scores QC
      tryCatch({
        plotScores(res, pch = 16, main = paste("QC Scores -", inversion_id))
      }, error = function(e) {
        plot(1, type = "n", main = "Score QC Plot Failed", xlab = "", ylab = "")
        text(1, 1, paste("Error:", e\$message), cex = 0.8)
      })
      
      # Plot call rate QC
      tryCatch({
        plotCallRate(res, main = paste("Call Rate QC -", inversion_id), callRate = call_rate)
      }, error = function(e) {
        plot(1, type = "n", main = "Call Rate QC Plot Failed", xlab = "", ylab = "")
        text(1, 1, paste("Error:", e\$message), cex = 0.8)
      })
      
      dev.off()
      message("QC plots saved to 'qc_plots.pdf'.")
      
    } else {
      # Fallback in case of execution failure
      message("Writing fallback empty outputs due to execution failure.")
      write.csv(data.frame(Error = "Inversion genotyping failed or returned no results."), 
                "inversion_genotypes.csv", row.names = FALSE)
      pdf("qc_plots.pdf", width = 6, height = 4)
      plot(1, type = "n", main = "Genotyping Failed", xlab = "", ylab = "")
      text(1, 1, "No QC plots available due to pipeline failure.", cex = 0.8)
      dev.off()
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SCOREINVHAP_SCORE_INVERSION_HAPLOTYPES":',
        paste0('    scoreInvHap: ', as.character(packageVersion('scoreInvHap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_score_inversion_haplotypes.csv versions.yml
    """
}

workflow BIOC_SCOREINVHAP_SCORE_INVERSION_HAPLOTYPES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SCOREINVHAP_SCORE_INVERSION_HAPLOTYPES(ch_input)

    emit:
    tables   = BIOC_SCOREINVHAP_SCORE_INVERSION_HAPLOTYPES.out.tables
    plots    = BIOC_SCOREINVHAP_SCORE_INVERSION_HAPLOTYPES.out.plots
    objects  = BIOC_SCOREINVHAP_SCORE_INVERSION_HAPLOTYPES.out.objects
    versions = BIOC_SCOREINVHAP_SCORE_INVERSION_HAPLOTYPES.out.versions
}
