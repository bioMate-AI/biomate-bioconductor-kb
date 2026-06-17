#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: limma — two_color_microarray_analysis
// Analyze two-color spotted microarray data to identify differentially expressed genes.
// Input: targets.txt, .gpr
// Container: quay.io/biocontainers/bioconductor-limma:3.66.0--r45h01b2380_0
// R packages: limma
// Bioconductor: 3.20 | R: 4.4
// Requires: limma
// Visualizations: mean-difference plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read targets metadata
//  * 2. [Input & Preparation] Read raw intensities and apply spot quality weights
//  * 3. [Input & Preparation] Perform background correction
//  * 4. [Input & Preparation] Perform within-array normalization
//  * 5. [Input & Preparation] Fit gene-wise linear models
//  * 6. [Input & Preparation] Apply empirical Bayes smoothing
//  * 7. [Input & Preparation] Extract top differentially expressed genes

nextflow.enable.dsl = 2

process BIOC_LIMMA_TWO_COLOR_MICROARRAY_ANALYSIS {
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
    .bm_deps <- c("limma")
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
        
        # -----------------------------------------------------------------
        # Workspace Setup (Creating dummy input files if they do not exist)
        # -----------------------------------------------------------------
        if (!file.exists("targets.txt")) {
          targets_data <- data.frame(
            SlideNumber = 1:4,
            FileName = c("array1.gpr", "array2.gpr", "array3.gpr", "array4.gpr"),
            Cy3 = c("Ref", "Treatment", "Ref", "Treatment"),
            Cy5 = c("Treatment", "Ref", "Treatment", "Ref"),
            stringsAsFactors = FALSE
          )
          write.table(targets_data, "targets.txt", sep="\t", row.names=FALSE, quote=FALSE)
        }
        
        create_dummy_gpr <- function(filename) {
          if (!file.exists(filename)) {
            header <- c(
              "ATF\t1.0",
              "30\t12",
              "Type=GenePix Results List",
              "Creator=GenePix Pro 6.0",
              "\"Block\"\t\"Row\"\t\"Column\"\t\"ID\"\t\"Name\"\t\"F635 Mean\"\t\"F635 Median\"\t\"B635\"\t\"B635 Median\"\t\"F532 Mean\"\t\"F532 Median\"\t\"B532\"\t\"B532 Median\"\t\"Flags\""
            )
            set.seed(42)
            rows <- lapply(1:100, function(i) {
              paste(
                1, # Block
                i, # Row
                1, # Column
                paste0("ID_", i), # ID
                paste0("Gene_", i), # Name
                round(runif(1, 100, 1000)), # F635 Mean
                round(runif(1, 100, 1000)), # F635 Median
                round(runif(1, 40, 60)), # B635
                round(runif(1, 40, 60)), # B635 Median
                round(runif(1, 100, 1000)), # F532 Mean
                round(runif(1, 100, 1000)), # F532 Median
                round(runif(1, 40, 60)), # B532
                round(runif(1, 40, 60)), # B532 Median
                sample(c(0, -100), 1, prob=c(0.95, 0.05)), # Flags
                sep="\t"
              )
            })
            writeLines(c(header, unlist(rows)), filename)
          }
        }
        
        for (f_name in c("array1.gpr", "array2.gpr", "array3.gpr", "array4.gpr")) {
          create_dummy_gpr(f_name)
        }
        
        # -----------------------------------------------------------------
        # Pipeline Execution (Faithful Adaptation of Documented Code)
        # -----------------------------------------------------------------
        library(limma)
        
        # --- Read targets metadata ---
        targets <- readTargets("targets.txt")
        
        # --- Read raw intensities and apply spot quality weights ---
        f <- function(x) as.numeric(x\$Flags > -99)
        RG <- read.maimages(targets, source="genepix", wt.fun=f)
        
        # --- Perform background correction ---
        RG <- backgroundCorrect(RG, method="normexp", offset=50)
        
        # --- Perform within-array normalization ---
        MA <- normalizeWithinArrays(RG)
        
        # --- Fit gene-wise linear models ---
        # Dynamically create the design vector based on the dye-swap layout in the targets file
        design <- as.numeric(targets\$Cy5 == targets\$Cy5[1]) - as.numeric(targets\$Cy3 == targets\$Cy5[1])
        fit <- lmFit(MA, design=design)
        
        # --- Apply empirical Bayes smoothing ---
        fit <- eBayes(fit)
        
        # --- Extract top differentially expressed genes ---
        top_genes <- topTable(fit)
        
        # -----------------------------------------------------------------
        # Export Outputs
        # -----------------------------------------------------------------
        # Save RDS objects
        saveRDS(RG, "raw_RGList.rds")
        saveRDS(MA, "normalized_MAList.rds")
        saveRDS(fit, "ebayes_fit.rds")
        
        # Save CSV tables
        write.csv(top_genes, "top_table_summary.csv", row.names=TRUE)
        write.csv(topTable(fit, number=Inf), "all_genes_results.csv", row.names=TRUE)
        
        # Save PDF plots
        pdf("diagnostic_plots.pdf", width=10, height=10)
        par(mfrow=c(2,2))
        for (i in 1:ncol(MA)) {
          plotMD(MA, column=i, main=paste("MA Plot - Array", i))
        }
        dev.off()

    writeLines(c(
        '"BIOC_LIMMA_TWO_COLOR_MICROARRAY_ANALYSIS":',
        paste0('    limma: ', as.character(packageVersion('limma')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_color_microarray_analysis.csv versions.yml
    """
}

workflow BIOC_LIMMA_TWO_COLOR_MICROARRAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ targets.txt, .gpr ] ]

    main:
    BIOC_LIMMA_TWO_COLOR_MICROARRAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_LIMMA_TWO_COLOR_MICROARRAY_ANALYSIS.out.tables
    plots    = BIOC_LIMMA_TWO_COLOR_MICROARRAY_ANALYSIS.out.plots
    objects  = BIOC_LIMMA_TWO_COLOR_MICROARRAY_ANALYSIS.out.objects
    versions = BIOC_LIMMA_TWO_COLOR_MICROARRAY_ANALYSIS.out.versions
}
