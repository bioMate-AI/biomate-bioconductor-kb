#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CSSQ — differential_binding_from_bams
// Identify differentially bound regions step-by-step starting from raw BAM files and a BED file of regions of interest.
// Input: chr19_regions.bed, sample_info.txt, BAM files
// Container: quay.io/biocontainers/bioconductor-cssq:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CSSQ, GenomicRanges
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Quantify reads in regions of interest and perform background correction using getRegionCounts
//  * 2. [Core Analysis] Apply Anscombe transformation using ansTransform
//  * 3. [Core Analysis] Normalize transformed counts across samples using normalizeData
//  * 4. [Core Analysis] Perform non-parametric statistical testing for differential binding using DBAnalyze

nextflow.enable.dsl = 2

process BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_BAMS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("CSSQ", "GenomicRanges")
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
    library(CSSQ)
    library(GenomicRanges)
    
    # 1. Read user input files from the working directory
    sampleInfo <- read.table("sample_info.txt", sep="\t", header=TRUE)
    
    # 2. Quantify reads in regions of interest and perform background correction
    countData <- getRegionCounts("chr19_regions.bed", sampleInfo, sampleDir = ".")
    
    # 3. Apply Anscombe transformation
    ansCountData <- ansTransform(countData)
    
    # 4. Normalize transformed counts across samples
    normInfo <- normalizeData(ansCountData, numClusters=4)
    
    # 5. Perform non-parametric statistical testing for differential binding
    comp_groups <- unique(as.character(sampleInfo\$Group))
    result <- DBAnalyze(normInfo, comparison=comp_groups)
    
    # 6. Write outputs
    # Save the final GRanges result as an RDS object
    saveRDS(result, "differential_binding_results.rds")
    
    # Save the final results as a CSV table
    result_df <- as.data.frame(result)
    write.csv(result_df, "differential_binding_results.csv", row.names=FALSE)
    
    # Save intermediate normalized data
    saveRDS(normInfo, "normalized_info.rds")

    writeLines(c(
        '"BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_BAMS":',
        paste0('    CSSQ: ', as.character(packageVersion('CSSQ')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_binding_from_bams.csv versions.yml
    """
}

workflow BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_BAMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chr19_regions.bed, sample_info.txt, BAM files ] ]

    main:
    BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_BAMS(ch_input)

    emit:
    tables   = BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_BAMS.out.tables
    plots    = BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_BAMS.out.plots
    objects  = BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_BAMS.out.objects
    versions = BIOC_CSSQ_DIFFERENTIAL_BINDING_FROM_BAMS.out.versions
}
