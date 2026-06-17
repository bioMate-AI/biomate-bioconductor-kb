#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pageRank — conformation_grn_generation
// Build a gene regulatory network from chromosome conformation records and regulator position frequency matrices (PFMs).
// Input: conformation.csv, regulators.csv
// Container: quay.io/biocontainers/bioconductor-pagerank:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, GenomicFeatures, GenomicRanges, TFBSTools, TxDb.Hsapiens.UCSC.hg19.knownGene, annotate, motifmatchr, org.Hs.eg.db, pageRank
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define conformation interaction regions, promoter regions, and regulator PFMs
//  * 2. [Input & Preparation] Build the network using conformation_network

nextflow.enable.dsl = 2

process BIOC_PAGERANK_CONFORMATION_GRN_GENERATION {
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
    .bm_deps <- c("pageRank", "GenomicRanges", "GenomicFeatures", "TxDb.Hsapiens.UCSC.hg19.knownGene", "org.Hs.eg.db", "annotate", "JASPAR2018", "TFBSTools", "motifmatchr", "BSgenome.Hsapiens.UCSC.hg19")
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
    library(pageRank)
    library(GenomicRanges)
    library(GenomicFeatures)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(org.Hs.eg.db)
    library(annotate)
    library(JASPAR2018)
    library(TFBSTools)
    library(motifmatchr)
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    # 1. Read User Input Files
    # Read conformation.csv
    if (!file.exists("conformation.csv")) {
      stop("Error: conformation.csv not found in the working directory.")
    }
    table <- read.csv("conformation.csv", stringsAsFactors = FALSE)
    
    # Handle potential row names in the CSV
    if ("X" %in% colnames(table)) {
      rownames(table) <- table\$X
      table\$X <- NULL
    } else if ("row_names" %in% colnames(table)) {
      rownames(table) <- table\$row_names
      table\$row_names <- NULL
    }
    
    # Read regulators.csv
    if (!file.exists("regulators.csv")) {
      stop("Error: regulators.csv not found in the working directory.")
    }
    regulators_raw <- readLines("regulators.csv")
    # Clean up empty lines and comments
    regulators <- regulators_raw[regulators_raw != "" & !grepl("^#", regulators_raw)]
    # Strip potential header or quotes
    if (length(regulators) > 0 && regulators[1] %in% c("regulators", "regulator", "x", "V1")) {
      regulators <- regulators[-1]
    }
    regulators <- gsub('["\']', '', regulators)
    
    # 2. Define promoter regions
    promoter <- promoters(genes(TxDb.Hsapiens.UCSC.hg19.knownGene))
    names(promoter) <- getSYMBOL(names(promoter), data="org.Hs.eg")
    promoter <- promoter[!is.na(names(promoter))]
    
    # 3. Get regulator position frequency matrix (PFM) list
    pfm <- getMatrixSet(JASPAR2018, list(species="Homo sapiens"))
    pfm <- pfm[unlist(lapply(pfm, function(x) name(x))) %in% regulators]
    
    # 4. Build the network using conformation_network
    network <- conformation_network(table, promoter, pfm, "BSgenome.Hsapiens.UCSC.hg19")
    
    # 5. Write output to CSV
    write.csv(network, "conformation_network.csv", row.names = FALSE)
    cat("Workflow complete. Output written to conformation_network.csv\n")

    writeLines(c(
        '"BIOC_PAGERANK_CONFORMATION_GRN_GENERATION":',
        paste0('    pageRank: ', as.character(packageVersion('pageRank')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_conformation_grn_generation.csv versions.yml
    """
}

workflow BIOC_PAGERANK_CONFORMATION_GRN_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ conformation.csv, regulators.csv ] ]

    main:
    BIOC_PAGERANK_CONFORMATION_GRN_GENERATION(ch_input)

    emit:
    tables   = BIOC_PAGERANK_CONFORMATION_GRN_GENERATION.out.tables
    plots    = BIOC_PAGERANK_CONFORMATION_GRN_GENERATION.out.plots
    objects  = BIOC_PAGERANK_CONFORMATION_GRN_GENERATION.out.objects
    versions = BIOC_PAGERANK_CONFORMATION_GRN_GENERATION.out.versions
}
