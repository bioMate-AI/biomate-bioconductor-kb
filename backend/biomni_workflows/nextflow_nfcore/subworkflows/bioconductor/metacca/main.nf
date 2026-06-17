#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaCCA — single_snp_multi_trait_analysis
// Test individual genetic variants one by one (or a specific selected SNP) for association with a set of phenotypic traits across one or more studies.
// Input: S_XY_full_study1, S_XY_full_study2, S_XY_study1, S_XY_study2
// Container: quay.io/biocontainers/bioconductor-metacca:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: metaCCA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate the phenotypic correlation structure (S_YY) for each study using estimateSyy
//  * 2. [Core Analysis] Run the single-SNP--multi-trait association analysis using metaCcaGp or metaCcaPlusGp

nextflow.enable.dsl = 2

process BIOC_METACCA_SINGLE_SNP_MULTI_TRAIT_ANALYSIS {
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
    .bm_deps <- c("metaCCA")
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
    
    # Load required library
    library(metaCCA)
    
    # Helper function to read input files with or without common extensions
    read_input <- function(filename) {
      possible_files <- c(
        filename,
        paste0(filename, ".txt"),
        paste0(filename, ".tsv"),
        paste0(filename, ".csv")
      )
      
      for (f in possible_files) {
        if (file.exists(f)) {
          # Determine separator based on extension or content
          sep <- if (grepl("\\\\.csv\$", f)) "," else ""
          return(read.table(f, header = TRUE, row.names = 1, sep = sep, stringsAsFactors = FALSE))
        }
      }
      stop(paste("Required input file not found:", filename))
    }
    
    # Read user input files from the working directory
    S_XY_full_study1 <- read_input("S_XY_full_study1")
    S_XY_full_study2 <- read_input("S_XY_full_study2")
    S_XY_study1      <- read_input("S_XY_study1")
    S_XY_study2      <- read_input("S_XY_study2")
    
    # Read sample sizes N1 and N2 if provided in the working directory, otherwise default to vignette values
    N1 <- if (file.exists("N1")) {
      as.numeric(readLines("N1", warn = FALSE)[1])
    } else if (file.exists("N1.txt")) {
      as.numeric(readLines("N1.txt", warn = FALSE)[1])
    } else {
      1000
    }
    
    N2 <- if (file.exists("N2")) {
      as.numeric(readLines("N2", warn = FALSE)[1])
    } else if (file.exists("N2.txt")) {
      as.numeric(readLines("N2.txt", warn = FALSE)[1])
    } else {
      2000
    }
    
    # 1. Estimate the phenotypic correlation structure (S_YY) for each study
    S_YY_study1 = estimateSyy( S_XY = S_XY_full_study1 )
    S_YY_study2 = estimateSyy( S_XY = S_XY_full_study2 )
    
    # 2. Run the single-SNP--multi-trait association analysis using metaCcaGp and metaCcaPlusGp
    metaCCA_res1 = metaCcaGp( nr_studies = 2,
                              S_XY = list( S_XY_study1, S_XY_study2 ),
                              std_info = c( 0, 0 ),
                              S_YY = list( S_YY_study1, S_YY_study2 ),
                              N = c( N1, N2) )
    
    metaCCApl_res1 = metaCcaPlusGp( nr_studies = 2,
                                    S_XY = list( S_XY_study1, S_XY_study2 ),
                                    std_info = c( 0, 0 ),
                                    S_YY = list( S_YY_study1, S_YY_study2 ),
                                    N = c( N1, N2 ) )
    
    # Write meaningful results to output files
    write.csv(metaCCA_res1, "metaCCA_results.csv", row.names = TRUE)
    write.csv(metaCCApl_res1, "metaCCA_plus_results.csv", row.names = TRUE)
    
    saveRDS(metaCCA_res1, "metaCCA_results.rds")
    saveRDS(metaCCApl_res1, "metaCCA_plus_results.rds")
    saveRDS(S_YY_study1, "S_YY_study1.rds")
    saveRDS(S_YY_study2, "S_YY_study2.rds")
    
    # Generate a diagnostic plot comparing -log10(p-values) of metaCCA and metaCCA+
    pdf("p_value_comparison.pdf", width = 6, height = 6)
    plot(metaCCA_res1\$"-log10(p-val)", metaCCApl_res1\$"-log10(p-val)",
         xlab = "-log10(p-value) metaCCA",
         ylab = "-log10(p-value) metaCCA+",
         main = "P-value Comparison: metaCCA vs metaCCA+",
         pch = 19, col = "blue")
    abline(a = 0, b = 1, col = "red", lty = 2)
    dev.off()

    writeLines(c(
        '"BIOC_METACCA_SINGLE_SNP_MULTI_TRAIT_ANALYSIS":',
        paste0('    metaCCA: ', as.character(packageVersion('metaCCA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_snp_multi_trait_analysis.csv versions.yml
    """
}

workflow BIOC_METACCA_SINGLE_SNP_MULTI_TRAIT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ S_XY_full_study1, S_XY_full_study2, S_XY_study1, S_XY_study2 ] ]

    main:
    BIOC_METACCA_SINGLE_SNP_MULTI_TRAIT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METACCA_SINGLE_SNP_MULTI_TRAIT_ANALYSIS.out.tables
    plots    = BIOC_METACCA_SINGLE_SNP_MULTI_TRAIT_ANALYSIS.out.plots
    objects  = BIOC_METACCA_SINGLE_SNP_MULTI_TRAIT_ANALYSIS.out.objects
    versions = BIOC_METACCA_SINGLE_SNP_MULTI_TRAIT_ANALYSIS.out.versions
}
