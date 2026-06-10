#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normalyzerde — differential_expression
// Perform differential expression analysis (Limma/ANOVA) on a selected normalized matrix.
// Input: CycLoess-normalized.txt, tiny_design.tsv
// Container: quay.io/biocontainers/bioconductor-normalyzerde:1.28.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMALYZERDE_DIFFERENTIAL_EXPRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-normalyzerde:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("NormalyzerDE")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(NormalyzerDE)
    
    # Define input file paths (must exist in the working directory)
    designFp <- "tiny_design.tsv"
    normMatrixPath <- "CycLoess-normalized.txt"
    bestNormMatPath <- "CycLoess-normalized.txt"
    
    # Verify input files exist
    if (!file.exists(designFp)) {
        stop(paste("Required input file missing:", designFp))
    }
    if (!file.exists(normMatrixPath)) {
        stop(paste("Required input file missing:", normMatrixPath))
    }
    
    # Create output directories
    outDir <- "output_normalyzerDE"
    if (!dir.exists(outDir)) {
        dir.create(outDir, recursive = TRUE)
    }
    
    jobDir <- "output_stepwise"
    if (!dir.exists(jobDir)) {
        dir.create(jobDir, recursive = TRUE)
    }
    
    # 1. Run differential expression analysis using normalyzerDE
    message("Running normalyzerDE...")
    normalyzerDE("vignette_run", 
                 comparisons=c("4-5"),
                 designPath=designFp, 
                 dataPath=normMatrixPath,
                 outputDir=outDir, 
                 condCol="group")
    
    # 2. Stepwise processing: Setup contrast object and statistics object
    message("Setting up contrast and statistics objects...")
    experimentObj <- setupRawContrastObject(bestNormMatPath, designFp, "sample")
    nst <- NormalyzerStatistics(experimentObj, logTrans=FALSE)
    
    # 3. Calculate statistical contrasts
    message("Calculating contrasts...")
    comparisons <- c("4-5")
    nst <- calculateContrasts(nst, comparisons, condCol="group", leastRepCount=2)
    
    # 4. Generate annotated matrix and write outputs
    message("Generating annotated matrix and reports...")
    annotDf <- generateAnnotatedMatrix(nst)
    
    # Write statistics table (exact documented call)
    utils::write.table(annotDf, file=paste(jobDir, "stat_table.tsv", sep="/"))
    
    # Additional outputs for robust pipeline results
    write.csv(annotDf, file=paste(jobDir, "stat_table.csv", sep="/"), row.names=FALSE)
    saveRDS(nst, file=paste(jobDir, "normalyzer_stats_object.rds", sep="/"))
    
    # Generate stats report (exact documented call)
    generateStatsReport(nst, "Vignette stats", jobDir)
    
    message("Pipeline completed successfully!")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NORMALYZERDE_DIFFERENTIAL_EXPRESSION":
        normalyzerde: \$(Rscript -e 'cat(as.character(packageVersion("normalyzerde")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_expression.csv versions.yml
    """
}

workflow BIOC_NORMALYZERDE_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CycLoess-normalized.txt, tiny_design.tsv ] ]

    main:
    BIOC_NORMALYZERDE_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_NORMALYZERDE_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_NORMALYZERDE_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_NORMALYZERDE_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_NORMALYZERDE_DIFFERENTIAL_EXPRESSION.out.versions
}
