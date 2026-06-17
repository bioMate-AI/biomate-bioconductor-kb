#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metabCombiner — lc_ms_dataset_alignment
// Align two LC-MS metabolomics datasets by grouping features, mapping retention times with non-linear splines, scoring alignments, and resolving conflicts.
// Input: dataset1.txt, dataset2.txt
// Container: quay.io/biocontainers/bioconductor-metabcombiner:1.20.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: metabCombiner
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Data Formatting and Filtering
//  * 2. [Core Analysis] Feature m/z Grouping and Pairwise Alignment Detection
//  * 3. [Core Analysis] Anchor Selection
//  * 4. [Core Analysis] Model-fitting / RT Mapping
//  * 5. [Core Analysis] Feature Pair Alignment Scoring
//  * 6. [Core Analysis] Combined Table Reduction and Conflict Labeling
//  * 7. [Visualization & Output] Exporting Results

nextflow.enable.dsl = 2

process BIOC_METABCOMBINER_LC_MS_DATASET_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("metabCombiner")
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
        library(metabCombiner)
        
        # ==========================================
        # 1. Data Formatting and Filtering
        # ==========================================
        
        # Read user input files from the working directory
        # dataset1.txt corresponds to the 30-minute plasma dataset (X dataset)
        # dataset2.txt corresponds to the 20-minute plasma dataset (Y dataset)
        plasma30_df <- read.delim("dataset1.txt", sep = "\t", header = TRUE, stringsAsFactors = FALSE)
        plasma20_df <- read.delim("dataset2.txt", sep = "\t", header = TRUE, stringsAsFactors = FALSE)
        
        # Format and filter the datasets using metabData
        # Dynamically identify sample columns by excluding 'mz' and 'rt'
        samples20 <- setdiff(names(plasma20_df), c("mz", "rt"))
        p20 <- metabData(table = plasma20_df, mz = "mz", rt = "rt", samples = samples20, measure = "median", zero = FALSE, duplicate = c(0.0025, 0.05))
        
        samples30 <- setdiff(names(plasma30_df), c("mz", "rt"))
        p30 <- metabData(table = plasma30_df, mz = "mz", rt = "rt", samples = samples30)
        
        # ==========================================
        # 2. Feature m/z Grouping and Pairwise Alignment Detection
        # ==========================================
        p.combined = metabCombiner(xdata = p30, ydata = p20, binGap = 0.0075)
        p.results = combinedTable(p.combined)
        
        # ==========================================
        # 3. Anchor Selection
        # ==========================================
        p.combined.2 = selectAnchors(p.combined, windx = 0.03, windy = 0.02, tolQ = 0.3, tolmz = 0.003, tolrtq = 0.3, useID = FALSE)
        a = getAnchors(p.combined.2)
        
        # Save anchor plot to PDF
        pdf("anchor_plot.pdf")
        plot(a\$rtx, a\$rty, main = "Fit Template", xlab = "rtx", ylab = "rty")
        dev.off()
        
        # ==========================================
        # 4. Model-fitting / RT Mapping
        # ==========================================
        set.seed(100)
        p.combined.3 = fit_gam(p.combined.2, useID = FALSE, k = seq(12,20,2), iterFilter = 2, coef = 2, prop = 0.5, bs = "bs", family = "gaussian", m = c(3,2))
        
        # Save GAM plot to PDF
        pdf("gam_plot.pdf")
        plot(p.combined.3, main = "Example metabCombiner Plot", xlab = "P30 RTs", ylab = "P20 RTs", lcol = "blue", pcol = "black", lwd = 3, pch = 19, outlier = "highlight")
        grid(lty = 2, lwd = 1)
        dev.off()
        
        # ==========================================
        # 5. Feature Pair Alignment Scoring
        # ==========================================
        p.combined.4 = calcScores(p.combined.3, A = 70, B = 15, C = 0.5, usePPM = FALSE, useAdduct = FALSE, groups = NULL)
        
        # ==========================================
        # 6. Combined Table Reduction and Conflict Labeling
        # ==========================================
        combined.table = combinedTable(p.combined.4)
        
        # Version 1: score-based conflict detection
        combined.table.2 = labelRows(combined.table, minScore = 0.5, maxRankX = 3, maxRankY = 3, method = "score", delta = 0.2, remove = FALSE, balanced = TRUE)
        
        # Version 2: mzrt-based conflict detection
        combined.table.3 = labelRows(combined.table, minScore = 0.5, maxRankX = 3, maxRankY = 3, method = "mzrt", balanced = TRUE, delta = c(0.003, 0.5, 0.003, 0.2))
        
        # Save labeled tables
        write.table(combined.table.2, file = "Combined.Table.ScoreLabeled.txt", sep = "\t", row.names = FALSE, quote = FALSE)
        write.table(combined.table.3, file = "Combined.Table.MzrtLabeled.txt", sep = "\t", row.names = FALSE, quote = FALSE)
        
        # Save final metabCombiner object as RDS
        saveRDS(p.combined.4, file = "metabCombiner_final_object.rds")
        
        # ==========================================
        # 7. Exporting Results
        # ==========================================
        write2file(combined.table, file = "Combined.Table.Report.txt", sep = "\t")

    writeLines(c(
        '"BIOC_METABCOMBINER_LC_MS_DATASET_ALIGNMENT":',
        paste0('    metabCombiner: ', as.character(packageVersion('metabCombiner')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lc_ms_dataset_alignment.csv versions.yml
    """
}

workflow BIOC_METABCOMBINER_LC_MS_DATASET_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataset1.txt, dataset2.txt ] ]

    main:
    BIOC_METABCOMBINER_LC_MS_DATASET_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_METABCOMBINER_LC_MS_DATASET_ALIGNMENT.out.tables
    plots    = BIOC_METABCOMBINER_LC_MS_DATASET_ALIGNMENT.out.plots
    objects  = BIOC_METABCOMBINER_LC_MS_DATASET_ALIGNMENT.out.objects
    versions = BIOC_METABCOMBINER_LC_MS_DATASET_ALIGNMENT.out.versions
}
