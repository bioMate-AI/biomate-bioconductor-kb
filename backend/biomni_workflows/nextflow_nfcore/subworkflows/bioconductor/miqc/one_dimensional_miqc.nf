#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miQC — one_dimensional_miqc
// Perform quality control filtering based solely on mitochondrial percentage using a 1D Gaussian mixture model to calculate a single threshold.
// Input: sce
// Container: quay.io/biocontainers/bioconductor-miqc:1.18.0--r45hdfd78af_0
// Requires: SingleCellExperiment, ggplot2, miQC, scater
// Visualizations: plot (ggplot/base)
// QC: per-cell QC metrics, cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify mitochondrial genes and calculate per-cell QC metrics using scater::addPerCellQC
//  * 2. [Core Analysis] Fit a 1D mixture model using mixtureModel with model_type = "one_dimensional"
//  * 3. [Visualization & Output] Visualize the model and filtering using plotModel and plotFiltering
//  * 4. [Core Analysis] Calculate the single mitochondrial percentage cutoff using get1DCutoff

nextflow.enable.dsl = 2

process BIOC_MIQC_ONE_DIMENSIONAL_MIQC {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    suppressPackageStartupMessages({
        library(SingleCellExperiment)
        library(scater)
        library(miQC)
        library(ggplot2)
    })
    
    # 1. Read User Input
    message("Reading input SingleCellExperiment object...")
    if (file.exists("sce")) {
        sce <- readRDS("sce")
    } else if (file.exists("sce.rds")) {
        sce <- readRDS("sce.rds")
    } else {
        stop("Error: Input file 'sce' or 'sce.rds' not found in the working directory.")
    }
    
    # 2. Identify mitochondrial genes and calculate per-cell QC metrics
    message("Identifying mitochondrial genes and calculating QC metrics...")
    mt_genes <- grepl("^mt-",  rownames(sce))
    # Fallback to human mitochondrial prefix if no mouse mitochondrial genes are found
    if (sum(mt_genes) == 0) {
        mt_genes <- grepl("^MT-", rownames(sce))
    }
    feature_ctrls <- list(mito = rownames(sce)[mt_genes])
    sce <- addPerCellQC(sce, subsets = feature_ctrls)
    
    # 3. Fit a 1D mixture model
    message("Fitting 1D mixture model...")
    model4 <- mixtureModel(sce, model_type = "one_dimensional")
    
    # Save the fitted model object
    saveRDS(model4, "model4.rds")
    
    # 4. Visualize the model and filtering
    message("Generating diagnostic plots...")
    pdf("miqc_1d_plots.pdf", width = 7, height = 5)
    print(plotModel(sce, model4))
    print(plotFiltering(sce, model4))
    dev.off()
    
    # 5. Calculate the single mitochondrial percentage cutoff
    message("Calculating 1D mitochondrial cutoff...")
    cutoff <- get1DCutoff(sce, model4)
    
    # Write the cutoff value to output files
    writeLines(as.character(cutoff), "cutoff_1d.txt")
    write.csv(data.frame(mitochondrial_cutoff_percent = cutoff), "cutoff_1d.csv", row.names = FALSE)
    
    # Save the updated SingleCellExperiment object containing the QC metrics
    saveRDS(sce, "sce_processed.rds")
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MIQC_ONE_DIMENSIONAL_MIQC":',
        paste0('    miQC: ', as.character(packageVersion('miQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_dimensional_miqc.csv versions.yml
    """
}

workflow BIOC_MIQC_ONE_DIMENSIONAL_MIQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce ] ]

    main:
    BIOC_MIQC_ONE_DIMENSIONAL_MIQC(ch_input)

    emit:
    tables   = BIOC_MIQC_ONE_DIMENSIONAL_MIQC.out.tables
    plots    = BIOC_MIQC_ONE_DIMENSIONAL_MIQC.out.plots
    objects  = BIOC_MIQC_ONE_DIMENSIONAL_MIQC.out.objects
    versions = BIOC_MIQC_ONE_DIMENSIONAL_MIQC.out.versions
}
