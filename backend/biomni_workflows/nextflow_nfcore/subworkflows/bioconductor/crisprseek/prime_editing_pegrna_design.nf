#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CRISPRseek — prime_editing_pegrna_design
// Design gRNAs and pegRNAs for prime editing.
// Input: inputFilePath
// Container: quay.io/biocontainers/bioconductor-crisprseek:1.50.0--r45hdfd78af_0
// R packages: Biostrings, CRISPRseek
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, CRISPRseek
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run offTargetAnalysis with primeEditing = TRUE and specify prime-editing-specific parameters (PBS length, RT template length, corr

nextflow.enable.dsl = 2

process BIOC_CRISPRSEEK_PRIME_EDITING_PEGRNA_DESIGN {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("Biostrings", "CRISPRseek")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    library(CRISPRseek)
    library(Biostrings)
    
    # Define output directory
    outputDir <- getwd()
    
    # Read user input file from the working directory
    # The pipeline expects 'inputFilePath' as a DNAStringSet object.
    # We support reading it from an RDS file or a FASTA file.
    if (file.exists("inputFilePath.rds")) {
      inputFilePath <- readRDS("inputFilePath.rds")
    } else if (file.exists("inputFilePath.fa")) {
      inputFilePath <- readDNAStringSet("inputFilePath.fa")
    } else if (file.exists("inputFilePath.fasta")) {
      inputFilePath <- readDNAStringSet("inputFilePath.fasta")
    } else if (file.exists("inputFilePath")) {
      # Attempt to read if the file is named exactly 'inputFilePath' without extension
      inputFilePath <- tryCatch({
        readRDS("inputFilePath")
      }, error = function(e) {
        readDNAStringSet("inputFilePath")
      })
    } else {
      stop("Required user input file 'inputFilePath' (as RDS or FASTA) not found in the working directory.")
    }
    
    # Run offTargetAnalysis with primeEditing = TRUE and specify prime-editing-specific parameters
    res <- offTargetAnalysis(inputFilePath,
                             chromToSearch = "",
                             gRNAoutputName = "testPEgRNAs", # Required when inputFilePath is a DNAStringSet object.
                             primeEditing = TRUE,
                             targeted.seq.length.change = 0,
                             bp.after.target.end = 15,
                             PBS.length = 15,
                             RT.template.length = 8:30,
                             RT.template.pattern = "D\$",
                             target.start = 20,
                             target.end = 20,
                             corrected.seq = "T",
                             findPairedgRNAOnly = TRUE,
                             paired.orientation = "PAMin",
                             outputDir = outputDir, 
                             overwrite = TRUE)
    
    # Save the resulting DNAStringSet object containing designed pegRNAs
    saveRDS(res, file = file.path(outputDir, "designed_pegrnas.rds"))
    writeXStringSet(res, filepath = file.path(outputDir, "designed_pegrnas.fa"))

    writeLines(c(
        '"BIOC_CRISPRSEEK_PRIME_EDITING_PEGRNA_DESIGN":',
        paste0('    CRISPRseek: ', as.character(packageVersion('CRISPRseek')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prime_editing_pegrna_design.csv versions.yml
    """
}

workflow BIOC_CRISPRSEEK_PRIME_EDITING_PEGRNA_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputFilePath ] ]

    main:
    BIOC_CRISPRSEEK_PRIME_EDITING_PEGRNA_DESIGN(ch_input)

    emit:
    tables   = BIOC_CRISPRSEEK_PRIME_EDITING_PEGRNA_DESIGN.out.tables
    plots    = BIOC_CRISPRSEEK_PRIME_EDITING_PEGRNA_DESIGN.out.plots
    objects  = BIOC_CRISPRSEEK_PRIME_EDITING_PEGRNA_DESIGN.out.objects
    versions = BIOC_CRISPRSEEK_PRIME_EDITING_PEGRNA_DESIGN.out.versions
}
