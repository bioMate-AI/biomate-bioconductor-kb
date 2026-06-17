#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MGFR — marker_detection_rnaseq
// Detect tissue- or cell-type-specific marker genes from normalized RNA-seq expression data and return them as an R list.
// Input: expression_matrix.tsv, sample_classes.txt
// Container: quay.io/biocontainers/bioconductor-mgfr:1.32.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MGFR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the normalized expression matrix and sample classes
//  * 2. [Input & Preparation] Run marker gene detection and annotation using
//  * 3. [Input & Preparation] Retrieve and inspect the identified marker genes

nextflow.enable.dsl = 2

process BIOC_MGFR_MARKER_DETECTION_RNASEQ {
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
    .bm_deps <- c("MGFR")
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
    library(MGFR)
    
    # --- Load the normalized expression matrix and sample classes ---
    if (!file.exists("expression_matrix.tsv")) {
      stop("Error: expression_matrix.tsv not found in the working directory.")
    }
    if (!file.exists("sample_classes.txt")) {
      stop("Error: sample_classes.txt not found in the working directory.")
    }
    
    # Read expression matrix
    ref.mat <- as.matrix(read.table(
      "expression_matrix.tsv",
      header = TRUE,
      sep = "\t",
      row.names = 1,
      check.names = FALSE
    ))
    
    # Read sample classes
    classes <- readLines("sample_classes.txt")
    classes <- classes[classes != ""]
    
    if (length(classes) != ncol(ref.mat)) {
      stop(sprintf(
        "Error: Number of classes in sample_classes.txt (%d) does not match the number of columns in expression_matrix.tsv (%d).",
        length(classes),
        ncol(ref.mat)
      ))
    }
    
    # Assign classes to colnames to match the vignette's class.vec specification
    colnames(ref.mat) <- classes
    
    # --- Run marker gene detection and annotation using ---
    # Wrap in tryCatch to handle potential biomaRt connectivity issues when annotate=TRUE
    markers.list <- tryCatch({
      message("Attempting marker gene detection with biomaRt annotation...")
      getMarkerGenes.rnaseq(
        ref.mat,
        class.vec = colnames(ref.mat),
        samples2compare = "all",
        annotate = TRUE,
        gene.ids.type = "ensembl",
        score.cutoff = 1
      )
    }, error = function(e) {
      message("Warning: Annotation failed (likely due to biomaRt/internet connectivity issues).")
      message("Error details: ", e\$message)
      message("Retrying marker gene detection with annotate=FALSE...")
      getMarkerGenes.rnaseq(
        ref.mat,
        class.vec = colnames(ref.mat),
        samples2compare = "all",
        annotate = FALSE,
        gene.ids.type = "ensembl",
        score.cutoff = 1
      )
    })
    
    # --- Retrieve and inspect the identified marker genes ---
    message("Identified marker groups:")
    print(names(markers.list))
    
    # Save the raw list object
    saveRDS(markers.list, "markers_list.rds")
    
    # Format and export the marker genes to a structured CSV file
    export_list <- list()
    for (class_name in names(markers.list)) {
      markers <- markers.list[[class_name]]
      if (length(markers) > 0) {
        # Split the colon-separated output format: "GeneID : Symbol : EntrezID : Score"
        parts <- strsplit(markers, " : ")
        df <- do.call(rbind, lapply(parts, function(x) {
          if (length(x) < 4) {
            x <- c(x, rep(NA, 4 - length(x)))
          }
          x[1:4]
        }))
        df <- as.data.frame(df, stringsAsFactors = FALSE)
        colnames(df) <- c("Gene_ID", "Gene_Symbol", "Entrez_ID", "Specificity_Score")
        df\$Class <- class_name
        export_list[[class_name]] <- df
      }
    }
    
    if (length(export_list) > 0) {
      all_markers_df <- do.call(rbind, export_list)
      write.csv(all_markers_df, "marker_genes_identified.csv", row.names = FALSE)
      message("Successfully saved marker genes to 'marker_genes_identified.csv' and 'markers_list.rds'.")
    } else {
      message("No marker genes were identified matching the criteria.")
    }

    writeLines(c(
        '"BIOC_MGFR_MARKER_DETECTION_RNASEQ":',
        paste0('    MGFR: ', as.character(packageVersion('MGFR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_marker_detection_rnaseq.csv versions.yml
    """
}

workflow BIOC_MGFR_MARKER_DETECTION_RNASEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.tsv, sample_classes.txt ] ]

    main:
    BIOC_MGFR_MARKER_DETECTION_RNASEQ(ch_input)

    emit:
    tables   = BIOC_MGFR_MARKER_DETECTION_RNASEQ.out.tables
    plots    = BIOC_MGFR_MARKER_DETECTION_RNASEQ.out.plots
    objects  = BIOC_MGFR_MARKER_DETECTION_RNASEQ.out.objects
    versions = BIOC_MGFR_MARKER_DETECTION_RNASEQ.out.versions
}
