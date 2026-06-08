#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDblFinder — compute_doublet_density
// Score potential doublets based on the local density of simulated doublets in PCA space.
// Input: sce.rds
// Container: quay.io/biocontainers/bioconductor-scdblfinder:1.24.0--r45hdfd78af_0
// Requires: SingleCellExperiment, scDblFinder, scater, scran, scuttle
// Visualizations: t-SNE plot, density plot
// QC: doublet detection QC, cell QC metrics, count normalization, highly-variable feature selection
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize counts and identify highly variable genes
//  * 2. [Core Analysis] Run PCA
//  * 3. [Core Analysis] Run computeDoubletDensity to calculate doublet scores

nextflow.enable.dsl = 2

process BIOC_SCDBLFINDER_COMPUTE_DOUBLET_DENSITY {
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
    library(SingleCellExperiment)
    library(scuttle)
    library(scran)
    library(scater)
    library(scDblFinder)
    
    # 1. Read user input
    if (!file.exists("sce.rds")) {
      stop("Error: Input file 'sce.rds' not found in the working directory.")
    }
    sce <- readRDS("sce.rds")
    
    # 2. Normalize counts and identify highly variable genes
    sce <- logNormCounts(sce)
    dec <- modelGeneVar(sce)
    hvgs <- getTopHVGs(dec, n=1000)
    
    # 3. Run PCA and t-SNE
    set.seed(1002)
    sce <- runPCA(sce, ncomponents=10, subset_row=hvgs)
    sce <- runTSNE(sce, dimred="PCA")
    
    # 4. Run computeDoubletDensity to calculate doublet scores
    set.seed(1003)
    scores <- computeDoubletDensity(sce, subset.row=hvgs)
    
    # 5. Save outputs
    # Save scores as CSV
    write.csv(data.frame(Cell = colnames(sce), DoubletScore = scores), 
              file = "doublet_scores.csv", row.names = FALSE)
    
    # Save updated SingleCellExperiment object
    sce\$doublet_score <- scores
    saveRDS(sce, file = "sce_with_scores.rds")
    
    # Save t-SNE plot as PDF
    pdf("doublet_density_tsne.pdf", width = 7, height = 6)
    p <- plotTSNE(sce, colour_by=I(log1p(scores)))
    print(p)
    dev.off()

    writeLines(c(
        '"BIOC_SCDBLFINDER_COMPUTE_DOUBLET_DENSITY":',
        paste0('    scDblFinder: ', as.character(packageVersion('scDblFinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compute_doublet_density.csv versions.yml
    """
}

workflow BIOC_SCDBLFINDER_COMPUTE_DOUBLET_DENSITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.rds ] ]

    main:
    BIOC_SCDBLFINDER_COMPUTE_DOUBLET_DENSITY(ch_input)

    emit:
    tables   = BIOC_SCDBLFINDER_COMPUTE_DOUBLET_DENSITY.out.tables
    plots    = BIOC_SCDBLFINDER_COMPUTE_DOUBLET_DENSITY.out.plots
    objects  = BIOC_SCDBLFINDER_COMPUTE_DOUBLET_DENSITY.out.objects
    versions = BIOC_SCDBLFINDER_COMPUTE_DOUBLET_DENSITY.out.versions
}
