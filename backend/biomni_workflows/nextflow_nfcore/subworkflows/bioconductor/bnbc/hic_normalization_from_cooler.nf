#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bnbc — hic_normalization_from_cooler
// Import Hi-C data from .cooler/.mcool files and perform normalization and batch correction.
// Input: cools, hg19, colData
// Container: quay.io/biocontainers/bioconductor-bnbc:1.32.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomeInfoDb, S4Vectors, SummarizedExperiment, bnbc
// Visualizations: image plot
// QC: batch-effect correction, count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate genomic index using bnbc:::getChrIdx()
//  * 2. [Input & Preparation] Load chromosome interaction matrices into a ContactGroup using bnbc:::getChrCGFromCools()
//  * 3. [Core Analysis] Apply logCPM transformation using logCPM()
//  * 4. [Core Analysis] Smooth contact matrices using boxSmoother()
//  * 5. [Core Analysis] Perform cross-sample normalization and batch correction using bnbc()

nextflow.enable.dsl = 2

process BIOC_BNBC_HIC_NORMALIZATION_FROM_COOLER {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("bnbc", "GenomeInfoDb", "S4Vectors", "SummarizedExperiment")
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
    library(bnbc)
    library(SummarizedExperiment)
    library(GenomeInfoDb)
    library(S4Vectors)
    
    # ==========================================
    # 1. USER INPUTS & PREPARATION
    # ==========================================
    
    # Find .mcool files in the working directory
    cools <- list.files(path = ".", pattern = "\\\\.mcool\$", full.names = TRUE)
    if (length(cools) < 2) {
      stop("Error: This workflow requires at least 2 .mcool files in the working directory.")
    }
    
    # Load hg19 seqlengths or BSgenome object
    if (file.exists("hg19.rds")) {
      hg19_in <- readRDS("hg19.rds")
    } else if (file.exists("seqlengths.rds")) {
      hg19_in <- readRDS("seqlengths.rds")
    } else {
      stop("Error: Could not find hg19.rds or seqlengths.rds in the working directory.")
    }
    
    # Ensure hg19 is compatible with seqlengths(hg19)
    if (inherits(hg19_in, "Seqinfo") || inherits(hg19_in, "BSgenome")) {
      hg19 <- hg19_in
    } else if (is.numeric(hg19_in) && !is.null(names(hg19_in))) {
      hg19 <- GenomeInfoDb::Seqinfo(seqnames = names(hg19_in), seqlengths = hg19_in)
    } else {
      hg19 <- hg19_in
    }
    
    # Load colData
    if (file.exists("colData.rds")) {
      user_colData <- readRDS("colData.rds")
    } else if (file.exists("colData.csv")) {
      user_colData <- read.csv("colData.csv", row.names = 1)
      user_colData <- S4Vectors::DataFrame(user_colData)
    } else {
      stop("Error: Could not find colData.rds or colData.csv in the working directory.")
    }
    
    # Ensure Batch column exists and has at least two batches for ComBat
    if (!"Batch" %in% colnames(user_colData)) {
      user_colData\$Batch <- rep(c(1, 2), length.out = nrow(user_colData))
    }
    
    # Initialize cgEx as a SummarizedExperiment to hold colData
    cgEx <- SummarizedExperiment::SummarizedExperiment(colData = user_colData)
    
    # ==========================================
    # 2. RUN WORKFLOW (DOCUMENTED CODE)
    # ==========================================
    
    step <- 4e4
    ixns <- bnbc:::getChrIdx(seqlengths(hg19)["chr22"], "chr22", step)
    
    if (!dir.exists("tmp")) {
      dir.create("tmp")
    }
    
    cool.cg <- bnbc:::getChrCGFromCools(files = cools,
                                        chr = "chr22",
                                        step = step,
                                        index.gr = ixns,
                                        work.dir = "tmp",
                                        exp.name = "example",
                                        coldata = colData(cgEx))
    
    # Transition cgEx to the loaded ContactGroup
    cgEx <- cool.cg
    
    cgEx.cpm <- logCPM(cgEx)
    cgEx.smooth <- boxSmoother(cgEx.cpm, h=5)
    cgEx.bnbc <- bnbc(cgEx.smooth, batch=colData(cgEx.smooth)\$Batch,
                      threshold=1e7, step=4e4, nbands=11, verbose=FALSE)
    
    # ==========================================
    # 3. SAVE OUTPUTS
    # ==========================================
    
    # Save the final normalized ContactGroup object
    saveRDS(cgEx.bnbc, "cgEx_bnbc.rds")
    
    # Save raw and corrected contact matrices for downstream analysis
    raw_contacts <- contacts(cgEx)[[1]]
    corrected_contacts <- contacts(cgEx.bnbc)[[1]]
    saveRDS(raw_contacts, "raw_contacts_chr22.rds")
    saveRDS(corrected_contacts, "corrected_contacts_chr22.rds")
    
    # Generate a diagnostic plot comparing raw and corrected contacts
    pdf("normalization_comparison.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    image(raw_contacts[1:min(100, nrow(raw_contacts)), 1:min(100, ncol(raw_contacts))], 
          main = "Raw Contacts (Subset)", col = heat.colors(12))
    image(corrected_contacts[1:min(100, nrow(corrected_contacts)), 1:min(100, ncol(corrected_contacts))], 
          main = "BNBC Corrected (Subset)", col = heat.colors(12))
    dev.off()
    
    message("Workflow completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_BNBC_HIC_NORMALIZATION_FROM_COOLER":',
        paste0('    bnbc: ', as.character(packageVersion('bnbc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hic_normalization_from_cooler.csv versions.yml
    """
}

workflow BIOC_BNBC_HIC_NORMALIZATION_FROM_COOLER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cools, hg19, colData ] ]

    main:
    BIOC_BNBC_HIC_NORMALIZATION_FROM_COOLER(ch_input)

    emit:
    tables   = BIOC_BNBC_HIC_NORMALIZATION_FROM_COOLER.out.tables
    plots    = BIOC_BNBC_HIC_NORMALIZATION_FROM_COOLER.out.plots
    objects  = BIOC_BNBC_HIC_NORMALIZATION_FROM_COOLER.out.objects
    versions = BIOC_BNBC_HIC_NORMALIZATION_FROM_COOLER.out.versions
}
