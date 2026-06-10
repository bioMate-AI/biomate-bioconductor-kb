#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: varianttools — wildtype_calling
// Determine which non-variant positions have sufficient coverage to be confidently called wildtype.
// Input: sample.bam, called_variants.GRanges
// Container: quay.io/biocontainers/bioconductor-varianttools:1.51.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VARIANTTOOLS_WILDTYPE_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-varianttools:1.51.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "VariantTools")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(VariantTools)
    library(GenomicRanges)
    
    # 1. Read the declared user input files from the working directory
    bam <- "sample.bam"
    called.variants <- readRDS("called_variants.GRanges")
    
    # 2. Execute the documented workflow steps exactly as specified
    called.variants <- called.variants[!isIndel(called.variants)]
    pos <- c(called.variants, shift(called.variants, 3))
    wildtype <- callWildtype(bam, called.variants, VariantCallingFilters(), 
                             pos = pos, power = 0.85)
    
    # 3. Write meaningful output files
    # Save the raw wildtype results as an RDS object
    saveRDS(wildtype, "wildtype_results.rds")
    
    # Export a combined CSV table of positions and their wildtype status
    output_df <- as.data.frame(pos)
    output_df\$wildtype <- as.vector(wildtype)
    write.csv(output_df, "wildtype_calls.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_VARIANTTOOLS_WILDTYPE_CALLING":
        varianttools: \$(Rscript -e 'cat(as.character(packageVersion("varianttools")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wildtype_calling.csv versions.yml
    """
}

workflow BIOC_VARIANTTOOLS_WILDTYPE_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.bam, called_variants.GRanges ] ]

    main:
    BIOC_VARIANTTOOLS_WILDTYPE_CALLING(ch_input)

    emit:
    tables   = BIOC_VARIANTTOOLS_WILDTYPE_CALLING.out.tables
    plots    = BIOC_VARIANTTOOLS_WILDTYPE_CALLING.out.plots
    objects  = BIOC_VARIANTTOOLS_WILDTYPE_CALLING.out.objects
    versions = BIOC_VARIANTTOOLS_WILDTYPE_CALLING.out.versions
}
