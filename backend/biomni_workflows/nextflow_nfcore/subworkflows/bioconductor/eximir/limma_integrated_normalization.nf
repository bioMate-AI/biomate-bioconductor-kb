#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: eximir — limma_integrated_normalization
// Read raw data using limma, convert to an AffyBatch object, and normalize with ExiMiR using a custom spike-in probe list.
// Input: Raw data files, GAL file, Targets.txt
// Container: quay.io/biocontainers/bioconductor-eximir:2.52.0--r45hdfd78af_0
// R packages: ExiMiR, limma
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EXIMIR_LIMMA_INTEGRATED_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-eximir:2.52.0--r45hdfd78af_0"

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
    library(limma)
    library(ExiMiR)
    
    # 1. Read targets and raw images using limma's readTargets and read.maimages
    # Reads Targets.txt from the working directory
    targets <- readTargets(path='.')
    
    # Reads the raw data files specified in the targets file from the working directory
    RGList <- read.maimages(targets[,c('Cy3','Cy5')], source='imagene', path='.')
    
    # 2. Read GAL annotation and layout using readGAL and getLayout
    # Reads the GAL file from the working directory
    RGList\$genes <- readGAL(path='.')
    RGList\$printer <- getLayout(RGList\$genes)
    
    # 3. Convert the RGList to an AffyBatch object using createAB
    obatch <- createAB(RGList)
    
    # 4. Define custom spike-in probes and run NormiR normalization
    spikein.all <- grep('^spike', featureNames(obatch), value=TRUE)
    spikein.subset <- setdiff(spikein.all, 'spike_control_f')
    
    # Run NormiR normalization using the custom spike-in probe list
    eset.spike <- NormiR(obatch, bg.correct=FALSE,
                                   normalize.method='spikein',
                                   normalize.param=list(probeset.list=spikein.subset),
                                   summary.method='medianpolish')
    
    # Write named output files for the meaningful results
    write.csv(exprs(eset.spike), file='normalized_expression.csv', row.names=TRUE)
    saveRDS(eset.spike, file='eset_spike.rds')
    
    cat("Pipeline completed successfully. Outputs saved to 'normalized_expression.csv' and 'eset_spike.rds'.\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_EXIMIR_LIMMA_INTEGRATED_NORMALIZATION":
        eximir: \$(Rscript -e 'cat(as.character(packageVersion("eximir")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_limma_integrated_normalization.csv versions.yml
    """
}

workflow BIOC_EXIMIR_LIMMA_INTEGRATED_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Raw data files, GAL file, Targets.txt ] ]

    main:
    BIOC_EXIMIR_LIMMA_INTEGRATED_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_EXIMIR_LIMMA_INTEGRATED_NORMALIZATION.out.tables
    plots    = BIOC_EXIMIR_LIMMA_INTEGRATED_NORMALIZATION.out.plots
    objects  = BIOC_EXIMIR_LIMMA_INTEGRATED_NORMALIZATION.out.objects
    versions = BIOC_EXIMIR_LIMMA_INTEGRATED_NORMALIZATION.out.versions
}
