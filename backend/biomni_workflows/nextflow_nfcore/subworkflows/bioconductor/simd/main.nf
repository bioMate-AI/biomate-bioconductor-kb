#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SIMD — simd_differential_methylation_analysis
// Jointly analyze MeDIP-seq and MRE-seq data to calculate CpG site-specific p-values and identify differentially methylated regions.
// Input: H1ESB1_MeDIP_18.extended.txt, example_data.RData
// Container: quay.io/biocontainers/bioconductor-simd:1.28.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SIMD
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run EMalgorithm to infer actual short reads from observed fragments for each sample
//  * 2. [Core Analysis] Combine the inferred MeDIP-seq and MRE-seq counts for control and treatment samples
//  * 3. [Core Analysis] Run EMtest to calculate p-values for each CpG site

nextflow.enable.dsl = 2

process BIOC_SIMD_SIMD_DIFFERENTIAL_METHYLATION_ANALYSIS {
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
    .bm_deps <- c("SIMD")
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
    library(SIMD)
    
    # Load the pre-processed CpG and MRE site files from the user-provided RData file
    load("example_data.RData")
    
    # Define input and output paths for EMalgorithm
    allcpgfile <- EM_H1ESB1_MeDIP_sigleCpG
    readshort <- "H1ESB1_MeDIP_18.extended.txt"
    writefile <- "EM2_H1ESB1_MeDIP_sigleCpG.bed"
    reportfile <- "EM2_H1ESB1_MeDIP_sigleCpG_report.bed"
    
    # Run EMalgorithm to infer actual short reads from observed fragments
    EMalgorithm(cpgsitefile=readshort, allcpgfile=allcpgfile, category="1",
                writefile=writefile, reportfile=reportfile)
    
    # Read the inferred MeDIP-seq counts for the first sample
    data1 <- read.table(writefile, header=FALSE)
    
    # Retrieve the other samples and control/treatment data from the loaded workspace
    data2 <- EM2_H1ESB2_MeDIP_sigleCpG
    data3 <- H1ESB1_MRE_sigleCpG
    data4 <- H1ESB2_MRE_sigleCpG
    
    # Combine the MeDIP-seq and MRE-seq counts (extracting only the 4th column containing the counts)
    datafile <- cbind(data1[, 4], data2[, 4], data3[, 4], data4[, 4])
    allcpg <- all_CpGsite_bin_chr18
    mrecpg <- three_mre_cpg
    
    # Define output paths for EMtest
    writefile <- "pval_EM_H1ESB1_H1ESB21.bed"
    reportfile <- "report_pvalH1ESB1_H1ESB21.bed"
    
    # Run EMtest to calculate p-values for each CpG site
    EMtest(datafile=datafile, chrstring=NULL, cpgfile=allcpg, mrecpgfile=mrecpg, 
           writefile=writefile, reportfile=reportfile, mreratio=3/7, psd=2, 
           mkadded=1, f=1)
    
    # Save meaningful results to CSV and RDS formats
    pval_results <- read.table(writefile, header=FALSE)
    colnames(pval_results) <- c("chr", "start", "end", "p_value")
    write.csv(pval_results, "pval_results.csv", row.names=FALSE)
    saveRDS(pval_results, "pval_results.rds")

    writeLines(c(
        '"BIOC_SIMD_SIMD_DIFFERENTIAL_METHYLATION_ANALYSIS":',
        paste0('    SIMD: ', as.character(packageVersion('SIMD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simd_differential_methylation_analysis.csv versions.yml
    """
}

workflow BIOC_SIMD_SIMD_DIFFERENTIAL_METHYLATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ H1ESB1_MeDIP_18.extended.txt, example_data.RData ] ]

    main:
    BIOC_SIMD_SIMD_DIFFERENTIAL_METHYLATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SIMD_SIMD_DIFFERENTIAL_METHYLATION_ANALYSIS.out.tables
    plots    = BIOC_SIMD_SIMD_DIFFERENTIAL_METHYLATION_ANALYSIS.out.plots
    objects  = BIOC_SIMD_SIMD_DIFFERENTIAL_METHYLATION_ANALYSIS.out.objects
    versions = BIOC_SIMD_SIMD_DIFFERENTIAL_METHYLATION_ANALYSIS.out.versions
}
