#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: supersigs — train_supersig
// Preprocess mutation data, build a trinucleotide feature matrix, and train a supervised mutational signature (SuperSig).
// Input: chr22.vcf.gz, example_dt
// Container: quay.io/biocontainers/bioconductor-supersigs:1.18.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, dplyr, ggplot2, supersigs, VariantAnnotation
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, VariantAnnotation, dplyr, ggplot2, supersigs
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read VCF and add patient age to colData
//  * 2. [Core Analysis] Process VCF to a simplified data frame using process_vcf
//  * 3. [Core Analysis] Transform mutations into a trinucleotide matrix using make_matrix
//  * 4. [Core Analysis] Add the indicator variable (IndVar) to the matrix
//  * 5. [Core Analysis] Train the supervised signature using get_signature
//  * 6. [Visualization & Output] Simplify the signature for visualization using simplify_signature

nextflow.enable.dsl = 2

process BIOC_SUPERSIGS_TRAIN_SUPERSIG {
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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "dplyr", "ggplot2", "supersigs", "VariantAnnotation")
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
    library(supersigs)
    library(VariantAnnotation)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(dplyr)
    library(ggplot2)
    
    # 1. Read VCF and add patient age to colData
    fl <- "chr22.vcf.gz"
    if (!file.exists(fl)) {
      stop("Required input file 'chr22.vcf.gz' not found in the working directory.")
    }
    
    vcf <- VariantAnnotation::readVcf(fl, "hg19") 
    vcf <- vcf[, 1]
    positions <- geno(vcf)\$GT != "0|0" 
    vcf <- vcf[positions[, 1],]
    colData(vcf)\$age <- 50
    
    # 2. Process VCF to a simplified data frame using process_vcf
    dt <- process_vcf(vcf)
    write.csv(dt, "processed_vcf_mutations.csv", row.names = FALSE)
    
    # 3. Transform mutations into a trinucleotide matrix using make_matrix
    # Read the user-provided example_dt from the working directory
    if (file.exists("example_dt.csv")) {
      example_dt <- read.csv("example_dt.csv", stringsAsFactors = FALSE)
    } else if (file.exists("example_dt.tsv")) {
      example_dt <- read.delim("example_dt.tsv", stringsAsFactors = FALSE)
    } else if (file.exists("example_dt.rds")) {
      example_dt <- readRDS("example_dt.rds")
    } else {
      stop("Required input file 'example_dt' (CSV, TSV, or RDS) not found in the working directory.")
    }
    
    input_dt <- make_matrix(example_dt)
    
    # 4. Add the indicator variable (IndVar) to the matrix
    # Dynamically generate the IndVar vector to match the number of rows in input_dt
    ind_var_values <- rep(c(1, 0), length.out = nrow(input_dt))
    input_dt <- input_dt %>%
      mutate(IndVar = ind_var_values) %>%
      relocate(IndVar)
    
    # 5. Train the supervised signature using get_signature
    set.seed(1)
    supersig <- get_signature(data = input_dt, factor = "Smoking")
    saveRDS(supersig, "supersig_model.rds")
    
    # 6. Simplify the signature for visualization using simplify_signature
    features <- simplify_signature(object = supersig, iupac = FALSE)
    features_iupac <- simplify_signature(object = supersig, iupac = TRUE)
    
    saveRDS(features, "features_simplified.rds")
    saveRDS(features_iupac, "features_iupac.rds")
    
    # Create and save the visualization plot
    p <- data.frame(features = names(features_iupac),
                    differences = features_iupac) %>%
      ggplot(aes(x = features, y = differences)) +
      geom_col() +
      theme_minimal()
    
    ggsave("signature_plot.pdf", plot = p, width = 8, height = 6)
    
    # Apply the SuperSig to predict on the dataset
    newdata <- predict_signature(supersig, newdata = input_dt, factor = "Smoking")
    write.csv(newdata, "predicted_signatures.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_SUPERSIGS_TRAIN_SUPERSIG":',
        paste0('    supersigs: ', as.character(packageVersion('supersigs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_train_supersig.csv versions.yml
    """
}

workflow BIOC_SUPERSIGS_TRAIN_SUPERSIG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chr22.vcf.gz, example_dt ] ]

    main:
    BIOC_SUPERSIGS_TRAIN_SUPERSIG(ch_input)

    emit:
    tables   = BIOC_SUPERSIGS_TRAIN_SUPERSIG.out.tables
    plots    = BIOC_SUPERSIGS_TRAIN_SUPERSIG.out.plots
    objects  = BIOC_SUPERSIGS_TRAIN_SUPERSIG.out.objects
    versions = BIOC_SUPERSIGS_TRAIN_SUPERSIG.out.versions
}
