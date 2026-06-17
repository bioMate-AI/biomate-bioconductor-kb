#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ZygosityPredictor — gene_zygosity_prediction
// Predict the zygosity of a set of genes in a sample by phasing multiple variants and determining if wild-type copies remain.
// Input: FILE_BAM, VCF, GR_SCNA, GR_SOM_SMALL_VARS, GR_GERM_SMALL_VARS, GR_GENE_MODEL, GR_HAPLOBLOCKS
// Container: quay.io/biocontainers/bioconductor-zygositypredictor:1.10.0--r45hdfd78af_0
// R packages: GenomicRanges, ZygosityPredictor, dplyr
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, ZygosityPredictor, dplyr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Run predict_zygosity with all variant, copy number,
//  * 2. [Input & Preparation] Generate an overview of the full prediction results using
//  * 3. [Input & Preparation] Inspect detailed variant, phasing, and read-level phasing

nextflow.enable.dsl = 2

process BIOC_ZYGOSITYPREDICTOR_GENE_ZYGOSITY_PREDICTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "ZygosityPredictor", "dplyr")
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
    library(ZygosityPredictor)
    library(GenomicRanges)
    library(dplyr)
    
    # Helper function to robustly read GRanges RDS files
    read_granges <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else {
        stop(paste("Required input file missing:", filename))
      }
    }
    
    # Define input file paths from the working directory
    FILE_BAM <- "FILE_BAM"
    VCF <- "VCF"
    
    # Read GRanges inputs
    GR_SCNA             <- read_granges("GR_SCNA")
    GR_SOM_SMALL_VARS   <- read_granges("GR_SOM_SMALL_VARS")
    GR_GERM_SMALL_VARS  <- read_granges("GR_GERM_SMALL_VARS")
    GR_GENE_MODEL       <- read_granges("GR_GENE_MODEL")
    GR_HAPLOBLOCKS      <- read_granges("GR_HAPLOBLOCKS")
    
    # Define sample metadata (with environment variable fallbacks)
    PURITY <- as.numeric(Sys.getenv("PURITY", unset = "0.98"))
    PLOIDY <- as.numeric(Sys.getenv("PLOIDY", unset = "1.57"))
    SEX    <- Sys.getenv("SEX", unset = "female")
    
    # Define the gene variable for the gene_ov call
    OR2J1 <- "OR2J1"
    
    # --- Run predict_zygosity with all variant, copy number, ---
    fp <- predict_zygosity(
      purity = PURITY, 
      ploidy = PLOIDY,
      sex = SEX,
      somCna = GR_SCNA, 
      somSmallVars = GR_SOM_SMALL_VARS, 
      germSmallVars = GR_GERM_SMALL_VARS, 
      geneModel = GR_GENE_MODEL,
      bamDna = FILE_BAM,
      vcf = VCF,
      haploBlocks = GR_HAPLOBLOCKS
    )
    
    # Save the full prediction list object
    saveRDS(fp, "zygosity_predictions.rds")
    
    # Write individual prediction tables to CSV
    if (!is.null(fp\$evaluation_per_variant)) {
      write.csv(fp\$evaluation_per_variant, "evaluation_per_variant.csv", row.names = FALSE)
    }
    if (!is.null(fp\$evaluation_per_gene)) {
      write.csv(fp\$evaluation_per_gene, "evaluation_per_gene.csv", row.names = FALSE)
    }
    if (!is.null(fp\$main_phasing_info)) {
      write.csv(fp\$main_phasing_info, "main_phasing_info.csv", row.names = FALSE)
    }
    
    # --- Generate an overview of the full prediction results using ---
    sink("zygosity_overview.txt")
    ZP_ov(fp)
    sink()
    
    # --- Inspect detailed variant, phasing, and read-level phasing ---
    sink("gene_overview_OR2J1.txt")
    tryCatch({
      gene_ov(fp, OR2J1)
    }, error = function(e) {
      cat("Error running gene_ov for OR2J1:\n")
      print(e)
    })
    sink()

    writeLines(c(
        '"BIOC_ZYGOSITYPREDICTOR_GENE_ZYGOSITY_PREDICTION":',
        paste0('    ZygosityPredictor: ', as.character(packageVersion('ZygosityPredictor')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_zygosity_prediction.csv versions.yml
    """
}

workflow BIOC_ZYGOSITYPREDICTOR_GENE_ZYGOSITY_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ FILE_BAM, VCF, GR_SCNA, GR_SOM_SMALL_VARS, GR_GERM_SMALL_VARS, GR_GENE_MODEL, GR_HAPLOBLOCKS ] ]

    main:
    BIOC_ZYGOSITYPREDICTOR_GENE_ZYGOSITY_PREDICTION(ch_input)

    emit:
    tables   = BIOC_ZYGOSITYPREDICTOR_GENE_ZYGOSITY_PREDICTION.out.tables
    plots    = BIOC_ZYGOSITYPREDICTOR_GENE_ZYGOSITY_PREDICTION.out.plots
    objects  = BIOC_ZYGOSITYPREDICTOR_GENE_ZYGOSITY_PREDICTION.out.objects
    versions = BIOC_ZYGOSITYPREDICTOR_GENE_ZYGOSITY_PREDICTION.out.versions
}
