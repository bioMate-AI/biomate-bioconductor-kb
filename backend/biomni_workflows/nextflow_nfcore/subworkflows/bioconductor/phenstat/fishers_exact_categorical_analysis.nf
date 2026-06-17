#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PhenStat — fishers_exact_categorical_analysis
// Perform Fisher's exact test on categorical phenotypic data to determine association between genotype and a categorical outcome.
// Input: categorical_phenotypic_data.csv
// Container: quay.io/biocontainers/bioconductor-phenstat:2.42.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PhenStat
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and create a PhenList object using PhenList()
//  * 2. [Core Analysis] Run the statistical analysis using testDataset() with method="FE"
//  * 3. [Core Analysis] Extract classification tags using classificationTag()

nextflow.enable.dsl = 2

process BIOC_PHENSTAT_FISHERS_EXACT_CATEGORICAL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("PhenStat")
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
    
    # Load the required library
    library(PhenStat)
    
    # 1. Load data and create a PhenList object
    dataset <- read.csv("categorical_phenotypic_data.csv")
    
    phenList <- PhenList(
      dataset, 
      testGenotype="KO", 
      refGenotype="WT", 
      dataset.colname.genotype="Genotype", 
      dataset.colname.sex="Sex"
    )
    
    # 2. Run the statistical analysis using Fisher's Exact Test (FE)
    result <- testDataset(
      phenList, 
      depVariable="CategoryValue", 
      method="FE"
    )
    
    # 3. Extract classification tags
    tag <- classificationTag(result)
    
    # 4. Save meaningful results to output files
    # Save the complete PhenTestResult object
    saveRDS(result, file = "phenstat_fe_result.rds")
    
    # Save the classification tag to a text file
    writeLines(tag, con = "classification_tag.txt")
    
    # Extract and save the vector output (standard PhenStat summary statistics)
    if (exists("vectorOutput")) {
      val_vector <- vectorOutput(result)
      write.csv(as.data.frame(t(val_vector)), file = "phenstat_fe_summary.csv", row.names = FALSE)
    }
    
    # Generate and save a contingency table plot if applicable
    pdf("contingency_plots.pdf")
    tryCatch({
      # PhenStat has built-in plotting for FE, typically via plot() on the result object
      plot(result)
    }, error = function(e) {
      message("Plotting not supported or failed: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_PHENSTAT_FISHERS_EXACT_CATEGORICAL_ANALYSIS":',
        paste0('    PhenStat: ', as.character(packageVersion('PhenStat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fishers_exact_categorical_analysis.csv versions.yml
    """
}

workflow BIOC_PHENSTAT_FISHERS_EXACT_CATEGORICAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ categorical_phenotypic_data.csv ] ]

    main:
    BIOC_PHENSTAT_FISHERS_EXACT_CATEGORICAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PHENSTAT_FISHERS_EXACT_CATEGORICAL_ANALYSIS.out.tables
    plots    = BIOC_PHENSTAT_FISHERS_EXACT_CATEGORICAL_ANALYSIS.out.plots
    objects  = BIOC_PHENSTAT_FISHERS_EXACT_CATEGORICAL_ANALYSIS.out.objects
    versions = BIOC_PHENSTAT_FISHERS_EXACT_CATEGORICAL_ANALYSIS.out.versions
}
