#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sampleClassifier — microarray_classification
// Classify microarray gene expression profiles using a reference matrix and visualize the results.
// Input: micro_refmat, micro_testmat
// Container: quay.io/biocontainers/bioconductor-sampleclassifier:1.30.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: sampleClassifier
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load reference and query microarray matrices
//  * 2. [Core Analysis] Classify profiles using the Shared Marker Genes (SMG) algorithm with classifyProfile()
//  * 3. [Visualization & Output] Visualize classification results as a heatmap using get.heatmap()
//  * 4. [Core Analysis] Classify profiles using Support Vector Machines (SVM) with classifyProfile.svm()

nextflow.enable.dsl = 2

process BIOC_SAMPLECLASSIFIER_MICROARRAY_CLASSIFICATION {
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
    
    # Helper function to find and read input files in various formats
    find_and_read <- function(base_name) {
      extensions <- c(".rds", ".csv", ".tsv", ".txt")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          message(paste("Reading input file:", file_path))
          if (ext == ".rds") {
            return(readRDS(file_path))
          } else if (ext == ".csv") {
            return(as.matrix(read.csv(file_path, row.names = 1, check.names = FALSE)))
          } else if (ext %in% c(".tsv", ".txt")) {
            return(as.matrix(read.delim(file_path, row.names = 1, check.names = FALSE)))
          }
        }
      }
      stop(paste("Error: Could not find input file for", base_name, "with supported extensions (.rds, .csv, .tsv, .txt) in the working directory."))
    }
    
    # 1. Load reference and query microarray matrices
    micro_refmat <- find_and_read("micro_refmat")
    micro_testmat <- find_and_read("micro_testmat")
    
    # 2. Classify profiles using the Shared Marker Genes (SMG) algorithm
    message("Running classifyProfile (SMG)...")
    res1.list <- classifyProfile(ref_matrix=micro_refmat, query_mat=micro_testmat,
                                 chip1="hgu133plus2", chip2="hgu133a", write2File=FALSE)
    
    # Save SMG classification results
    saveRDS(res1.list, "smg_results.rds")
    message("SMG results saved to 'smg_results.rds'")
    
    # 3. Visualize classification results as a heatmap
    message("Generating heatmap...")
    pdf("heatmap_microarray.pdf", width = 10, height = 8)
    get.heatmap(res1.list)
    dev.off()
    message("Heatmap saved to 'heatmap_microarray.pdf'")
    
    # 4. Classify profiles using Support Vector Machines (SVM)
    message("Running classifyProfile.svm...")
    res1.svm.df <- classifyProfile.svm(ref_matrix=micro_refmat, query_mat=micro_testmat,
                                       chip1="hgu133plus2", chip2="hgu133a")
    
    # Save SVM classification results
    write.csv(res1.svm.df, "svm_results.csv", row.names = FALSE)
    message("SVM results saved to 'svm_results.csv'")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SAMPLECLASSIFIER_MICROARRAY_CLASSIFICATION":',
        paste0('    sampleClassifier: ', as.character(packageVersion('sampleClassifier')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_classification.csv versions.yml
    """
}

workflow BIOC_SAMPLECLASSIFIER_MICROARRAY_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ micro_refmat, micro_testmat ] ]

    main:
    BIOC_SAMPLECLASSIFIER_MICROARRAY_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_SAMPLECLASSIFIER_MICROARRAY_CLASSIFICATION.out.tables
    plots    = BIOC_SAMPLECLASSIFIER_MICROARRAY_CLASSIFICATION.out.plots
    objects  = BIOC_SAMPLECLASSIFIER_MICROARRAY_CLASSIFICATION.out.objects
    versions = BIOC_SAMPLECLASSIFIER_MICROARRAY_CLASSIFICATION.out.versions
}
