#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeoTcgaData — dna_methylation_differential_analysis
// Identify differentially methylated genes from CpG methylation data.
// Input: cpgData, sampleGroup, cpg2gene
// Container: quay.io/biocontainers/bioconductor-geotcgadata:2.10.0--r45hdfd78af_0
// R packages: ChAMP, GeoTcgaData, S4Vectors, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: ChAMP, GeoTcgaData, S4Vectors, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare CpG methylation matrix, sample groups, and CpG-to-gene mapping
//  * 2. [Core Analysis] Run differential_methy to identify differentially methylated genes

nextflow.enable.dsl = 2

process BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("ChAMP", "GeoTcgaData", "S4Vectors", "SummarizedExperiment")
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
    library(GeoTcgaData)
    library(SummarizedExperiment)
    library(ChAMP)
    library(S4Vectors)
    
    # 1. Prepare CpG methylation matrix, sample groups, and CpG-to-gene mapping
    # Read inputs from the working directory
    
    # Load cpgData (can be a matrix or a SummarizedExperiment)
    if (file.exists("cpgData.rds")) {
      cpgData <- readRDS("cpgData.rds")
    } else if (file.exists("cpgData.csv")) {
      cpgData <- as.matrix(read.csv("cpgData.csv", row.names = 1, check.names = FALSE))
    } else {
      stop("Error: cpgData file not found. Please provide 'cpgData.rds' or 'cpgData.csv' in the working directory.")
    }
    
    # Load sampleGroup (vector of sample group assignments)
    if (file.exists("sampleGroup.rds")) {
      sampleGroup <- readRDS("sampleGroup.rds")
    } else if (file.exists("sampleGroup.csv")) {
      sg_df <- read.csv("sampleGroup.csv", header = TRUE)
      if (ncol(sg_df) >= 2) {
        sampleGroup <- sg_df[[2]]
        names(sampleGroup) <- sg_df[[1]]
      } else {
        sampleGroup <- sg_df[[1]]
        if (!is.null(rownames(sg_df)) && !all(rownames(sg_df) == as.character(seq_len(nrow(sg_df))))) {
          names(sampleGroup) <- rownames(sg_df)
        }
      }
    } else {
      stop("Error: sampleGroup file not found. Please provide 'sampleGroup.rds' or 'sampleGroup.csv' in the working directory.")
    }
    
    # Load cpg2gene (data frame mapping CpG probe IDs to gene symbols)
    if (file.exists("cpg2gene.rds")) {
      cpg2gene <- readRDS("cpg2gene.rds")
    } else if (file.exists("cpg2gene.csv")) {
      cpg2gene <- read.csv("cpg2gene.csv", header = TRUE)
    } else {
      stop("Error: cpg2gene file not found. Please provide 'cpg2gene.rds' or 'cpg2gene.csv' in the working directory.")
    }
    
    # 2. Run differential_methy to identify differentially methylated genes
    if (inherits(cpgData, "SummarizedExperiment")) {
      # Align sampleGroup with SummarizedExperiment colData if names are available
      if (!is.null(names(sampleGroup))) {
        common_samples <- intersect(colnames(cpgData), names(sampleGroup))
        if (length(common_samples) > 0) {
          cpgData <- cpgData[, common_samples]
          sampleGroup <- sampleGroup[common_samples]
        }
      }
      
      # Ensure the group column is present in colData
      SummarizedExperiment::colData(cpgData)\$group <- sampleGroup
      
      # Run using SummarizedExperiment input
      result <- differential_methy(cpgData = cpgData, 
                                   groupCol = "group", 
                                   normMethod = NULL, 
                                   cpg2gene = cpg2gene)
    } else {
      # Align sampleGroup with matrix columns if names are available
      if (!is.null(names(sampleGroup))) {
        common_samples <- intersect(colnames(cpgData), names(sampleGroup))
        if (length(common_samples) > 0) {
          cpgData <- cpgData[, common_samples, drop = FALSE]
          sampleGroup <- sampleGroup[common_samples]
        }
      } else {
        if (length(sampleGroup) == ncol(cpgData)) {
          names(sampleGroup) <- colnames(cpgData)
        }
      }
      
      # Run using matrix input
      result <- differential_methy(cpgData, 
                                   sampleGroup, 
                                   cpg2gene = cpg2gene, 
                                   normMethod = NULL)
    }
    
    # 3. Write outputs
    saveRDS(result, "differential_methylation_results.rds")
    
    if (is.data.frame(result)) {
      write.csv(result, "differential_methylation_results.csv", row.names = TRUE)
    } else if (is.list(result)) {
      for (name in names(result)) {
        if (is.data.frame(result[[name]]) || is.matrix(result[[name]])) {
          write.csv(result[[name]], paste0("differential_methylation_results_", name, ".csv"), row.names = TRUE)
        }
      }
    }

    writeLines(c(
        '"BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS":',
        paste0('    GeoTcgaData: ', as.character(packageVersion('GeoTcgaData')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dna_methylation_differential_analysis.csv versions.yml
    """
}

workflow BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cpgData, sampleGroup, cpg2gene ] ]

    main:
    BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS.out.objects
    versions = BIOC_GEOTCGADATA_DNA_METHYLATION_DIFFERENTIAL_ANALYSIS.out.versions
}
