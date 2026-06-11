#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioQC — tissue_heterogeneity_detection
// Detect tissue heterogeneity and contamination in gene expression data using tissue-specific gene signatures.
// Input: kidney_example.rda, exp.tissuemark.affy.roche.symbols.gmt
// Container: quay.io/biocontainers/bioconductor-bioqc:1.38.0--r45ha27e39d_0
// R packages: Biobase, BioQC, gplots, gridExtra, lattice, RColorBrewer
// Bioconductor: 3.20 | R: 4.4
// Requires: BioQC, Biobase
// Visualizations: heatmap (ComplexHeatmap), heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load tissue-specific gene signatures from a GMT file using readGmt
//  * 2. [Input & Preparation] Load the gene expression dataset
//  * 3. [Core Analysis] Perform the Wilcoxon-Mann-Whitney test using wmwTest to calculate enrichment p-values
//  * 4. [Core Analysis] Filter the resulting p-value matrix using filterPmat
//  * 5. [Visualization & Output] Transform the filtered p-values to BioQC scores using absLog10p for downstream visualization

nextflow.enable.dsl = 2

process BIOC_BIOQC_TISSUE_HETEROGENEITY_DETECTION {
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
    .bm_deps <- c("Biobase", "BioQC", "gplots", "gridExtra", "lattice", "RColorBrewer")
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
    library(BioQC)
    library(Biobase)
    
    # 1. Load tissue-specific gene signatures from the local GMT file
    gmtFile <- "exp.tissuemark.affy.roche.symbols.gmt"
    gmt <- readGmt(gmtFile)
    
    # 2. Load the gene expression dataset from the local RDA file
    file <- "kidney_example.rda"
    load(file) # This loads the 'eset' object into the environment
    
    # 3. Perform the Wilcoxon-Mann-Whitney test using wmwTest to calculate enrichment p-values
    bioqcRes <- wmwTest(eset, gmt, valType="p.greater")
    
    # 4. Filter the resulting p-value matrix using filterPmat
    bioqcResFil <- filterPmat(bioqcRes, 1E-6)
    
    # 5. Transform the filtered p-values to BioQC scores using absLog10p
    bioqcAbsLogRes <- absLog10p(bioqcResFil)
    
    # 6. Write named output files for the results
    # Save RDS objects for downstream R analysis
    saveRDS(bioqcRes, "bioqc_raw_pvalues.rds")
    saveRDS(bioqcAbsLogRes, "bioqc_scores.rds")
    
    # Save CSV tables for easy inspection
    write.csv(as.matrix(bioqcRes), "bioqc_raw_pvalues.csv", row.names=TRUE)
    write.csv(as.matrix(bioqcAbsLogRes), "bioqc_scores.csv", row.names=TRUE)
    
    # Generate a PDF heatmap of the BioQC scores
    pdf("bioqc_scores_heatmap.pdf", width=10, height=8)
    if (nrow(bioqcAbsLogRes) > 0 && ncol(bioqcAbsLogRes) > 0) {
      heatmap(bioqcAbsLogRes, 
              Colv=NA, 
              Rowv=TRUE, 
              cexRow=0.85, 
              scale="row", 
              main="BioQC Scores Heatmap (absLog10p)")
    } else {
      plot.new()
      text(0.5, 0.5, "No signatures passed the filtering threshold (1E-6)")
    }
    dev.off()

    writeLines(c(
        '"BIOC_BIOQC_TISSUE_HETEROGENEITY_DETECTION":',
        paste0('    BioQC: ', as.character(packageVersion('BioQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tissue_heterogeneity_detection.csv versions.yml
    """
}

workflow BIOC_BIOQC_TISSUE_HETEROGENEITY_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kidney_example.rda, exp.tissuemark.affy.roche.symbols.gmt ] ]

    main:
    BIOC_BIOQC_TISSUE_HETEROGENEITY_DETECTION(ch_input)

    emit:
    tables   = BIOC_BIOQC_TISSUE_HETEROGENEITY_DETECTION.out.tables
    plots    = BIOC_BIOQC_TISSUE_HETEROGENEITY_DETECTION.out.plots
    objects  = BIOC_BIOQC_TISSUE_HETEROGENEITY_DETECTION.out.objects
    versions = BIOC_BIOQC_TISSUE_HETEROGENEITY_DETECTION.out.versions
}
