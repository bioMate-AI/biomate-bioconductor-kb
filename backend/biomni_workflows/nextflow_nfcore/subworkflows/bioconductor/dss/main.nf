#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DSS — rnaseq_twogroup_de
// Perform differential expression analysis on RNA-seq count data for a simple two-group comparison.
// Input: counts.txt, designs.txt
// Container: quay.io/biocontainers/bioconductor-dss:2.58.0--r45h01b2380_0
// R packages: bsseq, DSS, edgeR
// Bioconductor: 3.20 | R: 4.4
// Requires: DSS
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a SeqCountSet object using newSeqCountSet
//  * 2. [Core Analysis] Estimate normalization factors using estNormFactors
//  * 3. [Core Analysis] Estimate and shrink gene-wise dispersions using estDispersion
//  * 4. [Core Analysis] Perform two-group comparison Wald test using waldTest (or perform the entire workflow in one step using the high-level wrapper DSS

nextflow.enable.dsl = 2

process BIOC_DSS_RNASEQ_TWOGROUP_DE {
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
    .bm_deps <- c("bsseq", "DSS", "edgeR")
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
    library(DSS)
    
    # 1. Read User Inputs
    if (!file.exists("counts.txt")) {
      stop("Error: counts.txt not found in the working directory.")
    }
    if (!file.exists("designs.txt")) {
      stop("Error: designs.txt not found in the working directory.")
    }
    
    # Read counts matrix (rows = genes, columns = samples)
    counts_df <- read.table("counts.txt", header=TRUE, row.names=1, check.names=FALSE)
    X <- as.matrix(counts_df)
    counts <- X
    
    # Read designs vector (0s and 1s representing experimental groups)
    designs_df <- read.table("designs.txt", header=FALSE)
    designs <- as.numeric(as.vector(unlist(designs_df)))
    
    # 2. Step-by-step approach
    seqData = newSeqCountSet(X, designs)
    seqData = estNormFactors(seqData)
    seqData = estDispersion(seqData)
    result = waldTest(seqData, 0, 1)
    
    # Save step-by-step results
    write.csv(result, "result_step_by_step.csv", row.names=FALSE)
    saveRDS(seqData, "seqData.rds")
    
    # 3. High-level wrapper approach
    result = DSS.DE(counts, designs)
    
    # Save wrapper results
    write.csv(result, "result_wrapper.csv", row.names=FALSE)
    
    cat("DSS RNA-seq differential expression analysis completed successfully.\n")

    writeLines(c(
        '"BIOC_DSS_RNASEQ_TWOGROUP_DE":',
        paste0('    DSS: ', as.character(packageVersion('DSS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaseq_twogroup_de.csv versions.yml
    """
}

workflow BIOC_DSS_RNASEQ_TWOGROUP_DE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ counts.txt, designs.txt ] ]

    main:
    BIOC_DSS_RNASEQ_TWOGROUP_DE(ch_input)

    emit:
    tables   = BIOC_DSS_RNASEQ_TWOGROUP_DE.out.tables
    plots    = BIOC_DSS_RNASEQ_TWOGROUP_DE.out.plots
    objects  = BIOC_DSS_RNASEQ_TWOGROUP_DE.out.objects
    versions = BIOC_DSS_RNASEQ_TWOGROUP_DE.out.versions
}
