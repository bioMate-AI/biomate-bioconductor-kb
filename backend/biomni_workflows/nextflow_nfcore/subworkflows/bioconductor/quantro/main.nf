#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: quantro — quantro_normalization_test
// Test for global differences in distributions between sample groups to determine if global normalization is appropriate.
// Input: raw_data.matrix, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-quantro:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, doParallel, quantro
// Visualizations: density plot, box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Visualize raw sample distributions using matdensity and matboxplot
//  * 2. [Core Analysis] Run the main quantro test to calculate the test statistic and perform ANOVA on medians
//  * 3. [Core Analysis] Perform permutation testing with a registered parallel backend to assess statistical significance
//  * 4. [Visualization & Output] Plot the permutation test results using quantroPlot

nextflow.enable.dsl = 2

process BIOC_QUANTRO_QUANTRO_NORMALIZATION_TEST {
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
    .bm_deps <- c("quantro", "Biobase", "doParallel")
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
            library(quantro)
            library(Biobase)
            library(doParallel)
            
            # ==========================================
            # 1. Read User Input Files and Setup Data
            # ==========================================
            
            # Read raw data matrix
            if (file.exists("raw_data.matrix")) {
              p <- tryCatch({
                as.matrix(read.table("raw_data.matrix", header = TRUE, row.names = 1, check.names = FALSE))
              }, error = function(e) {
                as.matrix(read.csv("raw_data.matrix", header = TRUE, row.names = 1, check.names = FALSE))
              })
            } else {
              stop("Error: raw_data.matrix not found in the working directory.")
            }
            
            # Read sample metadata
            if (file.exists("sample_metadata.csv")) {
              pd <- read.csv("sample_metadata.csv", header = TRUE, row.names = 1, check.names = FALSE)
            } else {
              stop("Error: sample_metadata.csv not found in the working directory.")
            }
            
            # Align columns of raw data with rows of metadata
            common_samples <- intersect(colnames(p), rownames(pd))
            if (length(common_samples) == 0) {
              stop("Error: No matching sample names found between raw_data.matrix columns and sample_metadata.csv rows.")
            }
            p <- p[, common_samples, drop = FALSE]
            pd <- pd[common_samples, , drop = FALSE]
            
            # Ensure CellType column exists in metadata (fallback to first column if missing)
            if (!"CellType" %in% colnames(pd)) {
              group_col <- grep("group|type|cell|class|treatment", colnames(pd), ignore.case = TRUE, value = TRUE)
              if (length(group_col) > 0) {
                pd\$CellType <- pd[[group_col[1]]]
              } else {
                pd\$CellType <- pd[[1]]
              }
            }
            pd\$CellType <- as.factor(pd\$CellType)
            
            # ==========================================
            # 2. Visualize Raw Sample Distributions
            # ==========================================
            
            # Plot and save density plot
            pdf("density_plots.pdf", width = 7, height = 5)
            matdensity(p, groupFactor = pd\$CellType, xlab = " ", ylab = "density",
                       main = "Density Plot", brewer.n = 8, brewer.name = "Dark2")
            legend('top', levels(pd\$CellType), col = 1:length(levels(pd\$CellType)), lty = 1, lwd = 3)
            dev.off()
            
            # Plot and save boxplot
            pdf("boxplots.pdf", width = 7, height = 5)
            matboxplot(p, groupFactor = pd\$CellType, xaxt = "n", main = "Boxplot")
            dev.off()
            
            # ==========================================
            # 3. Run Main quantro Test & ANOVA
            # ==========================================
            
            qtest <- quantro(object = p, groupFactor = pd\$CellType)
            qtest
            summary(qtest)
            anova(qtest)
            quantroStat(qtest)
            
            # ==========================================
            # 4. Perform Permutation Testing
            # ==========================================
            
            registerDoParallel(cores=1)
            qtestPerm <- quantro(p, groupFactor = pd\$CellType, B = 1000)
            qtestPerm
            
            # ==========================================
            # 5. Plot Permutation Test Results
            # ==========================================
            
            pdf("quantro_permutation_plot.pdf", width = 7, height = 5)
            quantroPlot(qtestPerm)
            dev.off()
            
            # ==========================================
            # 6. Save Outputs to Files
            # ==========================================
            
            # Save RDS objects of the test results
            saveRDS(qtest, "quantro_results.rds")
            saveRDS(qtestPerm, "quantro_perm_results.rds")
            
            # Save ANOVA table as CSV
            write.csv(as.data.frame(anova(qtest)), "quantro_anova.csv", row.names = TRUE)
            
            # Save summary text
            sink("quantro_summary.txt")
            print(summary(qtest))
            sink()
            
            # Save the main test statistic
            writeLines(as.character(quantroStat(qtest)), "quantro_stat.txt")

    writeLines(c(
        '"BIOC_QUANTRO_QUANTRO_NORMALIZATION_TEST":',
        paste0('    quantro: ', as.character(packageVersion('quantro')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quantro_normalization_test.csv versions.yml
    """
}

workflow BIOC_QUANTRO_QUANTRO_NORMALIZATION_TEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_data.matrix, sample_metadata.csv ] ]

    main:
    BIOC_QUANTRO_QUANTRO_NORMALIZATION_TEST(ch_input)

    emit:
    tables   = BIOC_QUANTRO_QUANTRO_NORMALIZATION_TEST.out.tables
    plots    = BIOC_QUANTRO_QUANTRO_NORMALIZATION_TEST.out.plots
    objects  = BIOC_QUANTRO_QUANTRO_NORMALIZATION_TEST.out.objects
    versions = BIOC_QUANTRO_QUANTRO_NORMALIZATION_TEST.out.versions
}
