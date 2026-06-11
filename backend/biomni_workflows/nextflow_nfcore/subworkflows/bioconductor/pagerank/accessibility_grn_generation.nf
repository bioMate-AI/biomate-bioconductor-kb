#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pageRank — accessibility_grn_generation
// Build a gene regulatory network from chromatin accessibility peaks and regulator position frequency matrices (PFMs).
// Input: peaks.csv, regulators.csv
// Container: quay.io/biocontainers/bioconductor-pagerank:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, GenomicFeatures, GenomicRanges, TFBSTools, TxDb.Hsapiens.UCSC.hg19.knownGene, annotate, motifmatchr, org.Hs.eg.db, pageRank
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define peak regions, promoter regions, and regulator PFMs
//  * 2. [Input & Preparation] Build the network using accessibility_network

nextflow.enable.dsl = 2

process BIOC_PAGERANK_ACCESSIBILITY_GRN_GENERATION {
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
    
    # 1. Read user input files
    # Read peaks.csv and format as a data frame with genomic coordinates and row names
    table_raw <- read.csv("peaks.csv", stringsAsFactors = FALSE)
    if (colnames(table_raw)[1] == "" || colnames(table_raw)[1] == "X") {
      rownames(table_raw) <- table_raw[, 1]
      table_raw <- table_raw[, -1]
    }
    table <- data.frame(
      Chr = as.character(table_raw\$Chr),
      Start = as.numeric(table_raw\$Start),
      End = as.numeric(table_raw\$End),
      stringsAsFactors = FALSE
    )
    if (!is.null(rownames(table_raw))) {
      rownames(table) <- rownames(table_raw)
    } else {
      rownames(table) <- as.character(1:nrow(table))
    }
    
    # Read regulators.csv and format as a character vector
    reg_raw <- read.csv("regulators.csv", header = FALSE, stringsAsFactors = FALSE)
    regulators <- as.character(reg_raw[[1]])
    # Strip potential header if present
    if (length(regulators) > 0 && regulators[1] %in% c("regulators", "regulator", "x", "val", "name", "Regulator")) {
      regulators <- regulators[-1]
    }
    
    # 2. Define promoter regions
    promoter <- promoters(genes(TxDb.Hsapiens.UCSC.hg19.knownGene))
    names(promoter) <- getSYMBOL(names(promoter), data="org.Hs.eg")
    promoter <- promoter[!is.na(names(promoter))]
    
    # 3. Get regulator position frequency matrix (PFM) list
    pfm <- getMatrixSet(JASPAR2018, list(species="Homo sapiens"))
    pfm <- pfm[unlist(lapply(pfm, function(x) name(x))) %in% regulators]
    
    # 4. Build the network using accessibility_network
    network <- accessibility_network(table, promoter, pfm, "BSgenome.Hsapiens.UCSC.hg19")
    
    # 5. Write output to a CSV file
    write.csv(network, "accessibility_network.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_PAGERANK_ACCESSIBILITY_GRN_GENERATION":',
        paste0('    pageRank: ', as.character(packageVersion('pageRank')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_accessibility_grn_generation.csv versions.yml
    """
}

workflow BIOC_PAGERANK_ACCESSIBILITY_GRN_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks.csv, regulators.csv ] ]

    main:
    BIOC_PAGERANK_ACCESSIBILITY_GRN_GENERATION(ch_input)

    emit:
    tables   = BIOC_PAGERANK_ACCESSIBILITY_GRN_GENERATION.out.tables
    plots    = BIOC_PAGERANK_ACCESSIBILITY_GRN_GENERATION.out.plots
    objects  = BIOC_PAGERANK_ACCESSIBILITY_GRN_GENERATION.out.objects
    versions = BIOC_PAGERANK_ACCESSIBILITY_GRN_GENERATION.out.versions
}
