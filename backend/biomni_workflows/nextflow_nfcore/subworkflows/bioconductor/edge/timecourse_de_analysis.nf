#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: edge — timecourse_de_analysis
// Identify genes showing temporal differential expression over time (either within a single group or between different treatment groups) in longitudinal or indepe
// Input: kidexpr or endoexpr, sex or class, age or time, ind
// Container: quay.io/biocontainers/bioconductor-edge:2.42.0--r45h01b2380_0
// R packages: edge
// Bioconductor: 3.20 | R: 4.4
// Requires: edge
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Build the deSet object using build_study with sampling="timecourse" (specifying basis.df and optionally ind for longitudinal data)
//  * 2. [Core Analysis] Fit the models using fit_models
//  * 3. [Core Analysis] Perform significance testing using odp or lrt
//  * 4. [Core Analysis] Extract significance statistics (p-values, q-values, local FDR) using qvalueObj

nextflow.enable.dsl = 2

process BIOC_EDGE_TIMECOURSE_DE_ANALYSIS {
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
    .bm_deps <- c("edge")
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
    library(edge)
    library(splines)
    
    # Helper functions to read inputs robustly
    file_exists_any_ext <- function(base_name) {
      any(file.exists(paste0(base_name, c(".rds", ".RDS", ".csv", ".CSV", ".tsv", ".TSV"))))
    }
    
    read_matrix <- function(base_name) {
      for (ext in c(".rds", ".RDS", ".csv", ".CSV", ".tsv", ".TSV")) {
        fp <- paste0(base_name, ext)
        if (file.exists(fp)) {
          if (grepl("\\\\.rds\$", fp, ignore.case = TRUE)) {
            return(as.matrix(readRDS(fp)))
          } else {
            mat <- tryCatch({
              as.matrix(read.csv(fp, row.names = 1, check.names = FALSE))
            }, error = function(e) {
              as.matrix(read.csv(fp, check.names = FALSE))
            })
            return(mat)
          }
        }
      }
      stop(paste("Required matrix file not found for:", base_name))
    }
    
    read_vector <- function(base_name) {
      for (ext in c(".rds", ".RDS", ".csv", ".CSV", ".tsv", ".TSV")) {
        fp <- paste0(base_name, ext)
        if (file.exists(fp)) {
          if (grepl("\\\\.rds\$", fp, ignore.case = TRUE)) {
            val <- readRDS(fp)
            if (is.data.frame(val)) return(val[[1]])
            return(val)
          } else {
            df <- read.csv(fp, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE)
            if (ncol(df) == 2) {
              return(df[[2]])
            } else if (ncol(df) == 1) {
              return(df[[1]])
            } else {
              df_no_header <- read.csv(fp, header = FALSE, stringsAsFactors = FALSE)
              if (ncol(df_no_header) == 1) {
                return(df_no_header[[1]])
              }
              return(df_no_header[[2]])
            }
          }
        }
      }
      stop(paste("Required vector file not found for:", base_name))
    }
    
    # Determine which workflow to run based on available files
    if (file_exists_any_ext("kidexpr")) {
      message("Running independent timecourse DE analysis (kidney workflow)...")
      kidexpr <- read_matrix("kidexpr")
      sex <- read_vector("sex")
      age <- as.numeric(read_vector("age"))
      
      # Documented code call for independent timecourse
      de_obj <- build_study(data = kidexpr, adj.var = sex, tme = age, sampling = "timecourse", basis.df = 4)
      
    } else if (file_exists_any_ext("endoexpr")) {
      message("Running longitudinal timecourse DE analysis (endotoxin workflow)...")
      endoexpr <- read_matrix("endoexpr")
      class <- read_vector("class")
      time <- as.numeric(read_vector("time"))
      ind <- read_vector("ind")
      
      # Documented code call for longitudinal timecourse
      de_obj <- build_study(data = endoexpr, grp = class, tme = time, ind = ind, sampling = "timecourse")
      
    } else {
      stop("Neither 'kidexpr' nor 'endoexpr' files found in the working directory.")
    }
    
    # Common downstream analysis steps from documented code
    ef_obj <- fit_models(de_obj, stat.type="lrt")
    de_lrt <- lrt(de_obj, nullDistn="normal")
    de_odp <- odp(de_obj, bs.its = 50, verbose = FALSE, n.mods = 50)
    summary(de_odp)
    sig_results <- qvalueObj(de_odp)
    pvalues <- sig_results\$pvalues
    qvalues <- sig_results\$qvalues
    lfdr <- sig_results\$lfdr
    pi0 <- sig_results\$pi0
    
    # Write outputs
    message("Writing output files...")
    
    # 1. Save RDS objects
    saveRDS(de_obj, "de_obj.rds")
    saveRDS(ef_obj, "ef_obj.rds")
    saveRDS(de_lrt, "de_lrt.rds")
    saveRDS(de_odp, "de_odp.rds")
    saveRDS(sig_results, "sig_results.rds")
    
    # 2. Save CSV results table
    results_df <- data.frame(
      gene_id = rownames(de_obj),
      pvalue = pvalues,
      qvalue = qvalues,
      lfdr = lfdr,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "edge_timecourse_de_results.csv", row.names = FALSE)
    
    # 3. Save PDF plots
    pdf("edge_significance_plots.pdf", width = 8, height = 6)
    hist(sig_results)
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_EDGE_TIMECOURSE_DE_ANALYSIS":',
        paste0('    edge: ', as.character(packageVersion('edge')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_timecourse_de_analysis.csv versions.yml
    """
}

workflow BIOC_EDGE_TIMECOURSE_DE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kidexpr or endoexpr, sex or class, age or time, ind ] ]

    main:
    BIOC_EDGE_TIMECOURSE_DE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EDGE_TIMECOURSE_DE_ANALYSIS.out.tables
    plots    = BIOC_EDGE_TIMECOURSE_DE_ANALYSIS.out.plots
    objects  = BIOC_EDGE_TIMECOURSE_DE_ANALYSIS.out.objects
    versions = BIOC_EDGE_TIMECOURSE_DE_ANALYSIS.out.versions
}
