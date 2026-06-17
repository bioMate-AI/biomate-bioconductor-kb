#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GENIE3 — targeted_network_inference
// Infer a gene regulatory network while restricting the candidate regulators to a specific subset of genes or defining target-specific regulator sets.
// Input: exprMatr, regulators
// Container: quay.io/biocontainers/bioconductor-genie3:1.32.0--r45h01b2380_0
// R packages: GENIE3
// Bioconductor: 3.20 | R: 4.4
// Requires: GENIE3
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare the gene expression matrix and define the candidate regulators
//  * 2. [Core Analysis] Run GENIE3 with the restricted regulator set (globally or per-target)
//  * 3. [Core Analysis] Extract the resulting regulatory links

nextflow.enable.dsl = 2

process BIOC_GENIE3_TARGETED_NETWORK_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("GENIE3")
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
        library(GENIE3)
        
        # ==========================================
        # 1. Load User Input Files
        # ==========================================
        
        # Load expression matrix (exprMatr)
        if (file.exists("exprMatr.rds")) {
          exprMatr <- readRDS("exprMatr.rds")
        } else if (file.exists("exprMatr.csv")) {
          exprMatr <- as.matrix(read.csv("exprMatr.csv", row.names=1, check.names=FALSE))
        } else if (file.exists("exprMatr.tsv")) {
          exprMatr <- as.matrix(read.delim("exprMatr.tsv", row.names=1, check.names=FALSE))
        } else {
          stop("Error: Expression matrix file (exprMatr.rds, exprMatr.csv, or exprMatr.tsv) not found in the working directory.")
        }
        
        # Ensure exprMatr is a numeric matrix
        if (!is.matrix(exprMatr)) {
          exprMatr <- as.matrix(exprMatr)
        }
        mode(exprMatr) <- "numeric"
        
        # Load regulators (can be a vector or a list mapping targets to regulators)
        if (file.exists("regulators.rds")) {
          regulators <- readRDS("regulators.rds")
        } else if (file.exists("regulators.txt")) {
          regulators <- readLines("regulators.txt")
          regulators <- regulators[regulators != ""]
        } else if (file.exists("regulators.csv")) {
          regulators_df <- read.csv("regulators.csv", header=FALSE, stringsAsFactors=FALSE)
          regulators <- as.character(regulators_df[[1]])
        } else {
          stop("Error: Regulators file (regulators.rds, regulators.txt, or regulators.csv) not found in the working directory.")
        }
        
        # ==========================================
        # 2. Run GENIE3 Targeted Network Inference
        # ==========================================
        
        if (is.list(regulators)) {
          # Case A: Regulators is a list mapping target genes to potential regulators
          message("Running GENIE3 with target-specific regulator list...")
          
          set.seed(123)
          weightList <- GENIE3(exprMatr, nCores=1, targets=names(regulators), regulators=regulators, returnMatrix=TRUE)
          
          # Save results
          saveRDS(weightList, "weightList.rds")
          message("Target-specific regulatory weights saved to 'weightList.rds'.")
          
          weight_obj <- weightList
        
        } else {
          # Case B: Regulators is a vector of candidate regulator genes
          message("Running GENIE3 with global candidate regulator vector...")
          
          set.seed(123)
          weightMat <- GENIE3(exprMatr, regulators=regulators)
          
          # Save weight matrix
          saveRDS(weightMat, "weightMat.rds")
          write.csv(weightMat, "weightMat.csv")
          message("Regulatory weight matrix saved to 'weightMat.rds' and 'weightMat.csv'.")
          
          weight_obj <- weightMat
        }
        
        # ==========================================
        # 3. Extract Regulatory Links
        # ==========================================
        message("Extracting regulatory links...")
        
        # Get all regulatory links
        linkList <- getLinkList(weight_obj)
        write.csv(linkList, "linkList_all.csv", row.names=FALSE)
        
        # Get top-ranked links (e.g., top 50)
        num_links_to_report <- min(50, nrow(linkList))
        linkList_top <- getLinkList(weight_obj, reportMax=num_links_to_report)
        write.csv(linkList_top, "linkList_top.csv", row.names=FALSE)
        
        # Get links with weight higher than a threshold (e.g., 0.01)
        linkList_threshold <- getLinkList(weight_obj, threshold=0.01)
        write.csv(linkList_threshold, "linkList_threshold_0.01.csv", row.names=FALSE)
        
        message("Regulatory link lists saved to CSV files.")

    writeLines(c(
        '"BIOC_GENIE3_TARGETED_NETWORK_INFERENCE":',
        paste0('    GENIE3: ', as.character(packageVersion('GENIE3')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_targeted_network_inference.csv versions.yml
    """
}

workflow BIOC_GENIE3_TARGETED_NETWORK_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprMatr, regulators ] ]

    main:
    BIOC_GENIE3_TARGETED_NETWORK_INFERENCE(ch_input)

    emit:
    tables   = BIOC_GENIE3_TARGETED_NETWORK_INFERENCE.out.tables
    plots    = BIOC_GENIE3_TARGETED_NETWORK_INFERENCE.out.plots
    objects  = BIOC_GENIE3_TARGETED_NETWORK_INFERENCE.out.objects
    versions = BIOC_GENIE3_TARGETED_NETWORK_INFERENCE.out.versions
}
