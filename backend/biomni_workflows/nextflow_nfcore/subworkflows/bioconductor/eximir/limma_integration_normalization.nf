#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ExiMiR — limma_integration_normalization
// Read custom two-color microarray formats using limma, convert to AffyBatch, and normalize using ExiMiR's spike-in method.
// Input: Exiqon/Targets.txt, Exiqon/*.txt, Exiqon/*.gal
// Container: quay.io/biocontainers/bioconductor-eximir:2.52.0--r45hdfd78af_0
// Requires: ExiMiR, limma
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read targets and raw images using limma
//  * 2. [Input & Preparation] Read GAL annotation
//  * 3. [Core Analysis] Convert RGList to AffyBatch using createAB
//  * 4. [Input & Preparation] Define spike-in probe subset
//  * 5. [Visualization & Output] Normalize and summarize using NormiR

nextflow.enable.dsl = 2

process BIOC_EXIMIR_LIMMA_INTEGRATION_NORMALIZATION {
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
    .bm_deps <- c("ExiMiR", "limma")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(limma)
    library(ExiMiR)
    
    # Verify input directory and files exist
    if (!dir.exists("Exiqon")) {
      stop("Error: 'Exiqon' directory not found in the current working directory.")
    }
    if (!file.exists(file.path("Exiqon", "Targets.txt"))) {
      stop("Error: 'Exiqon/Targets.txt' targets file not found.")
    }
    
    # 1. Read targets and raw images using limma
    targets <- readTargets(path='Exiqon')
    RGList <- read.maimages(targets[,c('Cy3','Cy5')], source='imagene', path='Exiqon')
    
    # 2. Read GAL annotation
    RGList\$genes <- readGAL(path='Exiqon')
    RGList\$printer <- getLayout(RGList\$genes)
    
    # 3. Convert RGList to AffyBatch using createAB
    obatch <- createAB(RGList)
    
    # 4. Define spike-in probe subset
    spikein.all <- grep('^spike', featureNames(obatch), value=TRUE)
    spikein.subset <- setdiff(spikein.all, 'spike_control_f')
    
    # 5. Normalize and summarize using NormiR
    eset.spike <- NormiR(obatch, bg.correct=FALSE,
                                normalize.method='spikein',
                                normalize.param=list(probeset.list=spikein.subset),
                                summary.method='medianpolish')
    
    # Write outputs
    # Save the ExpressionSet object
    saveRDS(eset.spike, file = "eset_spike.rds")
    
    # Save the expression matrix as CSV
    write.csv(exprs(eset.spike), file = "normalized_expression.csv", row.names = TRUE)
    
    # Generate and save QC plots
    pdf("normalization_qc_plots.pdf", width = 10, height = 6)
    par(mfrow = c(1, 2))
    # Raw intensities boxplot (from obatch)
    boxplot(log2(exprs(obatch) + 1), main = "Raw Intensities (log2)", las = 2, cex.axis = 0.7)
    # Normalized intensities boxplot
    boxplot(exprs(eset.spike), main = "Normalized Expression", las = 2, cex.axis = 0.7)
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to 'eset_spike.rds', 'normalized_expression.csv', and 'normalization_qc_plots.pdf'.\n")

    writeLines(c(
        '"BIOC_EXIMIR_LIMMA_INTEGRATION_NORMALIZATION":',
        paste0('    ExiMiR: ', as.character(packageVersion('ExiMiR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_limma_integration_normalization.csv versions.yml
    """
}

workflow BIOC_EXIMIR_LIMMA_INTEGRATION_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Exiqon/Targets.txt, Exiqon/*.txt, Exiqon/*.gal ] ]

    main:
    BIOC_EXIMIR_LIMMA_INTEGRATION_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_EXIMIR_LIMMA_INTEGRATION_NORMALIZATION.out.tables
    plots    = BIOC_EXIMIR_LIMMA_INTEGRATION_NORMALIZATION.out.plots
    objects  = BIOC_EXIMIR_LIMMA_INTEGRATION_NORMALIZATION.out.objects
    versions = BIOC_EXIMIR_LIMMA_INTEGRATION_NORMALIZATION.out.versions
}
