#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PolySTest — quantitative_omics_differential_testing
// Perform differential abundance testing on quantitative omics data with missing values using multiple statistical tests and visualize the results.
// Input: LiverAllProteins.csv, sampleMetadata
// Container: quay.io/biocontainers/bioconductor-polystest:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PolySTest, SummarizedExperiment, htmlwidgets, matrixStats
// Visualizations: expression plot, volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and preprocess quantitative data (subsetting and median normalization)
//  * 2. [Visualization & Output] Construct a SummarizedExperiment object with assays, colData, rowData, and metadata
//  * 3. [Core Analysis] Update conditions using update_conditions_with_lcs
//  * 4. [Input & Preparation] Define pairwise comparisons using create_pairwise_comparisons
//  * 5. [Core Analysis] Run statistical testing using PolySTest_unpaired (or PolySTest_paired for matched samples)
//  * 6. [Visualization & Output] Visualize results using p-value distribution, volcano, UpSet, expression, regulation number, and heatmap plots

nextflow.enable.dsl = 2

process BIOC_POLYSTEST_QUANTITATIVE_OMICS_DIFFERENTIAL_TESTING {
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
    .bm_deps <- c("PolySTest", "matrixStats", "SummarizedExperiment")
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
    
    # Load required libraries    library(SummarizedExperiment)

    library(PolySTest)
    library(matrixStats)
    
    # 1. Load and preprocess quantitative data
    # Read quantitative features from LiverAllProteins.csv
    if (!file.exists("LiverAllProteins.csv")) {
      stop("Error: 'LiverAllProteins.csv' not found in the working directory.")
    }
    dat <- read.csv("LiverAllProteins.csv", row.names = 1, stringsAsFactors = FALSE)
    
    # Median normalization
    dat <- t(t(dat) - colMedians(as.matrix(dat), na.rm = TRUE))
    
    # Read sample metadata
    if (file.exists("sampleMetadata.csv")) {
      sampleMetadata <- read.csv("sampleMetadata.csv", stringsAsFactors = FALSE)
    } else if (file.exists("sampleMetadata")) {
      sampleMetadata <- read.csv("sampleMetadata", stringsAsFactors = FALSE)
    } else {
      stop("Error: 'sampleMetadata' or 'sampleMetadata.csv' not found in the working directory.")
    }
    
    # 2. Construct a SummarizedExperiment object
    fulldata <- SummarizedExperiment(assays = list(quant = dat), 
                                     colData = sampleMetadata)
    rowData(fulldata) <- rownames(dat)
    
    # Dynamically determine the number of replicates and conditions
    num_reps <- if ("Replicate" %in% colnames(sampleMetadata)) length(unique(sampleMetadata\$Replicate)) else 3
    num_cond <- if ("Condition" %in% colnames(sampleMetadata)) length(unique(sampleMetadata\$Condition)) else 4
    metadata(fulldata) <- list(NumReps = num_reps, NumCond = num_cond)
    
    assay(fulldata, "quant") <- dat
    
    # 3. Update conditions using update_conditions_with_lcs
    fulldata <- update_conditions_with_lcs(fulldata)
    
    # 4. Define pairwise comparisons using create_pairwise_comparisons
    conditions <- unique(colData(fulldata)\$Condition)
    allComps <- create_pairwise_comparisons(conditions, 1)
    
    # 5. Run statistical testing using PolySTest_unpaired
    fulldata_unpaired <- PolySTest_unpaired(fulldata, allComps)
    
    # Define comparisons to visualize from available ones
    compNames <- metadata(fulldata_unpaired)\$compNames
    print(compNames)
    comps <- compNames[1]
    
    # Select proteins with FDR < 0.01 for downstream visualization
    sigProts <- which(rowData(fulldata_unpaired)[, paste0("FDR_PolySTest_", comps[1])] < 0.01)
    
    # 6. Visualize results and save to files
    pdf("pvalue_distribution.pdf", width = 7, height = 4)
    plotPvalueDistr(fulldata_unpaired, comps, c("limma", "Miss Test"))
    dev.off()
    
    pdf("volcano_plot.pdf", width = 7, height = 4)
    if (length(sigProts) > 0) {
      plotVolcano(fulldata_unpaired, compNames = comps, sel_prots = sigProts, 
                  testNames = c("PolySTest", "limma", "Miss Test"))
    } else {
      plotVolcano(fulldata_unpaired, compNames = comps, 
                  testNames = c("PolySTest", "limma", "Miss Test"))
    }
    dev.off()
    
    pdf("upset_plot.pdf", width = 7, height = 4)
    plotUpset(fulldata_unpaired, qlim = 0.01)
    dev.off()
    
    if (length(sigProts) > 0) {
      # Limit selected proteins to a maximum of 20 to avoid overloaded expression plots
      sigProts_expr <- if (length(sigProts) > 20) sigProts[1:20] else sigProts
      pdf("expression_profiles.pdf", width = 8, height = 6)
      plotExpression(fulldata_unpaired, sel_prots = sigProts_expr)
      dev.off()
    } else {
      message("No significant proteins found; skipping expression profiles plot.")
    }
    
    pdf("regulation_number.pdf", width = 7, height = 4)
    plotRegNumber(fulldata_unpaired)
    dev.off()
    
    if (length(sigProts) > 0) {
      tryCatch({
        p <- plotHeatmaply(fulldata_unpaired, sel_prots = sigProts, heatmap_scale = "row")
        htmlwidgets::saveWidget(p, "heatmap.html")
      }, error = function(e) {
        message("Could not save heatmaply plot to HTML: ", e\$message)
      })
    } else {
      message("No significant proteins found; skipping heatmap.")
    }
    
    # Save meaningful results to output files
    write.csv(as.data.frame(rowData(fulldata_unpaired)), "differential_abundance_results.csv", row.names = TRUE)
    saveRDS(fulldata_unpaired, "fulldata_unpaired.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_POLYSTEST_QUANTITATIVE_OMICS_DIFFERENTIAL_TESTING":',
        paste0('    PolySTest: ', as.character(packageVersion('PolySTest')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quantitative_omics_differential_testing.csv versions.yml
    """
}

workflow BIOC_POLYSTEST_QUANTITATIVE_OMICS_DIFFERENTIAL_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ LiverAllProteins.csv, sampleMetadata ] ]

    main:
    BIOC_POLYSTEST_QUANTITATIVE_OMICS_DIFFERENTIAL_TESTING(ch_input)

    emit:
    tables   = BIOC_POLYSTEST_QUANTITATIVE_OMICS_DIFFERENTIAL_TESTING.out.tables
    plots    = BIOC_POLYSTEST_QUANTITATIVE_OMICS_DIFFERENTIAL_TESTING.out.plots
    objects  = BIOC_POLYSTEST_QUANTITATIVE_OMICS_DIFFERENTIAL_TESTING.out.objects
    versions = BIOC_POLYSTEST_QUANTITATIVE_OMICS_DIFFERENTIAL_TESTING.out.versions
}
