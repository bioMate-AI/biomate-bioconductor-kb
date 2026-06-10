#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TOAST — complete_geometric_deconvolution
// Estimate cell compositions, number of cell types, and cell-type-specific markers from DNA methylation data using a complete geometric approach (Tsisal).
// Input: Ybeta, ref_m
// Container: quay.io/biocontainers/bioconductor-toast:1.24.0--r45hdfd78af_0
// R packages: TOAST
// Bioconductor: 3.20 | R: 4.4
// Requires: TOAST
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run complete deconvolution using Tsisal() with specified or unknown cell numbers (K) and reference panels

nextflow.enable.dsl = 2

process BIOC_TOAST_COMPLETE_GEOMETRIC_DECONVOLUTION {
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
    .bm_deps <- c("TOAST")
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
    library(TOAST)
    
    # ----------------------------------------------------------------------
    # 1. Read User Input Files
    # ----------------------------------------------------------------------
    
    # Read Ybeta (matrix of bulk DNA methylation beta values)
    Ybeta <- NULL
    if (file.exists("Ybeta.rds")) {
      Ybeta <- readRDS("Ybeta.rds")
    } else if (file.exists("Ybeta.csv")) {
      Ybeta <- as.matrix(read.csv("Ybeta.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("Ybeta.tsv")) {
      Ybeta <- as.matrix(read.delim("Ybeta.tsv", row.names = 1, check.names = FALSE))
    } else {
      stop("Required input file 'Ybeta' (RDS, CSV, or TSV) not found in the working directory.")
    }
    
    # Read ref_m (optional matrix of reference cell type profiles)
    ref_m <- NULL
    if (file.exists("ref_m.rds")) {
      ref_m <- readRDS("ref_m.rds")
    } else if (file.exists("ref_m.csv")) {
      ref_m <- as.matrix(read.csv("ref_m.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("ref_m.tsv")) {
      ref_m <- as.matrix(read.delim("ref_m.tsv", row.names = 1, check.names = FALSE))
    }
    
    # Helper function to save outputs safely
    save_outputs <- function(out_obj, prefix) {
      if (is.null(out_obj)) return(NULL)
      
      # Save full RDS object
      saveRDS(out_obj, paste0(prefix, "_results.rds"))
      
      # Save estimated proportions
      if (!is.null(out_obj\$estProp)) {
        write.csv(out_obj\$estProp, paste0(prefix, "_estProp.csv"), row.names = TRUE)
        
        # Generate PDF plot of estimated proportions
        tryCatch({
          pdf(paste0(prefix, "_estProp_barplot.pdf"), width = 10, height = 7)
          barplot(t(out_obj\$estProp), 
                  col = rainbow(ncol(out_obj\$estProp)), 
                  legend.text = colnames(out_obj\$estProp),
                  main = paste("Estimated Proportions -", prefix), 
                  xlab = "Samples", 
                  ylab = "Proportion",
                  args.legend = list(x = "topright", bty = "n"))
          dev.off()
        }, error = function(e) {
          message("Could not generate PDF plot: ", e\$message)
        })
      }
      
      # Save selected markers
      if (!is.null(out_obj\$selMarker)) {
        if (is.list(out_obj\$selMarker) || is.vector(out_obj\$selMarker)) {
          writeLines(as.character(unlist(out_obj\$selMarker)), paste0(prefix, "_selMarker.txt"))
        } else {
          write.csv(out_obj\$selMarker, paste0(prefix, "_selMarker.csv"), row.names = TRUE)
        }
      }
      
      # Save estimated number of cell types (K)
      if (!is.null(out_obj\$K)) {
        writeLines(as.character(out_obj\$K), paste0(prefix, "_K.txt"))
      }
    }
    
    # ----------------------------------------------------------------------
    # 2. Run Complete Geometric Deconvolution (Tsisal)
    # ----------------------------------------------------------------------
    
    # Scenario A: Complete deconvolution with specified K and reference panel
    message("Running Tsisal Scenario A (K = 4, knowRef = ref_m)...")
    out <- NULL
    tryCatch({
      out = Tsisal(Ybeta,K = 4, knowRef = ref_m)
      save_outputs(out, "tsisal_scenario_A")
    }, error = function(e) {
      message("Error in Scenario A: ", e\$message)
    })
    
    # Scenario B: Complete deconvolution where both K and reference panel are unknown
    message("Running Tsisal Scenario B (K = NULL, knowRef = NULL, possibleCellNumber = 2:5)...")
    out <- NULL
    tryCatch({
      out = Tsisal(Ybeta,K = NULL, knowRef = NULL, possibleCellNumber = 2:5)
      save_outputs(out, "tsisal_scenario_B")
    }, error = function(e) {
      message("Error in Scenario B: ", e\$message)
    })
    
    # Scenario C: Complete deconvolution where K is unknown and reference panel is known
    message("Running Tsisal Scenario C (K = NULL, knowRef = ref_m, possibleCellNumber = 2:5)...")
    out <- NULL
    tryCatch({
      out = Tsisal(Ybeta, K = NULL, knowRef = ref_m, possibleCellNumber = 2:5)
      save_outputs(out, "tsisal_scenario_C")
    }, error = function(e) {
      message("Error in Scenario C: ", e\$message)
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_TOAST_COMPLETE_GEOMETRIC_DECONVOLUTION":',
        paste0('    TOAST: ', as.character(packageVersion('TOAST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_complete_geometric_deconvolution.csv versions.yml
    """
}

workflow BIOC_TOAST_COMPLETE_GEOMETRIC_DECONVOLUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Ybeta, ref_m ] ]

    main:
    BIOC_TOAST_COMPLETE_GEOMETRIC_DECONVOLUTION(ch_input)

    emit:
    tables   = BIOC_TOAST_COMPLETE_GEOMETRIC_DECONVOLUTION.out.tables
    plots    = BIOC_TOAST_COMPLETE_GEOMETRIC_DECONVOLUTION.out.plots
    objects  = BIOC_TOAST_COMPLETE_GEOMETRIC_DECONVOLUTION.out.objects
    versions = BIOC_TOAST_COMPLETE_GEOMETRIC_DECONVOLUTION.out.versions
}
