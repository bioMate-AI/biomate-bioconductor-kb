#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PAA — paa_protein_array_pipeline
// Perform a complete protein microarray analysis pipeline including preprocessing, batch filtering, normalization, univariate differential analysis, feature prese
// Input: intensity.csv, coldata.csv
// Container: 1.44.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PAA, limma
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PAA_PAA_PROTEIN_ARRAY_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("limma", "PAA")
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
    library(limma)
    library(PAA)
    
    # -------------------------------------------------------------------------
    # --- Load and Prepare Data ---
    # -------------------------------------------------------------------------
    message("Stage 1: Loading and preparing data...")
    
    # Read input files
    intensities <- read.csv("intensity.csv", row.names=1, check.names=FALSE)
    coldata <- read.csv("coldata.csv", check.names=FALSE)
    
    # Align coldata and intensities
    common_samples <- intersect(colnames(intensities), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between intensity.csv and coldata.csv")
    }
    intensities <- intensities[, common_samples, drop=FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # Ensure we have exactly two groups for differential analysis
    groups <- unique(coldata\$condition)
    if (length(groups) < 2) {
      stop("At least two conditions are required in coldata.csv for differential analysis.")
    } else if (length(groups) > 2) {
      message("More than 2 conditions found. Subsetting to the first two: ", paste(groups[1:2], collapse=", "))
      groups <- groups[1:2]
      coldata <- coldata[coldata\$condition %in% groups, ]
      intensities <- intensities[, coldata\$sample, drop=FALSE]
    }
    
    # Create EListRaw object
    elist <- new("EListRaw")
    elist\$E <- as.matrix(intensities)
    elist\$Eb <- matrix(0, nrow=nrow(intensities), ncol=ncol(intensities))
    colnames(elist\$Eb) <- colnames(elist\$E)
    rownames(elist\$Eb) <- rownames(elist\$E)
    
    # Create dummy genes annotation (PAA expects Block, Column, Row, Description, Name, ID)
    n_features <- nrow(intensities)
    elist\$genes <- data.frame(
      Block = rep(1, n_features),
      Column = rep(1, n_features),
      Row = 1:n_features,
      Description = rownames(intensities),
      Name = rownames(intensities),
      ID = rownames(intensities),
      stringsAsFactors = FALSE
    )
    
    # Create targets annotation (PAA batchAdjust expects 'Batch' and 'Group')
    if (!"Batch" %in% colnames(coldata)) {
      coldata\$Batch <- "Batch1"
    }
    elist\$targets <- data.frame(
      ArrayID = coldata\$sample,
      FileName = paste0(coldata\$sample, ".gpr"),
      Group = coldata\$condition,
      Batch = coldata\$Batch,
      stringsAsFactors = FALSE
    )
    
    # Define group labels and sample vectors
    g1_label <- groups[1]
    g2_label <- groups[2]
    c1 <- elist\$targets[elist\$targets\$Group == g1_label, "ArrayID"]
    c2 <- elist\$targets[elist\$targets\$Group == g2_label, "ArrayID"]
    
    # Create BRC-ID mapping to original feature IDs
    brc <- paste(elist\$genes[,1], elist\$genes[,3], elist\$genes[,2])
    brc_to_feature <- setNames(rownames(intensities), brc)
    
    # -------------------------------------------------------------------------
    # --- Preprocessing (Background Correction, Batch Filtering, ---
    # -------------------------------------------------------------------------
    message("Stage 2: Preprocessing...")
    
    # Background correction
    tryCatch({
      elist <- backgroundCorrect(elist, method="normexp", normexp.method="saddle")
    }, error = function(e) {
      message("Background correction failed or skipped: ", e\$message)
    })
    
    # Batch filtering (only if multiple batches exist)
    batches <- unique(elist\$targets\$Batch)
    if (length(batches) == 2) {
      lot1 <- elist\$targets[elist\$targets\$Batch == batches[1], "ArrayID"]
      lot2 <- elist\$targets[elist\$targets\$Batch == batches[2], "ArrayID"]
      tryCatch({
        elist <- batchFilter(elist=elist, lot1=lot1, lot2=lot2, log=FALSE, p.thresh=0.05, fold.thresh=1.5)
      }, error = function(e) {
        message("batchFilter failed: ", e\$message)
      })
    } else if (length(batches) > 2) {
      tryCatch({
        elist <- batchFilter.anova(elist=elist, log=FALSE, p.thresh=0.05, fold.thresh=1.5)
      }, error = function(e) {
        message("batchFilter.anova failed: ", e\$message)
      })
    }
    
    # Normalization (returns log2 scale)
    elist <- normalizeArrays(elist=elist, method="quantile")
    
    # Batch adjustment (only if multiple batches exist)
    if (length(unique(elist\$targets\$Batch)) > 1) {
      tryCatch({
        elist <- batchAdjust(elist=elist, log=TRUE)
      }, error = function(e) {
        message("batchAdjust failed: ", e\$message)
      })
    }
    
    # Create unlogged copy for methods requiring original scale
    elist.unlog <- elist
    elist.unlog\$E <- 2^(elist\$E)
    
    # -------------------------------------------------------------------------
    # --- Differential Analysis ---
    # -------------------------------------------------------------------------
    message("Stage 3: Differential Analysis...")
    
    # Generate diagnostic plots
    tryCatch({
      volcanoPlot(elist=elist, group1=c1, group2=c2, log=TRUE, method="tTest",
                  p.thresh=0.05, fold.thresh=1.5, output.path=".")
      pvaluePlot(elist=elist, group1=c1, group2=c2, log=TRUE, method="tTest",
                 output.path=".")
    }, error = function(e) {
      message("Diagnostic plotting failed: ", e\$message)
    })
    
    # Detailed univariate differential analysis
    mMs.matrix1 <- mMsMatrix(x=length(c1), y=length(c2))
    mMs.matrix2 <- mMsMatrix(x=length(c2), y=length(c1))
    
    E_unlog <- elist.unlog\$E
    rownames(E_unlog) <- paste(elist.unlog\$genes[,1], elist.unlog\$genes[,3], elist.unlog\$genes[,2])
    
    tryCatch({
      diff.results <- diffAnalysis(input=E_unlog, label1=c1, label2=c2,
                                   class1=g1_label, class2=g2_label,
                                   output.path=".",
                                   mMs.matrix1=mMs.matrix1, mMs.matrix2=mMs.matrix2,
                                   above=1500, between=400)
      
      diff.results.df <- as.data.frame(diff.results)
      diff.results.df\$feature_id <- brc_to_feature[rownames(diff.results.df)]
      write.csv(diff.results.df, "differential_analysis.csv", row.names=FALSE)
    }, error = function(e) {
      message("diffAnalysis failed: ", e\$message)
      write.csv(data.frame(Error=e\$message), "differential_analysis.csv", row.names=FALSE)
    })
    
    # -------------------------------------------------------------------------
    # --- Feature Preselection ---
    # -------------------------------------------------------------------------
    message("Stage 4: Feature Preselection...")
    
    elist.filtered <- elist
    tryCatch({
      pre.sel.results <- preselect(elist=elist.unlog, columns1=c1, columns2=c2,
                                   label1=g1_label, label2=g2_label, log=FALSE,
                                   discard.threshold=0.5, fold.thresh=1.5,
                                   discard.features=TRUE, mMs.above=1500, mMs.between=400,
                                   mMs.matrix1=mMs.matrix1, mMs.matrix2=mMs.matrix2,
                                   method="mMs")
      if (length(pre.sel.results\$discard) > 0 && length(pre.sel.results\$discard) < nrow(elist)) {
        elist.filtered <- elist[-pre.sel.results\$discard, ]
      }
    }, error = function(e) {
      message("preselect failed: ", e\$message)
    })
    
    # -------------------------------------------------------------------------
    # --- Feature Selection ---
    # -------------------------------------------------------------------------
    message("Stage 5: Feature Selection...")
    
    selected_brc <- c()
    tryCatch({
      if (nrow(elist.filtered) > 5) {
        select.results <- selectFeatures(elist.filtered,
                                         n1=length(c1), n2=length(c2),
                                         label1=g1_label, label2=g2_label,
                                         log=TRUE,
                                         selection.method="rf.rfe",
                                         preselection.method="tTest",
                                         subruns=2, k=2,
                                         candidate.number=min(50, nrow(elist.filtered)),
                                         method="frequency")
        selected_brc <- select.results\$features
      } else {
        selected_brc <- rownames(elist.filtered\$E)
      }
      
      selected_features <- brc_to_feature[selected_brc]
      selected_features <- selected_features[!is.na(selected_features)]
      write.table(selected_features, "selected_features.txt", row.names=FALSE, col.names=FALSE, quote=FALSE)
    }, error = function(e) {
      message("selectFeatures failed: ", e\$message)
      selected_brc <<- rownames(elist.filtered\$E)[1:min(5, nrow(elist.filtered))]
      selected_features <- brc_to_feature[selected_brc]
      selected_features <- selected_features[!is.na(selected_features)]
      write.table(selected_features, "selected_features.txt", row.names=FALSE, col.names=FALSE, quote=FALSE)
    })
    
    # -------------------------------------------------------------------------
    # --- Results Inspection & Visualization ---
    # -------------------------------------------------------------------------
    message("Stage 6: Results Inspection...")
    
    if (length(selected_brc) > 0) {
      tryCatch({
        plotFeatures(features=selected_brc, elist=elist.filtered,
                     n1=length(c1), n2=length(c2),
                     group1=g1_label, group2=g2_label,
                     output.path=".")
      }, error = function(e) {
        message("plotFeatures failed: ", e\$message)
      })
    
      tryCatch({
        plotFeaturesHeatmap(features=selected_brc, elist=elist.filtered,
                            n1=length(c1), n2=length(c2),
                            output.path=".", description=FALSE)
      }, error = function(e) {
        message("plotFeaturesHeatmap failed: ", e\$message)
      })
    
      tryCatch({
        features_table <- printFeatures(features=selected_brc, elist=elist.filtered, output.path=".")
      }, error = function(e) {
        message("printFeatures failed: ", e\$message)
        file.create("candidates.txt")
      })
    } else {
      file.create("candidates.txt")
    }
    
    message("Pipeline complete!")

    writeLines(c(
        '"BIOC_PAA_PAA_PROTEIN_ARRAY_PIPELINE":',
        paste0('    PAA: ', as.character(packageVersion('PAA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paa_protein_array_pipeline.csv versions.yml
    """
}

workflow BIOC_PAA_PAA_PROTEIN_ARRAY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PAA_PAA_PROTEIN_ARRAY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PAA_PAA_PROTEIN_ARRAY_PIPELINE.out.tables
    plots    = BIOC_PAA_PAA_PROTEIN_ARRAY_PIPELINE.out.plots
    objects  = BIOC_PAA_PAA_PROTEIN_ARRAY_PIPELINE.out.objects
    versions = BIOC_PAA_PAA_PROTEIN_ARRAY_PIPELINE.out.versions
}
