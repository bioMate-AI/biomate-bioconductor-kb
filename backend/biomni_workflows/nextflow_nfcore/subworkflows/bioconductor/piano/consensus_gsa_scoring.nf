#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: piano — consensus_gsa_scoring
// Run multiple GSA methods on the same dataset and combine their results into a consensus score and heatmap.
// Input: mapGO, myTval, myPval, myFC
// Container: quay.io/biocontainers/bioconductor-piano:2.26.0--r45hdfd78af_0
// R packages: piano
// Bioconductor: 3.20 | R: 4.4
// Requires: piano
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load gene set collection using loadGSC
//  * 2. [Core Analysis] Run multiple GSA analyses with different geneSetStat methods using runGSA
//  * 3. [Visualization & Output] Combine results and plot a consensus heatmap using consensusHeatmap

nextflow.enable.dsl = 2

process BIOC_PIANO_CONSENSUS_GSA_SCORING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("piano")
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
    
    # Load required library
    library(piano)
    
    # Helper function to load files robustly from the working directory
    load_file <- function(filename) {
      # Try exact match first
      if (file.exists(filename)) {
        res <- try(readRDS(filename), silent = TRUE)
        if (!inherits(res, "try-error")) return(res)
        res <- try(read.csv(filename, header = TRUE, stringsAsFactors = FALSE), silent = TRUE)
        if (!inherits(res, "try-error")) return(res)
      }
      # Try with common extensions
      for (ext in c(".rds", ".csv", ".tsv", ".txt")) {
        fn <- paste0(filename, ext)
        if (file.exists(fn)) {
          if (ext == ".rds") {
            return(readRDS(fn))
          } else if (ext == ".csv") {
            return(read.csv(fn, header = TRUE, stringsAsFactors = FALSE))
          } else {
            return(read.delim(fn, header = TRUE, stringsAsFactors = FALSE))
          }
        }
      }
      stop(paste("Could not find or read file:", filename))
    }
    
    # Helper to convert loaded data frames/matrices to named vectors
    to_named_vector <- function(obj) {
      if (is.vector(obj) && !is.null(names(obj))) {
        return(obj)
      }
      if (is.data.frame(obj)) {
        if (!all(rownames(obj) == as.character(1:nrow(obj)))) {
          vec <- obj[[1]]
          names(vec) <- rownames(obj)
          return(vec)
        } else if (ncol(obj) >= 2) {
          vec <- obj[[2]]
          names(vec) <- obj[[1]]
          return(vec)
        }
      }
      if (is.matrix(obj) || is.array(obj)) {
        vec <- as.vector(obj)
        names(vec) <- rownames(obj)
        return(vec)
      }
      return(as.vector(obj))
    }
    
    # Load user inputs from the working directory
    mapGO_raw <- load_file("mapGO")
    myTval_raw <- load_file("myTval")
    myPval_raw <- load_file("myPval")
    myFC_raw <- load_file("myFC")
    
    # Format inputs appropriately
    mapGO <- mapGO_raw
    myTval <- to_named_vector(myTval_raw)
    myPval <- to_named_vector(myPval_raw)
    myFC <- to_named_vector(myFC_raw)
    
    # 1. Load gene set collection using loadGSC
    myGsc <- loadGSC(mapGO)
    
    # 2. Run multiple GSA analyses with different geneSetStat methods using runGSA
    gsaRes1 <- runGSA(myTval,geneSetStat="mean",gsc=myGsc,
                      nPerm=1000,gsSizeLim=c(10,800))
    gsaRes2 <- runGSA(myTval,geneSetStat="median",gsc=myGsc,
                      nPerm=1000,gsSizeLim=c(10,800))
    gsaRes3 <- runGSA(myTval,geneSetStat="sum",gsc=myGsc,
                      nPerm=1000,gsSizeLim=c(10,800))
    gsaRes4 <- runGSA(myTval,geneSetStat="maxmean",gsc=myGsc,
                      nPerm=1000,gsSizeLim=c(10,800))
    gsaRes5 <- runGSA(myPval,myFC,geneSetStat="fisher",gsc=myGsc,
                      nPerm=1000,gsSizeLim=c(10,800))
    gsaRes6 <- runGSA(myPval,myFC,geneSetStat="stouffer",gsc=myGsc,
                      nPerm=1000,gsSizeLim=c(10,800))
    gsaRes7 <- runGSA(myPval,myFC,geneSetStat="tailStrength",gsc=myGsc,
                      nPerm=1000,gsSizeLim=c(10,800))
    
    resList <- list(gsaRes1,gsaRes2,gsaRes3,gsaRes4,gsaRes5,gsaRes6,gsaRes7)
    names(resList) <- c("mean","median","sum","maxmean","fisher",
                        "stouffer","tailStrength")
    
    # Save the raw GSA results list
    saveRDS(resList, file = "gsa_results_list.rds")
    
    # 3. Combine results and plot a consensus heatmap using consensusHeatmap
    pdf("consensus_heatmap.pdf", width = 12, height = 10)
    ch <- consensusHeatmap(resList,cutoff=30,method="mean")
    dev.off()
    
    # Extract and save the consensus p-value matrix
    pMat <- ch\$pMat
    write.csv(pMat, file = "consensus_p_matrix.csv", row.names = TRUE)
    
    # Save the consensus heatmap object
    saveRDS(ch, file = "consensus_heatmap_object.rds")
    
    cat("Pipeline completed successfully.\n")
    cat("Outputs saved:\n")
    cat("  - GSA results list: gsa_results_list.rds\n")
    cat("  - Consensus heatmap plot: consensus_heatmap.pdf\n")
    cat("  - Consensus p-value matrix: consensus_p_matrix.csv\n")
    cat("  - Consensus heatmap object: consensus_heatmap_object.rds\n")

    writeLines(c(
        '"BIOC_PIANO_CONSENSUS_GSA_SCORING":',
        paste0('    piano: ', as.character(packageVersion('piano')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_consensus_gsa_scoring.csv versions.yml
    """
}

workflow BIOC_PIANO_CONSENSUS_GSA_SCORING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mapGO, myTval, myPval, myFC ] ]

    main:
    BIOC_PIANO_CONSENSUS_GSA_SCORING(ch_input)

    emit:
    tables   = BIOC_PIANO_CONSENSUS_GSA_SCORING.out.tables
    plots    = BIOC_PIANO_CONSENSUS_GSA_SCORING.out.plots
    objects  = BIOC_PIANO_CONSENSUS_GSA_SCORING.out.objects
    versions = BIOC_PIANO_CONSENSUS_GSA_SCORING.out.versions
}
