#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprseek — base_editing_grna_design
// Design gRNAs optimized for base editing systems (CBE or ABE).
// Input: inputseq.fa
// Container: quay.io/biocontainers/bioconductor-crisprseek:1.50.0--r45hdfd78af_0
// R packages: CRISPRseek
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRSEEK_BASE_EDITING_GRNA_DESIGN {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-crisprseek:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("CRISPRseek")
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
    
    # Load required library
    library(CRISPRseek)
    
    # Define input and output paths
    inputFilePath <- "inputseq.fa"
    outputDir <- getwd()
    
    # Validate that the required user input file exists
    if (!file.exists(inputFilePath)) {
      stop(paste("Required input file '", inputFilePath, "' not found in the working directory.", sep = ""))
    }
    
    # Run the off-target analysis optimized for base editing as documented
    res <- offTargetAnalysis(inputFilePath = inputFilePath,
                             chromToSearch = "",
                             baseEditing = TRUE,
                             targetBase = "C",
                             editingWindow = 4:8,
                             editingWindow.offtargets = 4:8,
                             outputDir = outputDir,
                             overwrite = TRUE)
    
    # Print the resulting gRNA sequences
    print(res)
    
    # Save the resulting DNAStringSet object to an RDS file
    saveRDS(res, file = file.path(outputDir, "base_editing_gRNAs.rds"))
    
    # Export the designed gRNAs to a FASTA file
    if (inherits(res, "DNAStringSet")) {
      Biostrings::writeXStringSet(res, filepath = file.path(outputDir, "designed_base_editing_gRNAs.fa"))
    }

    writeLines(c(
        '"BIOC_CRISPRSEEK_BASE_EDITING_GRNA_DESIGN":',
        paste0('        crisprseek: ', as.character(packageVersion("crisprseek")))
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
