#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: eisar — reference_generation
// Generate reference sequences, an expanded GTF, and transcript-to-gene mappings for alignment-free abundance estimation methods.
// Input: gencode.v28.annotation.sub.gtf, BSgenome.Hsapiens.UCSC.hg38
// Container: quay.io/biocontainers/bioconductor-eisar:1.22.1--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EISAR_REFERENCE_GENERATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-eisar:1.22.1--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38", "Biostrings", "GenomicFeatures", "edger", "eisar", "quasr", "rtracklayer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(eisaR)
    library(GenomicFeatures)
    library(BSgenome.Hsapiens.UCSC.hg38)
    library(Biostrings)
    
    # 1. Define input file path (replacing system.file)
    gtf <- "gencode.v28.annotation.sub.gtf"
    
    # 2. Extract genomic ranges for spliced transcripts and introns
    grl <- getFeatureRanges(
        gtf = gtf,
        featureType = c("spliced", "intron"),
        intronType = "separate",
        flankLength = 50L,
        joinOverlappingIntrons = FALSE,
        verbose = TRUE
    )
    
    # 3. Extract nucleotide sequences
    seqs <- GenomicFeatures::extractTranscriptSeqs(
        x = BSgenome.Hsapiens.UCSC.hg38,
        transcripts = grl
    )
    
    # Save extracted sequences to the working directory
    Biostrings::writeXStringSet(seqs, "extracted_seqs.fa")
    
    # 4. Export the expanded features to a GTF file (exact call preserved)
    exportToGtf(
        grl,
        filepath = file.path(tempdir(), "exported.gtf")
    )
    
    # Copy the exported GTF to the working directory for user access
    file.copy(file.path(tempdir(), "exported.gtf"), "exported.gtf", overwrite = TRUE)
    
    # 5. Generate a transcript-to-gene mapping table
    df <- getTx2Gene(grl)
    head(df)
    tail(df)
    
    # Save mapping table to the working directory
    write.csv(df, "tx2gene.csv", row.names = FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_EISAR_REFERENCE_GENERATION":
        eisar: \$(Rscript -e 'cat(as.character(packageVersion("eisar")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_generation.csv versions.yml
    """
}

workflow BIOC_EISAR_REFERENCE_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gencode.v28.annotation.sub.gtf, BSgenome.Hsapiens.UCSC.hg38 ] ]

    main:
    BIOC_EISAR_REFERENCE_GENERATION(ch_input)

    emit:
    tables   = BIOC_EISAR_REFERENCE_GENERATION.out.tables
    plots    = BIOC_EISAR_REFERENCE_GENERATION.out.plots
    objects  = BIOC_EISAR_REFERENCE_GENERATION.out.objects
    versions = BIOC_EISAR_REFERENCE_GENERATION.out.versions
}
