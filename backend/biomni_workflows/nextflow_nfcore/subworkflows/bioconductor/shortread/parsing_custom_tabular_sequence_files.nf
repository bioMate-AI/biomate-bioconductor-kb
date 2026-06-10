#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: shortread — parsing_custom_tabular_sequence_files
// Read specific columns of sequence and quality data from tabular text files (e.g., Solexa export format) into Biostrings objects.
// Input: s_2_export.txt
// Container: quay.io/biocontainers/bioconductor-shortread:1.68.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SHORTREAD_PARSING_CUSTOM_TABULAR_SEQUENCE_FILES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-shortread:1.68.0--r45ha27e39d_0"

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
    .bm_deps <- c("Biostrings", "ShortRead")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(ShortRead)
    library(Biostrings)
    
    # Define the SolexaPath and pattern to read from the working directory
    sp <- SolexaPath(".", analysisPath=".")
    pattern <- "s_2_export.txt"
    
    # 1. Define column classes using a list where target columns are specified as "DNAString" or "BString" and others are NULL
    colClasses <- rep(list(NULL), 21)
    colClasses[9:10] <- c("DNAString", "BString")
    names(colClasses)[9:10] <- c("read", "quality")
    
    # 2. Read the specified columns from the file using readXStringColumns()
    cols <- readXStringColumns(analysisPath(sp), pattern, colClasses)
    
    # Save the parsed objects to an RDS file
    saveRDS(cols, "parsed_columns.rds")
    
    # Create and save a summary CSV table of the parsed sequences and qualities
    df_summary <- data.frame(
      read = as.character(cols\$read),
      quality = as.character(cols\$quality),
      width = width(cols\$read),
      stringsAsFactors = FALSE
    )
    write.csv(df_summary, "parsed_sequences_summary.csv", row.names = FALSE)
    
    # Generate and save a PDF plot of the base composition
    freqs <- alphabetFrequency(cols\$read, baseOnly = TRUE)
    pdf("alphabet_frequency.pdf")
    barplot(colSums(freqs), main="Base Composition of Parsed Reads", col="darkgreen", ylab="Count")
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SHORTREAD_PARSING_CUSTOM_TABULAR_SEQUENCE_FILES":
        shortread: \$(Rscript -e 'cat(as.character(packageVersion("shortread")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_parsing_custom_tabular_sequence_files.csv versions.yml
    """
}

workflow BIOC_SHORTREAD_PARSING_CUSTOM_TABULAR_SEQUENCE_FILES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ s_2_export.txt ] ]

    main:
    BIOC_SHORTREAD_PARSING_CUSTOM_TABULAR_SEQUENCE_FILES(ch_input)

    emit:
    tables   = BIOC_SHORTREAD_PARSING_CUSTOM_TABULAR_SEQUENCE_FILES.out.tables
    plots    = BIOC_SHORTREAD_PARSING_CUSTOM_TABULAR_SEQUENCE_FILES.out.plots
    objects  = BIOC_SHORTREAD_PARSING_CUSTOM_TABULAR_SEQUENCE_FILES.out.objects
    versions = BIOC_SHORTREAD_PARSING_CUSTOM_TABULAR_SEQUENCE_FILES.out.versions
}
