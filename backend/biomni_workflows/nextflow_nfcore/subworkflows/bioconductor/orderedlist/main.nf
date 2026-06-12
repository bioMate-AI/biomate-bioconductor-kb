#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OrderedList — compare_expression_studies
// Compare two gene expression studies to detect similarities and identify overlapping genes.
// Input: eset1, eset2, mapping
// Container: quay.io/biocontainers/bioconductor-orderedlist:1.82.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, OrderedList, twilight
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Combine and prepare the two expression datasets using prepareData
//  * 2. [Core Analysis] Compute the similarity score and optimize alpha using OrderedList
//  * 3. [Visualization & Output] Plot the results (pAUC, scores, overlap) using plot
//  * 4. [Core Analysis] Extract the intersecting genes from the resulting object

nextflow.enable.dsl = 2

process BIOC_ORDEREDLIST_COMPARE_EXPRESSION_STUDIES {
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
    .bm_deps <- c("Biobase", "twilight", "OrderedList")
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
    
    library(Biobase)
    library(twilight)
    library(OrderedList)
    
    # ----------------------------------------------------------------------
    # 1. Read User Inputs
    # ----------------------------------------------------------------------
    eset1_path <- "eset1.rds"
    if (!file.exists(eset1_path)) {
      eset1_path <- "eset1"
    }
    if (!file.exists(eset1_path)) {
      stop("Error: eset1 file not found in the working directory.")
    }
    eset1_obj <- readRDS(eset1_path)
    
    eset2_path <- "eset2.rds"
    if (!file.exists(eset2_path)) {
      eset2_path <- "eset2"
    }
    if (!file.exists(eset2_path)) {
      stop("Error: eset2 file not found in the working directory.")
    }
    eset2_obj <- readRDS(eset2_path)
    
    mapping_obj <- NULL
    if (file.exists("mapping.rds")) {
      mapping_obj <- readRDS("mapping.rds")
    } else if (file.exists("mapping.csv")) {
      mapping_obj <- read.csv("mapping.csv", stringsAsFactors = FALSE)
    } else if (file.exists("mapping")) {
      mapping_obj <- readRDS("mapping")
    }
    
    # Helper function to dynamically detect comparison variable and outcome levels
    get_var_and_out <- function(eset) {
      pd <- pData(eset)
      if (ncol(pd) == 0) {
        stop("Error: ExpressionSet phenoData is empty. Cannot determine comparison variable.")
      }
      # Look for columns with exactly 2 unique values first
      classes <- sapply(pd, function(x) length(unique(x)))
      two_level_cols <- names(classes)[classes == 2]
      if (length(two_level_cols) > 0) {
        var_name <- two_level_cols[1]
      } else {
        var_name <- colnames(pd)[1]
      }
      out_vals <- as.character(unique(pd[[var_name]]))
      if (length(out_vals) > 2) {
        out_vals <- out_vals[1:2]
      }
      list(var = var_name, out = out_vals)
    }
    
    spec1 <- get_var_and_out(eset1_obj)
    spec2 <- get_var_and_out(eset2_obj)
    
    # ----------------------------------------------------------------------
    # 2. Combine and Prepare Data
    # ----------------------------------------------------------------------
    A <- prepareData(
    eset1=list(data=eset1_obj,name="study1",var=spec1\$var,out=spec1\$out,paired=FALSE),
    eset2=list(data=eset2_obj,name="study2",var=spec2\$var,out=spec2\$out,paired=FALSE),
    mapping=mapping_obj
    )
    
    # ----------------------------------------------------------------------
    # 3. Compute Similarity Score and Optimize Alpha
    # ----------------------------------------------------------------------
    x <- OrderedList(A, empirical=TRUE)
    x
    x\$intersect[1:5]
    
    # ----------------------------------------------------------------------
    # 4. Plot Results
    # ----------------------------------------------------------------------
    pdf("plot_pauc.pdf")
    plot(x,"pauc")
    dev.off()
    
    pdf("plot_scores.pdf")
    plot(x,"scores")
    dev.off()
    
    pdf("plot_overlap.pdf")
    plot(x,"overlap")
    dev.off()
    
    # ----------------------------------------------------------------------
    # 5. Save Outputs
    # ----------------------------------------------------------------------
    saveRDS(x, "ordered_list_results.rds")
    write.csv(data.frame(IntersectingGenes = x\$intersect), "intersecting_genes.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_ORDEREDLIST_COMPARE_EXPRESSION_STUDIES":',
        paste0('    OrderedList: ', as.character(packageVersion('OrderedList')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compare_expression_studies.csv versions.yml
    """
}

workflow BIOC_ORDEREDLIST_COMPARE_EXPRESSION_STUDIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ eset1, eset2, mapping ] ]

    main:
    BIOC_ORDEREDLIST_COMPARE_EXPRESSION_STUDIES(ch_input)

    emit:
    tables   = BIOC_ORDEREDLIST_COMPARE_EXPRESSION_STUDIES.out.tables
    plots    = BIOC_ORDEREDLIST_COMPARE_EXPRESSION_STUDIES.out.plots
    objects  = BIOC_ORDEREDLIST_COMPARE_EXPRESSION_STUDIES.out.objects
    versions = BIOC_ORDEREDLIST_COMPARE_EXPRESSION_STUDIES.out.versions
}
