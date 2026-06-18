#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alphabeta — selfing_epimutation_analysis
// Estimate germline epimutation rates and test for selection in selfing-derived mutation accumulation lines.
// Input: nodelist.fn, edgelist.fn, methylome_files
// Container: quay.io/biocontainers/bioconductor-alphabeta:1.24.0--r45hdfd78af_0
// R packages: AlphaBeta, data.table, ggplot2, igraph
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_ALPHABETA_SELFING_EPIMUTATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-alphabeta:1.24.0--r45hdfd78af_0"

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
    .bm_deps <- c("AlphaBeta", "data.table", "ggplot2", "igraph")
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
    
    # Load required libraries
    library(AlphaBeta)
    library(data.table)
    library(igraph)
    library(ggplot2)
    
    # Define input file paths from the working directory
    sampleFile <- "nodelist.fn"
    edgesFile <- "edgelist.fn"
    out.dir <- getwd()
    output.data.dir <- getwd()
    
    # --- Build the pedigree and calculate pairwise divergence ---
    output <- buildPedigree(
      nodelist = sampleFile,
      edgelist = edgesFile,
      cytosine = "CG",
      posteriorMaxFilter = 0.99
    )
    
    # --- Generate diagnostic pedigree plots ---
    plotPedigree(
      nodelist = sampleFile,
      edgelist = edgesFile,
      sampling.design = "progenitor.endpoint",
      output.dir = out.dir,
      plot.width = 5,
      plot.height = 5,
      aspect.ratio = 1,
      vertex.size = 6,
      vertex.label = FALSE,
      out.pdf = "MA1_1"
    )
    
    # --- Plot divergence values against delta.t to inspect for ---
    pedigree <- output\$Pdata
    dt <- pedigree[, 2] + pedigree[, 3] - 2 * pedigree[, 1]
    
    pdf("divergence_vs_deltat.pdf", width = 6, height = 6)
    plot(dt, pedigree[, "D.value"], ylab = "Divergence value", xlab = expression(paste(Delta, " t")))
    dev.off()
    
    # --- Fit the neutral epimutation model ---
    p0uu_in <- output\$tmpp0
    output_neutral <- ABneutral(
      pedigree.data = pedigree,
      p0uu = p0uu_in,
      eqp = p0uu_in,
      eqp.weight = 1,
      Nstarts = 2,
      out.dir = output.data.dir,
      out.name = "ABneutral_CG_global_estimates"
    )
    
    # --- Fit selection models (against gains or losses) ---
    outputABselectMM <- ABselectMM(
      pedigree.data = pedigree,
      p0uu = p0uu_in,
      eqp = p0uu_in,
      eqp.weight = 1,
      Nstarts = 2,
      out.dir = output.data.dir,
      out.name = "ABselectMM_CG_global_estimates"
    )
    
    outputABselectUU <- ABselectUU(
      pedigree.data = pedigree,
      p0uu = p0uu_in,
      eqp = p0uu_in,
      eqp.weight = 1,
      Nstarts = 2,
      out.dir = output.data.dir,
      out.name = "ABselectUU_CG_global_estimates"
    )
    
    # --- Fit the null model (no epimutation accumulation) ---
    outputABnull <- ABnull(
      pedigree.data = pedigree,
      out.dir = output.data.dir,
      out.name = "ABnull_CG_global_estimates"
    )
    
    # --- Compare models using FtestRSS to select the best-fitting ---
    file_neutral <- file.path(output.data.dir, "ABneutral_CG_global_estimates.Rdata")
    file_selectMM <- file.path(output.data.dir, "ABselectMM_CG_global_estimates.Rdata")
    file_selectUU <- file.path(output.data.dir, "ABselectUU_CG_global_estimates.Rdata")
    file_null <- file.path(output.data.dir, "ABnull_CG_global_estimates.Rdata")
    
    out_neutral_vs_null <- FtestRSS(pedigree.select = file_neutral, pedigree.null = file_null)
    out_selectMM_vs_null <- FtestRSS(pedigree.select = file_selectMM, pedigree.null = file_null)
    out_selectUU_vs_null <- FtestRSS(pedigree.select = file_selectUU, pedigree.null = file_null)
    
    # Save F-test results to a CSV file
    ftest_df <- data.frame(
      Comparison = c("Neutral_vs_Null", "SelectMM_vs_Null", "SelectUU_vs_Null"),
      RSS_F = c(out_neutral_vs_null\$Ftest\$RSS_F, out_selectMM_vs_null\$Ftest\$RSS_F, out_selectUU_vs_null\$Ftest\$RSS_F),
      RSS_R = c(out_neutral_vs_null\$Ftest\$RSS_R, out_selectMM_vs_null\$Ftest\$RSS_R, out_selectUU_vs_null\$Ftest\$RSS_R),
      df_F = c(out_neutral_vs_null\$Ftest\$df_F, out_selectMM_vs_null\$Ftest\$df_F, out_selectUU_vs_null\$Ftest\$df_F),
      df_R = c(out_neutral_vs_null\$Ftest\$df_R, out_selectMM_vs_null\$Ftest\$df_R, out_selectUU_vs_null\$Ftest\$df_R),
      Fvalue = c(out_neutral_vs_null\$Ftest\$Fvalue, out_selectMM_vs_null\$Ftest\$Fvalue, out_selectUU_vs_null\$Ftest\$Fvalue),
      pvalue = c(out_neutral_vs_null\$Ftest\$pvalue, out_selectMM_vs_null\$Ftest\$pvalue, out_selectUU_vs_null\$Ftest\$pvalue)
    )
    write.csv(ftest_df, "Ftest_results.csv", row.names = FALSE)
    
    # --- Perform bootstrap analysis on the best-fitting model ---
    inputModel <- file_neutral
    Boutput <- BOOTmodel(
      pedigree.data = inputModel,
      Nboot = 2,
      out.dir = getwd(),
      out.name = "ABneutral_Boot_CG_global_estimates"
    )
    
    # Save bootstrap standard errors
    write.csv(as.data.frame(Boutput\$standard.errors), "bootstrap_standard_errors.csv")
    
    # --- Plot the final model fit ---
    ABfile <- file_neutral
    ABplot(
      pedigree.names = ABfile,
      output.dir = getwd(),
      out.name = "ABneutral",
      plot.height = 8,
      plot.width = 11
    )

    writeLines(c(
        '"BIOC_ALPHABETA_SELFING_EPIMUTATION_ANALYSIS":',
        paste0('        alphabeta: ', as.character(packageVersion("alphabeta")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_selfing_epimutation_analysis.csv versions.yml
    """
}

workflow BIOC_ALPHABETA_SELFING_EPIMUTATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ nodelist.fn, edgelist.fn, methylome_files ] ]

    main:
    BIOC_ALPHABETA_SELFING_EPIMUTATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ALPHABETA_SELFING_EPIMUTATION_ANALYSIS.out.tables
    plots    = BIOC_ALPHABETA_SELFING_EPIMUTATION_ANALYSIS.out.plots
    objects  = BIOC_ALPHABETA_SELFING_EPIMUTATION_ANALYSIS.out.objects
    versions = BIOC_ALPHABETA_SELFING_EPIMUTATION_ANALYSIS.out.versions
}
