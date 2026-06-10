#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RTopper — gse_then_integration
// Perform separate Gene Set Enrichment (GSE) analyses on individual genomic platforms first, and then integrate the GSE results across platforms.
// Input: dat, pheno, fgsList
// Container: quay.io/biocontainers/bioconductor-rtopper:1.56.0--r45hdfd78af_0
// R packages: RTopper, limma
// Bioconductor: 3.20 | R: 4.4
// Requires: RTopper, limma
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert the genomic and phenotypic data into a gene-centered list using convertToDr. 2. Compute separate gene-to-phenotype associa

nextflow.enable.dsl = 2

process BIOC_RTOPPER_GSE_THEN_INTEGRATION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("RTopper", "limma")
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
    library(RTopper)
    library(limma)
    
    # Read user input files from the working directory
    dat <- readRDS("dat.rds")
    pheno <- readRDS("pheno.rds")
    fgsList <- readRDS("fgsList.rds")
    
    # 1. Convert the genomic and phenotypic data into a gene-centered list
    dataDr <- convertToDr(dat, pheno, length(dat))
    
    # 2. Compute separate gene-to-phenotype association scores for each platform
    bicStatSep <- computeDrStat(dataDr, columns = 1:length(dat), method="bic", integrate = FALSE)
    
    # 3. Perform separate batch GSE analyses for each platform
    gseABS.sep <- runBatchGSE(dataList=bicStatSep, fgsList=fgsList)
    
    # 4. Integrate the separate GSE p-values across platforms
    gseABS.geoMean.sep <- combineGSE(gseABS.sep, method="geometricMean")
    
    # Save meaningful results to output files
    saveRDS(dataDr, "dataDr.rds")
    saveRDS(bicStatSep, "bicStatSep.rds")
    saveRDS(gseABS.sep, "gseABS_sep.rds")
    saveRDS(gseABS.geoMean.sep, "gseABS_geoMean_sep.rds")
    
    # Export combined GSE results as CSV tables for each functional gene set collection
    if ("combinedScore" %in% names(gseABS.geoMean.sep)) {
      combined_results <- gseABS.geoMean.sep\$combinedScore
      for (collection_name in names(combined_results)) {
        scores <- combined_results[[collection_name]]
        df_out <- data.frame(
          GeneSet = names(scores),
          PValue = as.numeric(scores),
          stringsAsFactors = FALSE
        )
        # Remove rows with NA p-values (gene sets that couldn't be evaluated)
        df_out <- df_out[!is.na(df_out\$PValue), ]
        # Sort by p-value
        df_out <- df_out[order(df_out\$PValue), ]
        write.csv(df_out, file = paste0("gse_combined_", collection_name, ".csv"), row.names = FALSE)
      }
    }

    writeLines(c(
        '"BIOC_RTOPPER_GSE_THEN_INTEGRATION":',
        paste0('    RTopper: ', as.character(packageVersion('RTopper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gse_then_integration.csv versions.yml
    """
}

workflow BIOC_RTOPPER_GSE_THEN_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dat, pheno, fgsList ] ]

    main:
    BIOC_RTOPPER_GSE_THEN_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_RTOPPER_GSE_THEN_INTEGRATION.out.tables
    plots    = BIOC_RTOPPER_GSE_THEN_INTEGRATION.out.plots
    objects  = BIOC_RTOPPER_GSE_THEN_INTEGRATION.out.objects
    versions = BIOC_RTOPPER_GSE_THEN_INTEGRATION.out.versions
}
