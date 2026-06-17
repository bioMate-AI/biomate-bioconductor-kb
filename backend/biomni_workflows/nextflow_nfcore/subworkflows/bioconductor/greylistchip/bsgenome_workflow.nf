#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GreyListChIP — bsgenome_workflow
// Generate a grey list in a single step using a BSgenome package and an input BAM file.
// Input: myBamFile.bam
// Container: quay.io/biocontainers/bioconductor-greylistchip:1.42.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, GreyListChIP, Rsamtools
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, GreyListChIP, Rsamtools
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load BSgenome package
//  * 2. [Core Analysis] Generate grey list in one step using greyListBS
//  * 3. [Visualization & Output] Export grey list to BED file

nextflow.enable.dsl = 2

process BIOC_GREYLISTCHIP_BSGENOME_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "GreyListChIP", "Rsamtools")
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
    library(GreyListChIP)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(Rsamtools)
    
    # Define input file
    bam_file <- "myBamFile.bam"
    
    # Check if input file exists
    if (!file.exists(bam_file)) {
      stop(paste("Error: Input BAM file", bam_file, "not found in the working directory."))
    }
    
    # Ensure BAM index exists, create if missing
    bai_file <- paste0(bam_file, ".bai")
    if (!file.exists(bai_file)) {
      message("BAM index file not found. Attempting to index BAM file...")
      tryCatch({
        Rsamtools::indexBam(bam_file)
        message("BAM file indexed successfully.")
      }, error = function(e) {
        warning("Could not index BAM file automatically. greyListBS may fail if index is missing: ", e\$message)
      })
    }
    
    # Generate grey list in a single step using BSgenome and the input BAM file
    message("Generating grey list using BSgenome.Hsapiens.UCSC.hg19 and ", bam_file, "...")
    gl <- greyListBS(BSgenome.Hsapiens.UCSC.hg19,"myBamFile.bam")
    
    # Export the grey list to a BED file
    message("Exporting grey list to myGreyList.bed...")
    export(gl,con="myGreyList.bed")
    
    # Save additional outputs for downstream analysis
    message("Saving summary and RDS object...")
    saveRDS(gl, file = "myGreyList.rds")
    
    # Write a text summary of the generated grey list
    sink("myGreyList_summary.txt")
    cat("GreyList Summary\n")
    cat("================\n")
    print(gl)
    sink()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GREYLISTCHIP_BSGENOME_WORKFLOW":',
        paste0('    GreyListChIP: ', as.character(packageVersion('GreyListChIP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bsgenome_workflow.csv versions.yml
    """
}

workflow BIOC_GREYLISTCHIP_BSGENOME_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ myBamFile.bam ] ]

    main:
    BIOC_GREYLISTCHIP_BSGENOME_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_GREYLISTCHIP_BSGENOME_WORKFLOW.out.tables
    plots    = BIOC_GREYLISTCHIP_BSGENOME_WORKFLOW.out.plots
    objects  = BIOC_GREYLISTCHIP_BSGENOME_WORKFLOW.out.objects
    versions = BIOC_GREYLISTCHIP_BSGENOME_WORKFLOW.out.versions
}
