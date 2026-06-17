#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: doseR — dosage_compensation_analysis
// Assess sex chromosome dosage compensation by normalizing RNA-seq counts, filtering unexpressed genes, and comparing absolute and relative expression across chro
// Input: readcounts.matrix, trxLength.vector, chromosome.vector
// Container: quay.io/biocontainers/bioconductor-doser:1.26.0--r45hdfd78af_0
// R packages: SummarizedExperiment, digest, doseR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: diagnostic MA/PCA QC

nextflow.enable.dsl = 2

process BIOC_DOSER_DOSAGE_COMPENSATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-doser:1.26.0--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("SummarizedExperiment", "digest", "doseR")
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
    
    library(doseR)
    library(SummarizedExperiment)
    
    # ==========================================
    # --- Read User Input Files Robustly ---
    # ==========================================
    
    # Read counts matrix
    counts <- tryCatch({
      as.matrix(read.table("readcounts.matrix", header=TRUE, row.names=1, sep="\t", check.names=FALSE))
    }, error = function(e) {
      as.matrix(read.table("readcounts.matrix", header=TRUE, row.names=1, check.names=FALSE))
    })
    
    # Helper function to read vectors (handles named or unnamed formats)
    read_vector <- function(file) {
      if (file.exists(file)) {
        tryCatch({
          df <- read.table(file, header=FALSE, stringsAsFactors=FALSE)
          if (ncol(df) > 1) {
            val <- df[[2]]
            names(val) <- df[[1]]
            return(val)
          } else {
            return(df[[1]])
          }
        }, error = function(e) {
          return(readLines(file))
        })
      } else {
        stop(paste("Required input file not found:", file))
      }
    }
    
    trxLength_raw <- read_vector("trxLength.vector")
    chromosome_raw <- read_vector("chromosome.vector")
    
    # Align vectors to counts matrix rownames if names are present
    if (!is.null(names(trxLength_raw)) && all(rownames(counts) %in% names(trxLength_raw))) {
      trxLength <- as.numeric(trxLength_raw[rownames(counts)])
    } else {
      trxLength <- as.numeric(trxLength_raw)
    }
    
    if (!is.null(names(chromosome_raw)) && all(rownames(counts) %in% names(chromosome_raw))) {
      chromosome <- as.character(chromosome_raw[rownames(counts)])
    } else {
      chromosome <- as.character(chromosome_raw)
    }
    
    # ==========================================
    # --- Prepare Metadata and Design ---
    # ==========================================
    
    # Infer replicate structure (Treatment) from column names
    col_names <- colnames(counts)
    if (any(grepl("male", col_names, ignore.case=TRUE))) {
      reps <- ifelse(grepl("female", col_names, ignore.case=TRUE), "Female", "Male")
    } else {
      # Fallback: split 50/50 if no explicit male/female keywords are found
      half <- ceiling(length(col_names) / 2)
      reps <- c(rep("Male", half), rep("Female", length(col_names) - half))
    }
    
    # Determine chromosome levels dynamically
    chrom_levels <- sort(unique(chromosome))
    if (!any(is.na(suppressWarnings(as.numeric(chrom_levels))))) {
      chrom_levels <- as.character(sort(as.numeric(chrom_levels)))
    }
    
    annotxn <- data.frame("Chromosome" = factor(chromosome, levels = chrom_levels))
    
    # Identify the sex chromosome (Z or X) dynamically
    z_chrom <- NULL
    if ("Z" %in% chrom_levels) {
      z_chrom <- "Z"
    } else if ("X" %in% chrom_levels) {
      z_chrom <- "X"
    } else if ("21" %in% chrom_levels) {
      z_chrom <- "21"
    } else {
      z_chrom <- tail(chrom_levels, 1)
    }
    
    annotxn\$ZA <- factor(ifelse(chromosome == z_chrom, "Z", "A"), levels = c("A", "Z"))
    
    # ==========================================
    # --- Construct SummarizedExperiment Object ---
    # ==========================================
    
    colData <- S4Vectors::DataFrame(Treatment=as.factor(reps), 
                                    row.names=colnames(counts))
    rowData <- S4Vectors::DataFrame(annotation = annotxn, 
                                    seglens = trxLength,
                                    row.names=rownames(counts) )
    se2 <- SummarizedExperiment(assays=list(counts=counts), 
                                colData=colData, rowData=rowData)
    
    # ==========================================
    # --- Normalization & RPKM Calculation ---
    # ==========================================
    
    SummarizedExperiment::colData(se2)\$Libsizes <- getLibsizes3(se2, estimationType = "total")
    SummarizedExperiment::assays(se2)\$rpkm <- make_RPKM(se2)
    
    # Assign se2 to se to continue the workflow seamlessly without loading demo data
    se <- se2
    
    # Save the unfiltered SummarizedExperiment object
    saveRDS(se, "unfiltered_se.rds")
    
    # ==========================================
    # --- Filtering "Unexpressed" Loci ---
    # ==========================================
    
    f_se <- simpleFilter(se, mean_cutoff = 0.01, counts = FALSE)
    saveRDS(f_se, "filtered_se.rds")
    
    # ==========================================
    # --- Visualization and Statistical Analysis ---
    # ==========================================
    
    # Open PDF device for all plots
    pdf("dosage_compensation_plots.pdf", width = 10, height = 8)
    
    # Plot MA
    plotMA.se(se, samplesA ="Male", samplesB = "Female", cex = .2 , 
              pch = 19, col = rgb(0,0,0, .2), xlab = "Log2(Average RPKM)", 
              ylab = "Log2(Male:Female)")
    
    # Plot Absolute Expression (ZA)
    plotExpr(f_se, groupings = "annotation.ZA", clusterby_grouping = FALSE, 
             col=c("grey80","red","grey80","red"), notch=TRUE, ylab = "Log2(RPKM)")
    
    # Generate Absolute Expression Statistics (Male)
    se.male <- f_se[, colData(f_se)\$Treatment == "Male"]
    male_ZvA <- generateStats(se.male , groupings = "annotation.ZA", LOG2 = FALSE)
    
    # Save Male Absolute Expression Statistics
    write.csv(male_ZvA\$summary, "male_ZvA_summary.csv")
    sink("male_ZvA_kruskal.txt")
    print(male_ZvA\$kruskal)
    sink()
    saveRDS(male_ZvA, "male_ZvA_stats.rds")
    
    # Plot Absolute Expression (Chromosome)
    num_chroms <- length(chrom_levels)
    chrom_cols <- c(rep("grey80", num_chroms - 1), "red")
    
    plotExpr(f_se, groupings = "annotation.Chromosome", col=chrom_cols, 
             notch=TRUE, ylab = "Log2(RPKM)", las = 2, treatment = "Male",  
             clusterby_grouping = TRUE )
    
    # Plot Relative Expression Ratios (ZA)
    plotRatioBoxes(f_se, groupings = "annotation.ZA", treatment1 = "Male", 
                   treatment2 = "Female", outline = FALSE, col = c("grey80", "red"),
                   ylab = "Log(Male:Female)" )
    
    plotRatioDensity(f_se, groupings = "annotation.ZA", treatment1 = "Male", 
                     treatment2 = "Female", type = "l", xlab = "Log(Male:Female)", ylab = "Density")
    
    # Plot Relative Expression Ratios (Chromosome)
    par(mfrow = c(1,2))
    plotRatioBoxes(f_se, groupings = "annotation.Chromosome", treatment1 = "Male", 
                   treatment2 = "Female", outline = FALSE, col=chrom_cols, 
                   ylab = "Log(Male:Female)", xlab = "Chromosome" )
    
    plotRatioDensity(f_se, groupings = "annotation.Chromosome", treatment1 = "Male", 
                     treatment2 = "Female", type = "l", xlab = "Log(Male:Female)",
                     ylab = "Density", col=chrom_cols, lty = 1)
    
    # Close PDF device
    dev.off()
    
    # ==========================================
    # --- Statistical Testing on Ratios ---
    # ==========================================
    
    za.ratios.test <- test_diffs(f_se, groupings = "annotation.ZA", 
                                 treatment1 = "Male", treatment2 = "Female", LOG2 = FALSE )
    
    # Save Ratio Test Statistics
    write.csv(za.ratios.test\$summary, "za_ratios_test_summary.csv")
    sink("za_ratios_test_kruskal.txt")
    print(za.ratios.test\$kruskal)
    sink()
    saveRDS(za.ratios.test, "za_ratios_test.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # diagnostic MA/PCA QC — PC1 variance explained on any large matrix.
    # Pass when PC1 > 10% (Risso 2014 RUV-seq diagnostic).
    .pca_pc1 <- NA_real_; .pca_files <- character(0)
    for (.pca_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .pca_obj <- tryCatch(readRDS(.pca_rds), error = function(e) NULL)
      .pca_mat <- if (is.matrix(.pca_obj) || is.data.frame(.pca_obj)) .pca_obj else NULL
      if (!is.null(.pca_mat) && ncol(.pca_mat) >= 3 && nrow(.pca_mat) >= 100) {
        .pca_m <- suppressWarnings(as.matrix(.pca_mat))
        .pca_kept <- apply(.pca_m, 1, function(r) all(is.finite(r)) && var(r) > 0)
        if (sum(.pca_kept) >= 50) {
          .pca_fit <- tryCatch(prcomp(t(.pca_m[.pca_kept, , drop = FALSE])), error = function(e) NULL)
          if (!is.null(.pca_fit)) {
            .pca_vars <- (.pca_fit\$sdev^2) / sum(.pca_fit\$sdev^2)
            .pca_pc1 <- round(.pca_vars[1] * 100, 2); .pca_files <- c(.pca_files, .pca_rds); break
          }
        }
      }
    }
    .gates_by_label[["diagnostic MA/PCA QC"]] <- list(
      gate_row = "bioc_diagnostic_ma_pca_qc",
      metric_name = "pc1_var_explained",
      metric_value = .pca_pc1,
      passes = isTRUE(is.finite(.pca_pc1) && .pca_pc1 > 10),
      status = if (is.finite(.pca_pc1)) paste0("computed (PC1=", .pca_pc1, "%)")
               else "not_computed (no large numeric matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_DOSER_DOSAGE_COMPENSATION_ANALYSIS",
      domain  = "bioconductor",
      declared_qc_steps = c("diagnostic MA/PCA QC"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_DOSER_DOSAGE_COMPENSATION_ANALYSIS":',
        paste0('        doseR: ', as.character(packageVersion("doseR")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dosage_compensation_analysis.csv versions.yml
    """
}

workflow BIOC_DOSER_DOSAGE_COMPENSATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ readcounts.matrix, trxLength.vector, chromosome.vector ] ]

    main:
    BIOC_DOSER_DOSAGE_COMPENSATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DOSER_DOSAGE_COMPENSATION_ANALYSIS.out.tables
    plots    = BIOC_DOSER_DOSAGE_COMPENSATION_ANALYSIS.out.plots
    objects  = BIOC_DOSER_DOSAGE_COMPENSATION_ANALYSIS.out.objects
    versions = BIOC_DOSER_DOSAGE_COMPENSATION_ANALYSIS.out.versions
}
