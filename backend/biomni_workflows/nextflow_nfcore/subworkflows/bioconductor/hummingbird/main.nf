#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hummingbird — dmr_detection_and_visualization
// Detect and visualize differentially methylated regions (DMRs) from WGBS or RRBS data using a Bayesian HMM.
// Input: normM, normUM, abnormM, abnormUM, pos
// Container: quay.io/biocontainers/bioconductor-hummingbird:1.20.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, SummarizedExperiment, hummingbird
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Format input matrices and CpG positions into SummarizedExperiment objects for control and case groups
//  * 2. [Core Analysis] Execute the EM algorithm using hummingbirdEM to infer methylation states
//  * 3. [Core Analysis] Apply post-adjustment criteria (minimum length, minimum CpGs, maximum gap) using hummingbirdPostAdjustment to refine DMRs
//  * 4. [Visualization & Output] Visualize the observations and predictions for a specific genomic region using hummingbirdGraph

nextflow.enable.dsl = 2

process BIOC_HUMMINGBIRD_DMR_DETECTION_AND_VISUALIZATION {
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
    .bm_deps <- c("GenomicRanges", "hummingbird")
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
        
    library(GenomicRanges)
    library(hummingbird)
    
    # Helper function to robustly load input files from the working directory
    find_and_read <- function(base_name) {
      extensions <- c("", ".rds", ".csv", ".tsv", ".txt")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
            return(readRDS(file_path))
          } else if (grepl("\\\\.csv\$", file_path, ignore.case = TRUE)) {
            return(as.matrix(read.csv(file_path, header = TRUE)))
          } else if (grepl("\\\\.tsv\$|\\\\.txt\$", file_path, ignore.case = TRUE)) {
            return(as.matrix(read.table(file_path, header = TRUE)))
          } else {
            res <- tryCatch(readRDS(file_path), error = function(e) NULL)
            if (!is.null(res)) return(res)
            res <- tryCatch(as.matrix(read.table(file_path, header = TRUE)), error = function(e) NULL)
            if (!is.null(res)) return(res)
          }
        }
      }
      stop(paste("Required input file not found:", base_name))
    }
    
    # Load user inputs
    normM <- find_and_read("normM")
    normUM <- find_and_read("normUM")
    abnormM <- find_and_read("abnormM")
    abnormUM <- find_and_read("abnormUM")
    pos <- find_and_read("pos")
    
    # Format pos as a vector
    if (is.matrix(pos) || is.data.frame(pos)) {
      pos <- pos[, 1]
    }
    
    # Format input matrices and CpG positions into SummarizedExperiment objects
    assaysControl <- list(normM = normM, normUM = normUM)
    assaysCase <- list(abnormM = abnormM, abnormUM = abnormUM)
    exampleSEControl <- SummarizedExperiment(assaysControl, 
                                            rowRanges = GPos("chrUn", pos))
    exampleSECase <- SummarizedExperiment(assaysCase, 
                                        rowRanges = GPos("chrUn", pos))
    
    # Execute the EM algorithm using hummingbirdEM to infer methylation states
    emInfo <- hummingbirdEM(experimentInfoControl = exampleSEControl, 
                            experimentInfoCase = exampleSECase, binSize = 40)
    
    # Apply post-adjustment criteria using hummingbirdPostAdjustment to refine DMRs
    postAdjInfo <- hummingbirdPostAdjustment(
        experimentInfoControl = exampleSEControl, 
        experimentInfoCase = exampleSECase, 
        emInfo = emInfo, minCpGs = 10, 
        minLength = 100, maxGap = 300)
    
    # Save results to files
    saveRDS(emInfo, "emInfo.rds")
    saveRDS(postAdjInfo, "postAdjInfo.rds")
    
    if (!is.null(postAdjInfo\$DMRs)) {
      write.csv(as.data.frame(postAdjInfo\$DMRs), "detected_DMRs.csv", row.names = FALSE)
    }
    
    # Visualize the observations and predictions for a specific genomic region
    pdf("hummingbird_plots.pdf", width = 10, height = 8)
    if (!is.null(postAdjInfo\$DMRs) && length(postAdjInfo\$DMRs) > 0) {
      tryCatch({
        first_dmr <- postAdjInfo\$DMRs[1]
        hummingbirdGraph(experimentInfoControl = exampleSEControl, 
                        experimentInfoCase = exampleSECase, 
                        postAdjInfoDMRs = postAdjInfo\$DMRs, 
                        coord1 = start(first_dmr), coord2 = end(first_dmr))
      }, error = function(e) {
        warning("Could not plot the first detected DMR.")
      })
    } else {
      warning("No DMRs detected to plot.")
    }
    dev.off()

    writeLines(c(
        '"BIOC_HUMMINGBIRD_DMR_DETECTION_AND_VISUALIZATION":',
        paste0('    hummingbird: ', as.character(packageVersion('hummingbird')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmr_detection_and_visualization.csv versions.yml
    """
}

workflow BIOC_HUMMINGBIRD_DMR_DETECTION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ normM, normUM, abnormM, abnormUM, pos ] ]

    main:
    BIOC_HUMMINGBIRD_DMR_DETECTION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_HUMMINGBIRD_DMR_DETECTION_AND_VISUALIZATION.out.tables
    plots    = BIOC_HUMMINGBIRD_DMR_DETECTION_AND_VISUALIZATION.out.plots
    objects  = BIOC_HUMMINGBIRD_DMR_DETECTION_AND_VISUALIZATION.out.objects
    versions = BIOC_HUMMINGBIRD_DMR_DETECTION_AND_VISUALIZATION.out.versions
}
