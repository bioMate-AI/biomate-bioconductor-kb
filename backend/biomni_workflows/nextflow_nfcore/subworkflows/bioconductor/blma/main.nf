#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BLMA — gene_level_differential_expression
// Perform intra-experiment and bi-level gene-level differential expression analysis across multiple datasets.
// Input: data_GSE33223, group_GSE33223, dataList, groupList
// Container: quay.io/biocontainers/bioconductor-blma:1.34.0--r45hdfd78af_0
// R packages: BLMA, ROntoTools
// Bioconductor: 3.20 | R: 4.4
// Requires: BLMA
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform intra-experiment analysis on a single dataset using intraAnalysisGene with default addCLT or fisherMethod
//  * 2. [Core Analysis] Perform bi-level meta-analysis across multiple datasets using bilevelAnalysisGene

nextflow.enable.dsl = 2

process BIOC_BLMA_GENE_LEVEL_DIFFERENTIAL_EXPRESSION {
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
    .bm_deps <- c("BLMA", "ROntoTools")
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
    library(BLMA)
    
    # 1. Load input datasets from the working directory
    # The pipeline expects 'dataList.rds' and 'groupList.rds' to be present in the working directory.
    if (file.exists("dataList.rds") && file.exists("groupList.rds")) {
      dataList <- readRDS("dataList.rds")
      groupList <- readRDS("groupList.rds")
    } else if (file.exists("dataList.RData") && file.exists("groupList.RData")) {
      load("dataList.RData")
      load("groupList.RData")
    } else {
      stop("Required input files (dataList.rds/RData and groupList.rds/RData) not found in the working directory.")
    }
    
    if (file.exists("data_GSE33223.rds") && file.exists("group_GSE33223.rds")) {
      data_GSE33223 <- readRDS("data_GSE33223.rds")
      group_GSE33223 <- readRDS("group_GSE33223.rds")
    } else if (file.exists("data_GSE33223.RData") && file.exists("group_GSE33223.RData")) {
      load("data_GSE33223.RData")
      load("group_GSE33223.RData")
    } else {
      stop("Required input files (data_GSE33223.rds/RData and group_GSE33223.rds/RData) not found in the working directory.")
    }
    
    # 2. Stage 1: intra-experiment analysis using 'intraAnalysisGene'
    message("Running intra-experiment analysis...")
    intraRes <- NULL
    tryCatch({
      system.time(intraRes <- intraAnalysisGene(data_GSE33223, group_GSE33223))
      intraRes <- intraRes[order(intraRes\$pIntra), ]
      options(digits=2)
      print(head(intraRes))
      
      # Save intra-experiment results
      write.csv(intraRes, "intraAnalysisGene_results.csv", row.names = TRUE)
      saveRDS(intraRes, "intraAnalysisGene_results.rds")
    }, error = function(e) {
      message("Error during intra-experiment analysis: ", e\$message)
    })
    
    # 3. Stage 2: bi-level meta-analysis using 'bilevelAnalysisGene'
    message("Running bi-level meta-analysis...")
    bilevelRes <- NULL
    tryCatch({
      system.time(bilevelRes <- bilevelAnalysisGene(dataList = dataList, groupList = groupList))
      options(digits=2)
      print(head(bilevelRes))
      
      # Save bi-level meta-analysis results
      write.csv(bilevelRes, "bilevelAnalysisGene_results.csv", row.names = TRUE)
      saveRDS(bilevelRes, "bilevelAnalysisGene_results.rds")
    }, error = function(e) {
      message("Error during bi-level meta-analysis: ", e\$message)
    })
    
    message("Pipeline execution completed.")

    writeLines(c(
        '"BIOC_BLMA_GENE_LEVEL_DIFFERENTIAL_EXPRESSION":',
        paste0('    BLMA: ', as.character(packageVersion('BLMA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_level_differential_expression.csv versions.yml
    """
}

workflow BIOC_BLMA_GENE_LEVEL_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data_GSE33223, group_GSE33223, dataList, groupList ] ]

    main:
    BIOC_BLMA_GENE_LEVEL_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_BLMA_GENE_LEVEL_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_BLMA_GENE_LEVEL_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_BLMA_GENE_LEVEL_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_BLMA_GENE_LEVEL_DIFFERENTIAL_EXPRESSION.out.versions
}
