#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: R453Plus1Toolbox — sff_manipulation_qc
// Import, subset, write, and perform quality control on Standard Flowgram Format (SFF) files.
// Input: file
// Container: quay.io/biocontainers/bioconductor-r453plus1toolbox:1.56.0--r44h3df3fcb_0
// R packages: R453Plus1Toolbox
// Bioconductor: 3.20 | R: 4.4
// Requires: R453Plus1Toolbox
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read SFF file using readSFF
//  * 2. [Core Analysis] Subset SFF container using [
//  * 3. [Visualization & Output] Write SFF file using writeSFF
//  * 4. [Visualization & Output] Generate quality control plots using positionQualityBoxplot and dinucleotideOddsRatio

nextflow.enable.dsl = 2

process BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION_QC {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("R453Plus1Toolbox")
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
    library(R453Plus1Toolbox)
    
    # 1. Identify and Read the User-Provided SFF File
    sff_files <- list.files(pattern = "\\\\.sff\$", ignore.case = TRUE)
    if (length(sff_files) == 0) {
      stop("Error: No SFF file found in the working directory. Please provide a binary SFF file.")
    }
    file <- sff_files[1]
    
    message("Reading SFF file: ", file)
    sffContainer <- readSFF(file)
    
    # Save the imported container as an RDS object
    saveRDS(sffContainer, "sffContainer.rds")
    
    # 2. Subset SFF Container
    message("Subsetting SFF container (first 5 reads)...")
    # Determine subset range safely based on available reads
    num_reads <- length(reads(sffContainer))
    if (num_reads < 5) {
      message("Warning: SFF container has fewer than 5 reads. Subsetting all available reads.")
      subSffContainer <- sffContainer[1:num_reads]
    } else {
      subSffContainer <- sffContainer[1:5]
    }
    
    # Save the subsetted container as an RDS object
    saveRDS(subSffContainer, "subSffContainer.rds")
    
    # 3. Write SFF File
    message("Writing subsetted SFF container to 'subSffFile.sff'...")
    writeSFF(subSffContainer, "subSffFile.sff")
    
    # 4. Generate Quality Control Plots
    message("Generating quality control plots...")
    
    # Position Quality Boxplot
    pdf("positionQualityBoxplot.pdf", width = 8, height = 6)
    positionQualityBoxplot(sffContainer)
    dev.off()
    
    # Dinucleotide Odds Ratio Plot
    pdf("dinucleotideOddsRatio.pdf", width = 8, height = 6)
    dinucleotideOddsRatio(sffContainer)
    dev.off()
    
    message("Pipeline completed successfully. Outputs generated: 'subSffFile.sff', 'sffContainer.rds', 'subSffContainer.rds', 'positionQualityBoxplot.pdf', 'dinucleotideOddsRatio.pdf'.")

    writeLines(c(
        '"BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION_QC":',
        paste0('    R453Plus1Toolbox: ', as.character(packageVersion('R453Plus1Toolbox')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sff_manipulation_qc.csv versions.yml
    """
}

workflow BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file ] ]

    main:
    BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION_QC(ch_input)

    emit:
    tables   = BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION_QC.out.tables
    plots    = BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION_QC.out.plots
    objects  = BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION_QC.out.objects
    versions = BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION_QC.out.versions
}
