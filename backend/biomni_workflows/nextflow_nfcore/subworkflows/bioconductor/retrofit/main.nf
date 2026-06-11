#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: retrofit — two_step_deconvolution_and_annotation
// Deconvolve spatial transcriptomics data into components and then annotate those components using either a single-cell reference or known marker genes.
// Input: X, sc_ref, marker_ref
// Container: quay.io/biocontainers/bioconductor-retrofit:1.10.0--r45ha27e39d_0
// R packages: corrplot, retrofit
// Bioconductor: 3.20 | R: 4.4
// Requires: corrplot, retrofit
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Read User Input Files
//  * 2. [Core Analysis] Reference-free Deconvolution
//  * 3. [Core Analysis] Option A: Cell-type Annotation via annotated single-cell
//  * 4. [Core Analysis] Option B: Cell-type Annotation via known marker genes

nextflow.enable.dsl = 2

process BIOC_RETROFIT_TWO_STEP_DECONVOLUTION_AND_ANNOTATION {
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
    .bm_deps <- c("corrplot", "retrofit")
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
        library(retrofit)
        library(corrplot)
        library(stats)
        library(grDevices)
        
        # ==========================================
        # --- Read User Input Files ---
        # ==========================================
        
        # Load Spatial Transcriptomics Matrix X (G x S)
        if (file.exists("X.rds")) {
          X <- readRDS("X.rds")
        } else if (file.exists("X.csv")) {
          X <- as.matrix(read.csv("X.csv", row.names = 1, check.names = FALSE))
        } else {
          stop("Error: Spatial transcriptomics matrix file ('X.rds' or 'X.csv') not found in the working directory.")
        }
        
        # Load Single-Cell Reference Matrix sc_ref (G x K)
        if (file.exists("sc_ref.rds")) {
          sc_ref <- readRDS("sc_ref.rds")
        } else if (file.exists("sc_ref.csv")) {
          sc_ref <- as.matrix(read.csv("sc_ref.csv", row.names = 1, check.names = FALSE))
        } else {
          stop("Error: Single-cell reference file ('sc_ref.rds' or 'sc_ref.csv') not found in the working directory.")
        }
        
        # Load Marker Genes List marker_ref (List of K cell types)
        if (file.exists("marker_ref.rds")) {
          marker_ref <- readRDS("marker_ref.rds")
        } else {
          stop("Error: Marker reference list file ('marker_ref.rds') not found in the working directory.")
        }
        
        # Ensure X and sc_ref are numeric matrices
        X <- as.matrix(X)
        sc_ref <- as.matrix(sc_ref)
        
        # ==========================================
        # --- Reference-free Deconvolution ---
        # ==========================================
        iterations = 4000
        L = 20
        
        message("Running reference-free deconvolution using retrofit::decompose...")
        result = retrofit::decompose(X, L=L, iterations=iterations, verbose=TRUE)
        
        H = result\$h
        W = result\$w
        Th = result\$th
        
        # Save intermediate deconvolution results
        write.csv(as.data.frame(W), "decomposed_W.csv", row.names = TRUE)
        write.csv(as.data.frame(H), "decomposed_H.csv", row.names = TRUE)
        write.csv(data.frame(Theta = Th), "decomposed_Theta.csv", row.names = FALSE)
        saveRDS(result, "decomposed_result.rds")
        
        # ==========================================
        # --- Option A: Cell-type Annotation via annotated single-cell ---
        # ==========================================
        message("Running cell-type annotation via single-cell reference...")
        K = ncol(sc_ref) # number of cell types
        
        result_sc = annotateWithCorrelations(sc_ref, K, W, H)
        H_sc = result_sc\$h
        W_sc = result_sc\$w
        H_sc_prop = result_sc\$h_prop
        W_sc_prop = result_sc\$w_prop
        
        # Save Option A results
        write.csv(as.data.frame(H_sc), "H_sc.csv", row.names = TRUE)
        write.csv(as.data.frame(W_sc), "W_sc.csv", row.names = TRUE)
        write.csv(as.data.frame(H_sc_prop), "H_sc_prop.csv", row.names = TRUE)
        write.csv(as.data.frame(W_sc_prop), "W_sc_prop.csv", row.names = TRUE)
        saveRDS(result_sc, "annotation_sc_result.rds")
        
        # Generate Correlation-based Mapping Plot
        tryCatch({
          W_norm <- W
          for(i in 1:nrow(W)){
            if (sum(W[i,]) > 0) {
              W_norm[i,] = W[i,]/sum(W[i,])
            } else {
              W_norm[i,] = 0
            }
          }
          
          pdf("correlation_mapping_matrix.pdf", width = 8, height = 7)
          corrplot::corrplot(stats::cor(sc_ref, W_norm), 
                             is.corr=FALSE, 
                             mar=c(0,0,1,0), 
                             col = colorRampPalette(c("white", "deepskyblue", "blue4"))(100), 
                             main="Correlation-based Mapping Matrix")
          dev.off()
          message("Saved correlation mapping plot to 'correlation_mapping_matrix.pdf'")
        }, error = function(e) {
          warning("Could not generate correlation mapping plot: ", e\$message)
        })
        
        # ==========================================
        # --- Option B: Cell-type Annotation via known marker genes ---
        # ==========================================
        message("Running cell-type annotation via known marker genes...")
        K = length(marker_ref) # number of cell types
        
        result_mark = retrofit::annotateWithMarkers(marker_ref, K, W, H)
        H_mark = result_mark\$h
        W_mark = result_mark\$w
        H_mark_prop = result_mark\$h_prop
        W_mark_prop = result_mark\$w_prop
        gene_sums = result_mark\$gene_sums
        
        # Save Option B results
        write.csv(as.data.frame(H_mark), "H_mark.csv", row.names = TRUE)
        write.csv(as.data.frame(W_mark), "W_mark.csv", row.names = TRUE)
        write.csv(as.data.frame(H_mark_prop), "H_mark_prop.csv", row.names = TRUE)
        write.csv(as.data.frame(W_mark_prop), "W_mark_prop.csv", row.names = TRUE)
        write.csv(as.data.frame(gene_sums), "gene_sums.csv", row.names = TRUE)
        saveRDS(result_mark, "annotation_marker_result.rds")
        
        # Generate Marker-based Mapping Plot
        tryCatch({
          pdf("marker_mapping_matrix.pdf", width = 8, height = 7)
          corrplot::corrplot(gene_sums, 
                             is.corr=FALSE, 
                             mar=c(0,0,1,0), 
                             col=colorRampPalette(c("white", "deepskyblue", "blue4"))(100), 
                             main="Marker-based Mapping Matrix")
          dev.off()
          message("Saved marker mapping plot to 'marker_mapping_matrix.pdf'")
        }, error = function(e) {
          warning("Could not generate marker mapping plot: ", e\$message)
        })
        
        message("RETROFIT pipeline completed successfully. All outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_RETROFIT_TWO_STEP_DECONVOLUTION_AND_ANNOTATION":',
        paste0('    retrofit: ', as.character(packageVersion('retrofit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_step_deconvolution_and_annotation.csv versions.yml
    """
}

workflow BIOC_RETROFIT_TWO_STEP_DECONVOLUTION_AND_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ X, sc_ref, marker_ref ] ]

    main:
    BIOC_RETROFIT_TWO_STEP_DECONVOLUTION_AND_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_RETROFIT_TWO_STEP_DECONVOLUTION_AND_ANNOTATION.out.tables
    plots    = BIOC_RETROFIT_TWO_STEP_DECONVOLUTION_AND_ANNOTATION.out.plots
    objects  = BIOC_RETROFIT_TWO_STEP_DECONVOLUTION_AND_ANNOTATION.out.objects
    versions = BIOC_RETROFIT_TWO_STEP_DECONVOLUTION_AND_ANNOTATION.out.versions
}
