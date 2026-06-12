#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gcatest — gcat_association_testing
// Perform genotype conditional association testing on genome-wide SNP data and a trait while controlling for population structure.
// Input: PLINK binary genotype files, Trait vector
// Container: quay.io/biocontainers/bioconductor-gcatest:2.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: gcatest, genio, ggplot2, lfa
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate logistic factors from the genotype matrix using lfa
//  * 2. [Core Analysis] Run the genotype conditional association test using gcat to obtain p-values

nextflow.enable.dsl = 2

process BIOC_GCATEST_GCAT_ASSOCIATION_TESTING {
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
    .bm_deps <- c("lfa", "gcatest", "genio", "ggplot2")
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
    library(lfa)
    library(gcatest)
    library(genio)
    library(ggplot2)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    
    # Find PLINK binary genotype files in the working directory
    bed_files <- list.files(pattern = "\\\\.bed\$", ignore.case = TRUE)
    if (length(bed_files) == 0) {
      stop("Error: No PLINK .bed file found in the working directory.")
    }
    
    # Extract the prefix for the PLINK files
    plink_prefix <- sub("\\\\.bed\$", "", bed_files[1], ignore.case = TRUE)
    
    message("Reading PLINK genotypes using prefix: ", plink_prefix)
    plink_data <- genio::read_plink(plink_prefix)
    
    # Extract the genotype matrix (SNPs as rows, individuals as columns)
    sim_geno <- plink_data\$X
    
    # Find the trait file (expecting a CSV, TSV, or TXT file)
    trait_files <- list.files(pattern = "trait\\\\.(csv|txt|tsv)\$", ignore.case = TRUE)
    if (length(trait_files) == 0) {
      # Fallback to any non-PLINK text/csv file if no file is explicitly named "trait"
      all_files <- list.files(pattern = "\\\\.(csv|txt|tsv)\$", ignore.case = TRUE)
      trait_files <- all_files[!grepl("\\\\.(bim|fam|bed|map|ped)\$", all_files, ignore.case = TRUE)]
    }
    
    if (length(trait_files) == 0) {
      stop("Error: No trait file (e.g., trait.csv or trait.txt) found in the working directory.")
    }
    
    message("Reading trait data from: ", trait_files[1])
    trait_data <- read.table(trait_files[1], header = FALSE, stringsAsFactors = FALSE)
    
    # Convert to a numeric vector
    sim_trait <- as.numeric(trait_data[[1]])
    
    # Validate dimensions
    n_snps <- nrow(sim_geno)
    n_ind_geno <- ncol(sim_geno)
    n_ind_trait <- length(sim_trait)
    
    message(paste("Loaded", n_snps, "SNPs and", n_ind_geno, "individuals from genotypes."))
    message(paste("Loaded", n_ind_trait, "individuals from trait file."))
    
    if (n_ind_geno != n_ind_trait) {
      stop(paste("Dimension mismatch: Genotype matrix has", n_ind_geno, 
                 "individuals, but trait vector has", n_ind_trait, "individuals."))
    }
    
    # -----------------------------------------------------------------------------
    # 2. Run Genotype Conditional Association Testing (GCAT)
    # -----------------------------------------------------------------------------
    
    message("Estimating logistic factors (d = 3)...")
    LF <- lfa(sim_geno, 3)
    
    message("Running GCAT association test...")
    gcat_p <- gcat(sim_geno, LF, sim_trait)
    
    # -----------------------------------------------------------------------------
    # 3. Save Results and Generate Plots
    # -----------------------------------------------------------------------------
    
    # Prepare output directory/filenames
    output_csv <- "gcat_association_results.csv"
    output_pdf <- "gcat_pvalues_histogram.pdf"
    
    # Extract SNP names if available
    snp_names <- rownames(sim_geno)
    if (is.null(snp_names)) {
      snp_names <- paste0("SNP_", seq_len(n_snps))
    }
    
    # Save results table
    results_df <- data.frame(
      SNP = snp_names,
      P_Value = gcat_p,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, file = output_csv, row.names = FALSE)
    message("Saved association results to: ", output_csv)
    
    # Generate and save P-value histogram
    message("Generating P-value histogram...")
    plot_df <- data.frame(p = gcat_p)
    p <- ggplot(plot_df, aes(p, after_stat(density))) +
      geom_histogram(binwidth = 1/20, fill = "skyblue", color = "black") +
      theme_bw() +
      labs(
        title = "GCAT P-value Distribution",
        x = "P-value",
        y = "Density"
      )
    
    ggsave(filename = output_pdf, plot = p, width = 6, height = 4)
    message("Saved P-value histogram to: ", output_pdf)
    
    message("GCAT pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GCATEST_GCAT_ASSOCIATION_TESTING":',
        paste0('    gcatest: ', as.character(packageVersion('gcatest')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gcat_association_testing.csv versions.yml
    """
}

workflow BIOC_GCATEST_GCAT_ASSOCIATION_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PLINK binary genotype files, Trait vector ] ]

    main:
    BIOC_GCATEST_GCAT_ASSOCIATION_TESTING(ch_input)

    emit:
    tables   = BIOC_GCATEST_GCAT_ASSOCIATION_TESTING.out.tables
    plots    = BIOC_GCATEST_GCAT_ASSOCIATION_TESTING.out.plots
    objects  = BIOC_GCATEST_GCAT_ASSOCIATION_TESTING.out.objects
    versions = BIOC_GCATEST_GCAT_ASSOCIATION_TESTING.out.versions
}
