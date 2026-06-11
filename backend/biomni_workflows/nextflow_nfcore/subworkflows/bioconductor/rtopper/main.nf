#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RTopper — integration_then_gse
// Integrate genomic data across multiple platforms using a logistic model first, and then perform Gene Set Enrichment (GSE) analysis on the integrated score.
// Input: dat, pheno, fgsList
// Container: quay.io/biocontainers/bioconductor-rtopper:1.56.0--r45hdfd78af_0
// R packages: KEGGREST, limma, RTopper
// Bioconductor: 3.20 | R: 4.4
// Requires: RTopper
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert the genomic and phenotypic data into a gene-centered list using convertToDr. 2. Compute integrated gene-to-phenotype assoc

nextflow.enable.dsl = 2

process BIOC_RTOPPER_INTEGRATION_THEN_GSE {
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
    .bm_deps <- c("KEGGREST", "limma", "RTopper")
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
    
    # Read user input files from the working directory
    dat <- readRDS("dat.rds")
    pheno <- readRDS("pheno.rds")
    fgsList <- readRDS("fgsList.rds")
    
    # 1. Convert the genomic and phenotypic data into a gene-centered list
    dataDr <- convertToDr(dat, pheno, length(dat))
    
    # 2. Compute integrated gene-to-phenotype association scores across all platforms
    bicStatInt <- computeDrStat(dataDr, columns = 1:length(dat), method="bic", integrate = TRUE)
    
    # 3. Perform batch GSE analysis on the integrated scores
    gseABS.int <- runBatchGSE(dataList=bicStatInt, fgsList=fgsList)
    
    # 4. Adjust the resulting p-values for multiple testing
    gseABS.int.BH <- adjustPvalGSE(gseABS.int)
    
    # Save the primary outputs as RDS objects
    saveRDS(dataDr, "dataDr.rds")
    saveRDS(bicStatInt, "bicStatInt.rds")
    saveRDS(gseABS.int, "gseABS_int.rds")
    saveRDS(gseABS.int.BH, "gseABS_int_BH.rds")
    
    # Export adjusted p-values as CSV tables for each gene set collection
    if ("integrated" %in% names(gseABS.int.BH)) {
      for (gs_name in names(gseABS.int.BH\$integrated)) {
        val <- gseABS.int.BH\$integrated[[gs_name]]
        if (!is.null(val)) {
          write.csv(as.data.frame(val), file = paste0("gse_adjusted_integrated_", gs_name, ".csv"), row.names = TRUE)
        }
      }
    }

    writeLines(c(
        '"BIOC_RTOPPER_INTEGRATION_THEN_GSE":',
        paste0('    RTopper: ', as.character(packageVersion('RTopper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_integration_then_gse.csv versions.yml
    """
}

workflow BIOC_RTOPPER_INTEGRATION_THEN_GSE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dat, pheno, fgsList ] ]

    main:
    BIOC_RTOPPER_INTEGRATION_THEN_GSE(ch_input)

    emit:
    tables   = BIOC_RTOPPER_INTEGRATION_THEN_GSE.out.tables
    plots    = BIOC_RTOPPER_INTEGRATION_THEN_GSE.out.plots
    objects  = BIOC_RTOPPER_INTEGRATION_THEN_GSE.out.objects
    versions = BIOC_RTOPPER_INTEGRATION_THEN_GSE.out.versions
}
