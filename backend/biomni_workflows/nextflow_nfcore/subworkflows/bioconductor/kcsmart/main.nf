#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: KCsmart — recurrent_aberration_detection
// Identify recurrent genomic gains and losses across a set of tumor samples using single-scale or multi-scale kernel convolution.
// Input: hsSampleData, hsMirrorLocs
// Container: quay.io/biocontainers/bioconductor-kcsmart:2.68.0--r45hdfd78af_0
// R packages: KCsmart
// Bioconductor: 3.20 | R: 4.4
// Requires: KCsmart
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the aCGH data and chromosome mirror locations
//  * 2. [Core Analysis] Calculate the sample point matrix (SPM) at one or more kernel widths using calcSpm
//  * 3. [Visualization & Output] Plot the chromosome-wide convolution results using plot
//  * 4. [Core Analysis] Calculate permutation-based significance thresholds using findSigLevelTrad
//  * 5. [Visualization & Output] Plot the convolution results with the significance thresholds
//  * 6. [Core Analysis] Extract significant genomic segments and their corresponding probes using getSigSegments
//  * 7. [Visualization & Output] (Optional) Visualize multi-scale analysis results using plotScaleSpace

nextflow.enable.dsl = 2

process BIOC_KCSMART_RECURRENT_ABERRATION_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("KCsmart")
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
    
    # Load required library
    library(KCsmart)
    
    # Helper function to robustly read user input files from the working directory
    read_input <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else if (file.exists(paste0(filename, ".RData"))) {
        env <- new.env()
        load(paste0(filename, ".RData"), envir = env)
        vars <- ls(env)
        if (length(vars) == 1) {
          return(env[[vars[1]]])
        } else if (filename %in% vars) {
          return(env[[filename]])
        } else {
          stop("Multiple or no matching variables found in RData file.")
        }
      } else {
        stop(paste("Required input file", filename, "not found in the working directory."))
      }
    }
    
    # 1. Load the aCGH data and chromosome mirror locations
    hsSampleData <- read_input("hsSampleData")
    hsMirrorLocs <- read_input("hsMirrorLocs")
    
    # 2. Calculate the sample point matrix (SPM) at one or more kernel widths using calcSpm
    spm1mb <- calcSpm(hsSampleData, hsMirrorLocs)
    spm4mb <- calcSpm(hsSampleData, hsMirrorLocs, sigma=4000000)
    
    # Save calculated SPMs
    saveRDS(spm1mb, "spm1mb.rds")
    saveRDS(spm4mb, "spm4mb.rds")
    
    # 3. Plot the chromosome-wide convolution results using plot
    pdf("plot_spm1mb_all.pdf")
    plot(spm1mb)
    dev.off()
    
    pdf("plot_spm1mb_gains_selected.pdf")
    plot(spm1mb, chromosomes=c(1, 12, "X"), type="g")
    dev.off()
    
    # 4. Calculate permutation-based significance thresholds using findSigLevelTrad
    sigLevel4mb <- findSigLevelTrad(hsSampleData, spm4mb, n=10, p=0.05)
    saveRDS(sigLevel4mb, "sigLevel4mb.rds")
    
    # 5. Plot the convolution results with the significance thresholds
    pdf("plot_spm4mb_sig_both.pdf")
    plot(spm4mb, sigLevels=sigLevel4mb, type=1)
    dev.off()
    
    pdf("plot_spm4mb_sig_gains_selected.pdf")
    plot(spm4mb, chromosomes=c(1, 12, "X"), type="g", sigLevels=sigLevel4mb)
    dev.off()
    
    # 6. Extract significant genomic segments and their corresponding probes using getSigSegments
    sigRegions4mb <- getSigSegments(spm4mb, sigLevel4mb)
    saveRDS(sigRegions4mb, "sigRegions4mb.rds")
    
    # Write significant regions to a text file
    write.table(sigRegions4mb, file="sigRegions4mb.txt", sep="\t", quote=FALSE, row.names=FALSE)
    
    # Safely extract and write probe names of the first significantly gained region if it exists
    if (length(sigRegions4mb@gains) >= 1 && !is.null(sigRegions4mb@gains[[1]]\$probes)) {
      probes <- sigRegions4mb@gains[[1]]\$probes
      write.table(probes, "sigRegions4mb_gains_1_probes.txt", row.names=FALSE, col.names=FALSE, quote=FALSE)
    } else {
      message("No significant gains detected to extract probes from.")
    }
    
    # 7. Visualize multi-scale analysis results using plotScaleSpace
    sigLevel1mb <- findSigLevelTrad(hsSampleData, spm1mb, n=10)
    saveRDS(sigLevel1mb, "sigLevel1mb.rds")
    
    pdf("plot_scalespace_gains.pdf")
    plotScaleSpace(list(spm1mb, spm4mb), list(sigLevel1mb, sigLevel4mb), type='g')
    dev.off()

    writeLines(c(
        '"BIOC_KCSMART_RECURRENT_ABERRATION_DETECTION":',
        paste0('    KCsmart: ', as.character(packageVersion('KCsmart')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_recurrent_aberration_detection.csv versions.yml
    """
}

workflow BIOC_KCSMART_RECURRENT_ABERRATION_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hsSampleData, hsMirrorLocs ] ]

    main:
    BIOC_KCSMART_RECURRENT_ABERRATION_DETECTION(ch_input)

    emit:
    tables   = BIOC_KCSMART_RECURRENT_ABERRATION_DETECTION.out.tables
    plots    = BIOC_KCSMART_RECURRENT_ABERRATION_DETECTION.out.plots
    objects  = BIOC_KCSMART_RECURRENT_ABERRATION_DETECTION.out.objects
    versions = BIOC_KCSMART_RECURRENT_ABERRATION_DETECTION.out.versions
}
