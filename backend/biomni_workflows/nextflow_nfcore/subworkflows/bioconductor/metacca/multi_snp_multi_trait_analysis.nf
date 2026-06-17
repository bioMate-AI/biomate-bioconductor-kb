#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaCCA — multi_snp_multi_trait_analysis
// Test a set of genetic variants jointly for association with a set of phenotypic traits across one or more studies.
// Input: S_XY_full_study1, S_XY_full_study2, S_XY_study1, S_XY_study2, S_XX_study1, S_XX_study2
// Container: quay.io/biocontainers/bioconductor-metacca:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: metaCCA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate the phenotypic correlation structure (S_YY) for each study using estimateSyy
//  * 2. [Core Analysis] Run the multi-SNP--multi-trait association analysis using metaCcaGp or metaCcaPlusGp with analysis_type = 2 and providing the S_XX

nextflow.enable.dsl = 2

process BIOC_METACCA_MULTI_SNP_MULTI_TRAIT_ANALYSIS {
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
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input Files
        # -----------------------------------------------------------------------------
        
        # Read univariate summary statistics across a large number of SNPs
        S_XY_full_study1 <- read.table("S_XY_full_study1", header = TRUE, row.names = 1)
        S_XY_full_study2 <- read.table("S_XY_full_study2", header = TRUE, row.names = 1)
        
        # Read univariate summary statistics across the target SNPs
        S_XY_study1 <- read.table("S_XY_study1", header = TRUE, row.names = 1)
        S_XY_study2 <- read.table("S_XY_study2", header = TRUE, row.names = 1)
        
        # Read correlations between target SNPs
        S_XX_study1 <- read.table("S_XX_study1", header = TRUE, row.names = 1)
        S_XX_study2 <- read.table("S_XX_study2", header = TRUE, row.names = 1)
        
        # Read sample sizes N1 and N2 from files if they exist, otherwise use defaults
        N1 <- 1000
        if (file.exists("N1")) {
          N1 <- as.numeric(readLines("N1", n = 1))
        } else if (file.exists("N1.txt")) {
          N1 <- as.numeric(readLines("N1.txt", n = 1))
        }
        
        N2 <- 2000
        if (file.exists("N2")) {
          N2 <- as.numeric(readLines("N2", n = 1))
        } else if (file.exists("N2.txt")) {
          N2 <- as.numeric(readLines("N2.txt", n = 1))
        }
        
        # -----------------------------------------------------------------------------
        # 2. Estimate Phenotypic Correlation Structure (S_YY)
        # -----------------------------------------------------------------------------
        
        S_YY_study1 = estimateSyy( S_XY = S_XY_full_study1 )
        S_YY_study2 = estimateSyy( S_XY = S_XY_full_study2 )
        
        # -----------------------------------------------------------------------------
        # 3. Run Multi-SNP--Multi-Trait Association Analysis
        # -----------------------------------------------------------------------------
        
        # Run analysis using metaCCA algorithm
        metaCCA_res3 = metaCcaGp( nr_studies = 2,
                                  S_XY = list( S_XY_study1, S_XY_study2 ),
                                  std_info = c( 0, 0 ),
                                  S_YY = list( S_YY_study1, S_YY_study2 ),
                                  N = c( N1, N2 ),
                                  analysis_type = 2,
                                  SNP_id = rownames(S_XX_study1),
                                  S_XX = list( S_XX_study1, S_XX_study2 ) )
        
        # Run analysis using metaCCA+ algorithm
        metaCCApl_res3 = metaCcaPlusGp( nr_studies = 2,
                                        S_XY = list( S_XY_study1, S_XY_study2 ),
                                        std_info = c( 0, 0 ),
                                        S_YY = list( S_YY_study1, S_YY_study2 ),
                                        N = c( N1, N2 ),
                                        analysis_type = 2,
                                        SNP_id = rownames(S_XX_study1),
                                        S_XX = list( S_XX_study1, S_XX_study2 ))
        
        # -----------------------------------------------------------------------------
        # 4. Save Results
        # -----------------------------------------------------------------------------
        
        # Save results as CSV tables
        write.csv(metaCCA_res3, file = "metaCCA_results.csv", row.names = TRUE)
        write.csv(metaCCApl_res3, file = "metaCCAplus_results.csv", row.names = TRUE)
        
        # Save results as RDS objects
        saveRDS(metaCCA_res3, file = "metaCCA_results.rds")
        saveRDS(metaCCApl_res3, file = "metaCCAplus_results.rds")

    writeLines(c(
        '"BIOC_METACCA_MULTI_SNP_MULTI_TRAIT_ANALYSIS":',
        paste0('    metaCCA: ', as.character(packageVersion('metaCCA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_snp_multi_trait_analysis.csv versions.yml
    """
}

workflow BIOC_METACCA_MULTI_SNP_MULTI_TRAIT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ S_XY_full_study1, S_XY_full_study2, S_XY_study1, S_XY_study2, S_XX_study1, S_XX_study2 ] ]

    main:
    BIOC_METACCA_MULTI_SNP_MULTI_TRAIT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METACCA_MULTI_SNP_MULTI_TRAIT_ANALYSIS.out.tables
    plots    = BIOC_METACCA_MULTI_SNP_MULTI_TRAIT_ANALYSIS.out.plots
    objects  = BIOC_METACCA_MULTI_SNP_MULTI_TRAIT_ANALYSIS.out.objects
    versions = BIOC_METACCA_MULTI_SNP_MULTI_TRAIT_ANALYSIS.out.versions
}
