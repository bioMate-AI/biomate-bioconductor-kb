#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EBSeq — gene_de_multi_conditions
// Identify gene expression patterns and group genes into distinct expression profiles across three or more biological conditions.
// Input: multi_condition_gene_counts.csv, multi_conditions.csv
// Container: quay.io/biocontainers/bioconductor-ebseq:2.8.0--r45ha27e39d_0
// Requires: EBSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate all possible expression patterns across conditions using GetPatterns. 2. Calculate sample normalization factors using Med

nextflow.enable.dsl = 2

process BIOC_EBSEQ_GENE_DE_MULTI_CONDITIONS {
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
        
        # Load required library
        library(EBSeq)
        
        # 1. Read User Input Files
        if (!file.exists("multi_condition_gene_counts.csv")) {
          stop("Error: 'multi_condition_gene_counts.csv' not found in the working directory.")
        }
        MultiGeneMat <- as.matrix(read.csv("multi_condition_gene_counts.csv", row.names = 1, check.names = FALSE))
        
        if (!file.exists("multi_conditions.csv")) {
          stop("Error: 'multi_conditions.csv' not found in the working directory.")
        }
        cond_data <- read.csv("multi_conditions.csv", stringsAsFactors = FALSE, header = TRUE)
        Conditions <- cond_data[[1]]
        
        # 2. Run the EBSeq Multi-Condition Workflow
        # Generate all possible expression patterns across conditions
        PosParti=GetPatterns(Conditions)
        
        # Calculate sample normalization factors
        MultiSize=MedianNorm(MultiGeneMat)
        
        # Run the multi-condition empirical Bayes test
        MultiOut=EBMultiTest(MultiGeneMat,NgVector=NULL,Conditions=Conditions, AllParti=PosParti, sizeFactors=MultiSize, maxround=5)
        
        # Extract posterior probabilities for each pattern and the MAP pattern
        MultiPP=GetMultiPP(MultiOut)
        
        # Calculate fold changes across conditions
        MultiFC=GetMultiFC(MultiOut)
        
        # 3. Perform diagnostics and save plots to PDF
        pdf("diagnostic_plots.pdf", width = 8, height = 8)
        par(mfrow=c(2,2))
        tryCatch({
          QQP(MultiOut)
        }, error = function(e) {
          warning("QQP plot generation failed: ", e\$message)
        })
        tryCatch({
          DenNHist(MultiOut)
        }, error = function(e) {
          warning("DenNHist plot generation failed: ", e\$message)
        })
        dev.off()
        
        # 4. Save meaningful results to files
        # Save the main output objects as RDS for downstream analysis
        saveRDS(MultiOut, "MultiOut.rds")
        saveRDS(MultiPP, "MultiPP.rds")
        saveRDS(MultiFC, "MultiFC.rds")
        
        # Save posterior probabilities and MAP patterns to CSV
        write.csv(MultiPP\$PP, "posterior_probabilities.csv", row.names = TRUE)
        write.csv(data.frame(Gene = names(MultiPP\$MAP), MAP_Pattern = MultiPP\$MAP), "map_patterns.csv", row.names = FALSE)
        write.csv(MultiPP\$Patterns, "tested_patterns.csv", row.names = TRUE)
        
        # Save fold change matrices if available
        if (is.list(MultiFC)) {
          for (name in names(MultiFC)) {
            if (is.matrix(MultiFC[[name]]) || is.data.frame(MultiFC[[name]]) || is.vector(MultiFC[[name]])) {
              tryCatch({
                write.csv(MultiFC[[name]], paste0("fold_change_", name, ".csv"), row.names = TRUE)
              }, error = function(e) {})
            }
          }
        }

    writeLines(c(
        '"BIOC_EBSEQ_GENE_DE_MULTI_CONDITIONS":',
        paste0('    EBSeq: ', as.character(packageVersion('EBSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_de_multi_conditions.csv versions.yml
    """
}

workflow BIOC_EBSEQ_GENE_DE_MULTI_CONDITIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ multi_condition_gene_counts.csv, multi_conditions.csv ] ]

    main:
    BIOC_EBSEQ_GENE_DE_MULTI_CONDITIONS(ch_input)

    emit:
    tables   = BIOC_EBSEQ_GENE_DE_MULTI_CONDITIONS.out.tables
    plots    = BIOC_EBSEQ_GENE_DE_MULTI_CONDITIONS.out.plots
    objects  = BIOC_EBSEQ_GENE_DE_MULTI_CONDITIONS.out.objects
    versions = BIOC_EBSEQ_GENE_DE_MULTI_CONDITIONS.out.versions
}
