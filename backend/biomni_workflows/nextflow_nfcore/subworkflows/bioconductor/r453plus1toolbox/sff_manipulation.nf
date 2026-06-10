#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: r453plus1toolbox — sff_manipulation
// Import, subset, write, and perform quality control on Standard Flowgram Format (SFF) files.
// Input: example.sff
// Container: quay.io/biocontainers/bioconductor-r453plus1toolbox:1.56.0--r44h3df3fcb_0
// R packages: R453Plus1Toolbox
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-r453plus1toolbox:1.56.0--r44h3df3fcb_0"

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
    
    # Load the required Bioconductor library
    library(R453Plus1Toolbox)
    
    # 1. Read the binary SFF file into an SFFContainer
    # The pipeline reads EXACTLY "example.sff" from the working directory
    file <- "example.sff"
    sffContainer <- readSFF(file)
    
    # Save the imported container as an RDS object for downstream utility
    saveRDS(sffContainer, file = "sffContainer.rds")
    
    # 2. Subset the SFFContainer by read indices
    subSffContainer <- sffContainer[1:5]
    
    # Save the subsetted container as an RDS object
    saveRDS(subSffContainer, file = "subSffContainer.rds")
    
    # 3. Write the subsetted SFFContainer back to a binary SFF file
    writeSFF(subSffContainer, "subSffFile.sff")
    
    # 4. Generate quality control plots (position quality boxplot and dinucleotide odds ratio)
    # Save the position quality boxplot to a PDF file
    pdf("position_quality_boxplot.pdf")
    positionQualityBoxplot(sffContainer)
    dev.off()
    
    # Save the dinucleotide odds ratio plot to a PDF file
    pdf("dinucleotide_odds_ratio.pdf")
    dinucleotideOddsRatio(sffContainer)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION":
        r453plus1toolbox: \$(Rscript -e 'cat(as.character(packageVersion("r453plus1toolbox")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sff_manipulation.csv versions.yml
    """
}

workflow BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.sff ] ]

    main:
    BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION(ch_input)

    emit:
    tables   = BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION.out.tables
    plots    = BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION.out.plots
    objects  = BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION.out.objects
    versions = BIOC_R453PLUS1TOOLBOX_SFF_MANIPULATION.out.versions
}
