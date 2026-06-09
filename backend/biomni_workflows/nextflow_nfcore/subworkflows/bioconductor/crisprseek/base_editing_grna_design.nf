#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CRISPRseek — base_editing_grna_design
// Design gRNAs optimized for Cytosine or Adenine base editors.
// Input: inputseq.fa
// Container: quay.io/biocontainers/bioconductor-crisprseek:1.50.0--r45hdfd78af_0
// Requires: Biostrings, CRISPRseek
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run offTargetAnalysis with baseEditing = TRUE and specify target base and editing windows

nextflow.enable.dsl = 2

process BIOC_CRISPRSEEK_BASE_EDITING_GRNA_DESIGN {
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
    library(CRISPRseek)
    library(Biostrings)
    
    # Define input and output paths
    inputFilePath <- "inputseq.fa"
    outputDir <- "base_editing_results"
    
    # Verify input file exists
    if (!file.exists(inputFilePath)) {
      stop(paste("Error: Input file", inputFilePath, "does not exist in the current working directory."))
    }
    
    # Create output directory if it doesn't exist
    if (!dir.exists(outputDir)) {
      dir.create(outputDir, recursive = TRUE)
    }
    
    # Run the off-target analysis configured for base editing
    res <- offTargetAnalysis(inputFilePath = inputFilePath,
                             chromToSearch = "",
                             baseEditing = TRUE,
                             targetBase = "C",
                             editingWindow = 4:8,
                             editingWindow.offtargets = 4:8,
                             outputDir = outputDir,
                             overwrite = TRUE)
    
    # Save the resulting gRNA sequences
    saveRDS(res, file = file.path(outputDir, "base_editing_gRNAs.rds"))
    writeXStringSet(res, filepath = file.path(outputDir, "base_editing_gRNAs.fa"))
    
    message("Base editing gRNA design completed successfully. Results saved to ", outputDir)

    writeLines(c(
        '"BIOC_CRISPRSEEK_BASE_EDITING_GRNA_DESIGN":',
        paste0('    CRISPRseek: ', as.character(packageVersion('CRISPRseek')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_base_editing_grna_design.csv versions.yml
    """
}

workflow BIOC_CRISPRSEEK_BASE_EDITING_GRNA_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputseq.fa ] ]

    main:
    BIOC_CRISPRSEEK_BASE_EDITING_GRNA_DESIGN(ch_input)

    emit:
    tables   = BIOC_CRISPRSEEK_BASE_EDITING_GRNA_DESIGN.out.tables
    plots    = BIOC_CRISPRSEEK_BASE_EDITING_GRNA_DESIGN.out.plots
    objects  = BIOC_CRISPRSEEK_BASE_EDITING_GRNA_DESIGN.out.objects
    versions = BIOC_CRISPRSEEK_BASE_EDITING_GRNA_DESIGN.out.versions
}
