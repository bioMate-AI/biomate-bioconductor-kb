#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaphor — single_deg_metabolic_profiling
// Assess metabolic dysregulation from a single DEG list and visualize the profile using a bubble plot.
// Input: BRCA_DEGS.csv
// Container: quay.io/biocontainers/bioconductor-metaphor:1.12.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METAPHOR_SINGLE_DEG_METABOLIC_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-metaphor:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("kableextra", "metaphor")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(MetaPhOR)
    
    # Verify input file existence
    input_file <- "BRCA_DEGS.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "is missing from the working directory."))
    }
    
    # 1. Set seed for reproducible bootstrapping
    set.seed(1234)
    
    # 2. Run pathway analysis using pathwayAnalysis()
    brca <- pathwayAnalysis(DEGpath = input_file,
                            genename = "X",
                            sampsize = 1095,
                            iters = 50000,
                            headers = c("logFC", "adj.P.Val"))
    
    # Save the pathway analysis scores to CSV and RDS
    write.csv(brca, "BRCA_pathway_analysis_scores.csv", row.names = TRUE)
    saveRDS(brca, "BRCA_pathway_analysis_scores.rds")
    
    # 3. Visualize the metabolic profile using bubblePlot() and 4. Plot the bubble plot using plot()
    # Bubble Plot Labeled by P Value
    pval <- bubblePlot(scorelist = brca,
                        labeltext = "Pval",
                        labelsize = .85)
    
    pdf("BRCA_bubblePlot_Pval.pdf", width = 10, height = 8)
    plot(pval)
    dev.off()
    
    # Bubble Plot Labeled by LogFC
    logfc <- bubblePlot(scorelist = brca,
                        labeltext = "LogFC",
                        labelsize = .85)
    
    pdf("BRCA_bubblePlot_LogFC.pdf", width = 10, height = 8)
    plot(logfc)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_METAPHOR_SINGLE_DEG_METABOLIC_PROFILING":
        metaphor: \$(Rscript -e 'cat(as.character(packageVersion("metaphor")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_deg_metabolic_profiling.csv versions.yml
    """
}

workflow BIOC_METAPHOR_SINGLE_DEG_METABOLIC_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BRCA_DEGS.csv ] ]

    main:
    BIOC_METAPHOR_SINGLE_DEG_METABOLIC_PROFILING(ch_input)

    emit:
    tables   = BIOC_METAPHOR_SINGLE_DEG_METABOLIC_PROFILING.out.tables
    plots    = BIOC_METAPHOR_SINGLE_DEG_METABOLIC_PROFILING.out.plots
    objects  = BIOC_METAPHOR_SINGLE_DEG_METABOLIC_PROFILING.out.objects
    versions = BIOC_METAPHOR_SINGLE_DEG_METABOLIC_PROFILING.out.versions
}
