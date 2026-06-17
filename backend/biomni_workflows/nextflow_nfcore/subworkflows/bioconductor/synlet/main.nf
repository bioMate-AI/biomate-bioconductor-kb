#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: synlet — synthetic_lethal_rnai_screen_analysis
// Process synthetic lethal RNAi screen data, perform quality control, visualize results, and identify hit genes using multiple statistical methods.
// Input: screen_results.csv
// Container: quay.io/biocontainers/bioconductor-synlet:2.10.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: data.table, synlet
// Visualizations: heatmap, scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load package and data
//  * 2. [Core Analysis] Calculate Z and Z' factors for quality control
//  * 3. [Visualization & Output] Visualize screen data using heatmaps and scatter plots
//  * 4. [Visualization & Output] Plot knock-down effects for individual genes of interest
//  * 5. [Core Analysis] Calculate robust B-scores and perform Student's t-test
//  * 6. [Core Analysis] Perform hit selection using Median ± k MAD
//  * 7. [Core Analysis] Perform hit selection using Rank Products
//  * 8. [Core Analysis] Perform hit selection using Redundant siRNA Activity (RSA)

nextflow.enable.dsl = 2

process BIOC_SYNLET_SYNTHETIC_LETHAL_RNAI_SCREEN_ANALYSIS {
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
    .bm_deps <- c("synlet", "data.table")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # 1. Load package and data
    library(synlet)
    library(data.table)
    
    # Read the user input file
    example_dt <- fread("screen_results.csv")
    
    # Dynamically extract names and counts from the data to avoid hardcoding
    if (nrow(example_dt) > 0) {
      first_mp <- unique(example_dt\$MASTER_PLATE)[1]
      
      samples <- example_dt[EXPERIMENT_TYPE == "sample"]
      if (nrow(samples) > 0) {
        first_sample_gene <- sub(" si[0-9]+\$", "", samples\$WELL_CONTENT_NAME[1])
      } else {
        first_sample_gene <- "AAK1"
      }
      
      neg_controls <- unique(example_dt[EXPERIMENT_TYPE == "control_negative"]\$WELL_CONTENT_NAME)
      pos_controls <- unique(example_dt[EXPERIMENT_TYPE == "control_positive"]\$WELL_CONTENT_NAME)
      
      neg_con <- if (length(neg_controls) > 0) neg_controls[1] else "scrambled control si1"
      pos_con <- if (length(pos_controls) > 0) pos_controls[1] else "PLK1 si1"
      
      all_controls <- unique(c(pos_controls, neg_controls))
      if (length(all_controls) == 0) {
        all_controls <- c("PLK1 si1", "scrambled control si1", "lipid only")
      }
      
      num_treat <- length(unique(example_dt[MASTER_PLATE == first_mp & EXPERIMENT_MODIFICATION == "treatment"]\$PLATE))
      num_cont <- length(unique(example_dt[MASTER_PLATE == first_mp & EXPERIMENT_MODIFICATION == "control"]\$PLATE))
      
      if (num_treat == 0) num_treat <- 3
      if (num_cont == 0) num_cont <- 3
    } else {
      first_mp <- "P001"
      first_sample_gene <- "AAK1"
      neg_controls <- c("lipid only", "scrambled control si1")
      pos_controls <- "PLK1 si1"
      neg_con <- "scrambled control si1"
      pos_con <- "PLK1 si1"
      all_controls <- c("PLK1 si1", "scrambled control si1", "lipid only")
      num_treat <- 3
      num_cont <- 3
    }
    
    # 2. Calculate Z and Z' factors for quality control
    res <- zFactor(example_dt, negativeCon = neg_con, positiveCon = pos_con)
    head(res)
    write.csv(res, "zFactor_results.csv", row.names = TRUE)
    
    # 3. Visualize screen data using heatmaps and scatter plots
    pdf("plate_heatmap.pdf", width = 12, height = 10)
    plateHeatmap(example_dt)
    dev.off()
    
    pdf("scatter_plot.pdf", width = 12, height = 10)
    scatterPlot(example_dt, controlOnly = FALSE, control_name = all_controls)
    dev.off()
    
    # 4. Plot knock-down effects for individual genes of interest
    zF_mean <- zFactor(example_dt, negativeCon = neg_con, positiveCon = pos_con)
    zF_med <- zFactor(example_dt, negativeCon = neg_con, positiveCon = pos_con, useMean = FALSE)
    
    siRNAPlot(first_sample_gene, example_dt,
               controlsiRNA = neg_controls,
               FILEPATH = ".",  zPrimeMed = zF_med, zPrimeMean = zF_mean,
               treatment = "treatment", control = "control",
               normMethod = c("PLATE", neg_controls))
    
    # 5. Calculate robust B-scores and perform Student's t-test
    bscore_res <- sapply(first_mp, bScore, example_dt, treatment = "treatment", control = "control", simplify = FALSE)
    head(bscore_res[[first_mp]])
    saveRDS(bscore_res, "bscore_results.rds")
    
    t_res <- tTest(bscore_res[[first_mp]], num_treat, num_cont)
    head(t_res)
    write.csv(t_res, "t_test_results.csv", row.names = TRUE)
    
    # 6. Perform hit selection using Median ± k MAD
    mad_res <- sapply((unique(example_dt\$MASTER_PLATE)),
                      madSelect,
                      example_dt,
                      control   = "control",
                      treatment = "treatment",
                      simplify  = FALSE)
    head(mad_res[[first_mp]])
    saveRDS(mad_res, "mad_results.rds")
    
    # 7. Perform hit selection using Rank Products
    rp_res <- sapply(unique(example_dt\$MASTER_PLATE),
                     rankProdHits,
                     example_dt,
                     control   = "control",
                     treatment = "treatment",
                     simplify  = FALSE)
    head(rp_res)
    saveRDS(rp_res, "rankprod_results.rds")
    
    # 8. Perform hit selection using Redundant siRNA Activity (RSA)
    rsaHits(example_dt, treatment = "treatment", control = "control",
            normMethod = "PLATE", LB = 0.2, UB = 0.8, revHits = FALSE,
            Bonferroni = FALSE, outputFile = "RSAhits.csv")

    writeLines(c(
        '"BIOC_SYNLET_SYNTHETIC_LETHAL_RNAI_SCREEN_ANALYSIS":',
        paste0('    synlet: ', as.character(packageVersion('synlet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_synthetic_lethal_rnai_screen_analysis.csv versions.yml
    """
}

workflow BIOC_SYNLET_SYNTHETIC_LETHAL_RNAI_SCREEN_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ screen_results.csv ] ]

    main:
    BIOC_SYNLET_SYNTHETIC_LETHAL_RNAI_SCREEN_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SYNLET_SYNTHETIC_LETHAL_RNAI_SCREEN_ANALYSIS.out.tables
    plots    = BIOC_SYNLET_SYNTHETIC_LETHAL_RNAI_SCREEN_ANALYSIS.out.plots
    objects  = BIOC_SYNLET_SYNTHETIC_LETHAL_RNAI_SCREEN_ANALYSIS.out.objects
    versions = BIOC_SYNLET_SYNTHETIC_LETHAL_RNAI_SCREEN_ANALYSIS.out.versions
}
