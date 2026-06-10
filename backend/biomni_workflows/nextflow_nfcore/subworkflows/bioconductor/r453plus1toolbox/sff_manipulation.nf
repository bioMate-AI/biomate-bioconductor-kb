#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: r453plus1toolbox — sff_manipulation
// Import, subset, write, and perform quality control on Standard Flowgram Format (SFF) files.
// Input: example.sff
// Container: quay.io/biocontainers/bioconductor-r453plus1toolbox:1.56.0--r44h3df3fcb_0
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
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
