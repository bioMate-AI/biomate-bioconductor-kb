#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sampleClassifier — rnaseq_classification
// Classify RNA-seq gene expression profiles using a reference matrix and visualize the results.
// Input: rnaseq_refmat, rnaseq_testmat
// Container: quay.io/biocontainers/bioconductor-sampleclassifier:1.30.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: sampleClassifier
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load reference and query RNA-seq matrices
//  * 2. [Core Analysis] Classify profiles using the Shared Marker Genes (SMG) algorithm with classifyProfile.rnaseq()
//  * 3. [Visualization & Output] Visualize classification results as a heatmap using get.heatmap()
//  * 4. [Core Analysis] Classify profiles using Support Vector Machines (SVM) with classifyProfile.rnaseq.svm()

nextflow.enable.dsl = 2

process BIOC_SAMPLECLASSIFIER_RNASEQ_CLASSIFICATION {
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
    .bm_deps <- c("sampleClassifier")
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
    library(sampleClassifier)
    
    # Helper function to read matrix from various possible formats in the working directory
    read_matrix <- function(base_name) {
      possible_files <- c(
        base_name,
        paste0(base_name, ".csv"),
        paste0(base_name, ".tsv"),
        paste0(base_name, ".txt")
      )
      
      for (f in possible_files) {
        if (file.exists(f)) {
          # Determine separator based on file extension
          ext <- tools::file_ext(f)
          sep <- if (ext %in% c("tsv", "txt")) "\t" else ","
          
          message(paste("Reading", base_name, "from", f))
          mat <- as.matrix(read.table(f, header = TRUE, sep = sep, row.names = 1, check.names = FALSE))
          return(mat)
        }
      }
      stop(paste("Error: Could not find input file for", base_name, "in the working directory."))
    }
    
    # 1. Load reference and query RNA-seq matrices
    rnaseq_refmat <- read_matrix("rnaseq_refmat")
    rnaseq_testmat <- read_matrix("rnaseq_testmat")
    
    # 2. Classify profiles using the Shared Marker Genes (SMG) algorithm
    message("Running classifyProfile.rnaseq...")
    res2.list <- classifyProfile.rnaseq(
      ref_matrix = rnaseq_refmat, 
      query_mat = rnaseq_testmat, 
      gene.ids.type = "ensembl", 
      write2File = FALSE
    )
    
    # Save the full SMG classification list as an RDS object
    saveRDS(res2.list, "rnaseq_classification_smg_list.rds")
    
    # Extract and save top hits for convenience
    tryCatch({
      top_hits <- do.call(rbind, lapply(names(res2.list), function(name) {
        df <- res2.list[[name]]
        if (!is.null(df) && nrow(df) > 0) {
          data.frame(
            Query = name,
            Top_Hit = df\$Hits[1],
            Score = df\$Score[1],
            Ratio = df\$Ratio[1],
            stringsAsFactors = FALSE
          )
        } else {
          NULL
        }
      }))
      if (!is.null(top_hits)) {
        write.csv(top_hits, "rnaseq_classification_smg_top_hits.csv", row.names = FALSE)
        message("Saved SMG top hits to 'rnaseq_classification_smg_top_hits.csv'")
      }
    }, error = function(e) {
      warning("Could not extract top hits table: ", e\$message)
    })
    
    # 3. Visualize classification results as a heatmap
    message("Generating heatmap...")
    pdf("classification_heatmap.pdf", width = 10, height = 8)
    tryCatch({
      get.heatmap(res2.list)
    }, error = function(e) {
      warning("Failed to generate heatmap: ", e\$message)
    })
    dev.off()
    
    # 4. Classify profiles using Support Vector Machines (SVM)
    message("Running classifyProfile.rnaseq.svm...")
    res2.svm.df <- classifyProfile.rnaseq.svm(
      ref_matrix = rnaseq_refmat, 
      query_mat = rnaseq_testmat, 
      gene.ids.type = "ensembl"
    )
    
    # Save SVM classification results
    write.csv(res2.svm.df, "rnaseq_classification_svm_results.csv", row.names = FALSE)
    message("Saved SVM results to 'rnaseq_classification_svm_results.csv'")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SAMPLECLASSIFIER_RNASEQ_CLASSIFICATION":',
        paste0('    sampleClassifier: ', as.character(packageVersion('sampleClassifier')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseq_classification.csv versions.yml
    """
}

workflow BIOC_SAMPLECLASSIFIER_RNASEQ_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rnaseq_refmat, rnaseq_testmat ] ]

    main:
    BIOC_SAMPLECLASSIFIER_RNASEQ_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_SAMPLECLASSIFIER_RNASEQ_CLASSIFICATION.out.tables
    plots    = BIOC_SAMPLECLASSIFIER_RNASEQ_CLASSIFICATION.out.plots
    objects  = BIOC_SAMPLECLASSIFIER_RNASEQ_CLASSIFICATION.out.objects
    versions = BIOC_SAMPLECLASSIFIER_RNASEQ_CLASSIFICATION.out.versions
}
