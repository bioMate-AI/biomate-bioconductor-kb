#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iCNV — ngs_only_cnv_detection
// Detect CNVs using only NGS data (WES or WGS).
// Input: ngs_plr, ngs_plr.pos, ngs_baf, ngs_baf.pos
// Container: quay.io/biocontainers/bioconductor-icnv:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iCNV
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run NGS-only CNV detection using iCNV_detection with CN=0
//  * 2. [Visualization & Output] Format output using output_list
//  * 3. [Visualization & Output] Plot results using plotHMMscore

nextflow.enable.dsl = 2

process BIOC_ICNV_NGS_ONLY_CNV_DETECTION {
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
    .bm_deps <- c("iCNV")
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
    library(iCNV)
    
    # Helper function to load inputs robustly (supporting RDS, RDA, or raw files)
    load_input <- function(base_name) {
      possible_files <- c(
        base_name,
        paste0(base_name, ".rds"),
        paste0(base_name, ".rda"),
        paste0(base_name, ".RData")
      )
      
      for (f in possible_files) {
        if (file.exists(f)) {
          if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
            return(readRDS(f))
          } else if (grepl("\\\\.rda\$|\\\\.rdata\$", f, ignore.case = TRUE)) {
            env <- new.env()
            load(f, envir = env)
            return(get(ls(env)[1], envir = env))
          } else {
            # Try reading as RDS first, then fallback to load
            res <- tryCatch(readRDS(f), error = function(e) NULL)
            if (!is.null(res)) return(res)
            
            env <- new.env()
            res <- tryCatch({
              load(f, envir = env)
              get(ls(env)[1], envir = env)
            }, error = function(e) NULL)
            if (!is.null(res)) return(res)
          }
        }
      }
      stop(paste("Error: Could not find or load input file for", base_name))
    }
    
    # Load user inputs from the working directory
    ngs_plr <- load_input("ngs_plr")
    ngs_plr.pos <- load_input("ngs_plr.pos")
    ngs_baf <- load_input("ngs_baf")
    ngs_baf.pos <- load_input("ngs_baf.pos")
    
    # Determine sample names (sampname_qc) from files or list names
    sampname_qc <- NULL
    if (file.exists("sampname_qc.rds")) {
      sampname_qc <- readRDS("sampname_qc.rds")
    } else if (file.exists("sampname_qc.txt")) {
      sampname_qc <- readLines("sampname_qc.txt")
    } else if (file.exists("sampname_qc.rda")) {
      env <- new.env()
      load("sampname_qc.rda", envir = env)
      sampname_qc <- get(ls(env)[1], envir = env)
    } else if (!is.null(names(ngs_plr))) {
      sampname_qc <- names(ngs_plr)
    } else {
      sampname_qc <- paste0("sample_", seq_along(ngs_plr))
    }
    
    # Define project name
    projectname <- 'icnv.demo.ngs.'
    
    # Open PDF device to capture all visualization outputs
    pdf(paste0(projectname, "plots.pdf"), width = 10, height = 8)
    
    # 1. Run NGS-only CNV detection using iCNV_detection with CN=0
    icnv_res0_ngs <- iCNV_detection(ngs_plr=ngs_plr, ngs_baf = ngs_baf, 
                                 ngs_plr.pos = ngs_plr.pos,ngs_baf.pos = ngs_baf.pos,
                                 projname=projectname,CN=0,mu=c(-3,0,2),cap=TRUE,visual = 2)
    
    # 2. Format output using output_list
    icnv.output <- output_list(icnv_res0_ngs,sampname_qc,CN=0)
    print(head(icnv.output))
    
    # 3. Plot results using plotHMMscore
    plotHMMscore(icnv_res0_ngs,title=projectname)
    
    # Close PDF device
    dev.off()
    
    # Save meaningful results to files
    saveRDS(icnv_res0_ngs, file = paste0(projectname, "icnv_res0_ngs.rds"))
    write.csv(icnv.output, file = paste0(projectname, "icnv_output.csv"), row.names = FALSE)

    writeLines(c(
        '"BIOC_ICNV_NGS_ONLY_CNV_DETECTION":',
        paste0('    iCNV: ', as.character(packageVersion('iCNV')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ngs_only_cnv_detection.csv versions.yml
    """
}

workflow BIOC_ICNV_NGS_ONLY_CNV_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ngs_plr, ngs_plr.pos, ngs_baf, ngs_baf.pos ] ]

    main:
    BIOC_ICNV_NGS_ONLY_CNV_DETECTION(ch_input)

    emit:
    tables   = BIOC_ICNV_NGS_ONLY_CNV_DETECTION.out.tables
    plots    = BIOC_ICNV_NGS_ONLY_CNV_DETECTION.out.plots
    objects  = BIOC_ICNV_NGS_ONLY_CNV_DETECTION.out.objects
    versions = BIOC_ICNV_NGS_ONLY_CNV_DETECTION.out.versions
}
