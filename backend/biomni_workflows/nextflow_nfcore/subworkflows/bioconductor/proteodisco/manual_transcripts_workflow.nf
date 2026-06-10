#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: proteodisco — manual_transcripts_workflow
// Import manually-curated or long-read transcript sequences to check for proteotypic peptides and export to a customized protein database.
// Input: manualSeq
// Container: quay.io/biocontainers/bioconductor-proteodisco:1.16.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROTEODISCO_MANUAL_TRANSCRIPTS_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-proteodisco:1.16.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "Biostrings", "ProteoDisco", "S4Vectors", "TxDb.Hsapiens.UCSC.hg19.knownGene")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(ProteoDisco)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(S4Vectors)
    library(Biostrings)
    
    # 1. Read the user input file from the working directory
    # The user input is 'manualSeq', an S4Vectors DataFrame containing mutant sequences and metadata.
    # We read this object from 'manualSeq.rds' in the working directory.
    if (!file.exists("manualSeq.rds")) {
      stop("Required input file 'manualSeq.rds' not found in the working directory.")
    }
    manualSeq <- readRDS("manualSeq.rds")
    
    # 2. Generate the ProteoDiscography reference database
    ProteoDiscography.hg19 <- ProteoDisco::generateProteoDiscography(
      TxDb = TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene, 
      genomeSeqs = BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    )
    
    # 3. Import manual transcript sequences
    ProteoDiscography.hg19 <- ProteoDisco::importTranscriptSequences(
      ProteoDiscography.hg19, 
      transcripts = manualSeq,
      removeExisting = TRUE
    )
    
    # 4. Export the customized database to FASTA
    ProteoDisco::exportProteoDiscography(
      ProteoDiscography = ProteoDiscography.hg19, 
      outFile = 'example.fasta', 
      aggregateSamples = TRUE
    )
    
    # 5. Save meaningful results and outputs
    # Save the final ProteoDiscography object as RDS
    saveRDS(ProteoDiscography.hg19, file = "ProteoDiscography_final.rds")
    
    # Export a summary table of the imported transcripts
    discography_df <- ProteoDisco::getDiscography(ProteoDiscography.hg19)
    write.csv(as.data.frame(discography_df), file = "imported_transcripts_summary.csv", row.names = FALSE)
    
    message("Workflow completed successfully. Outputs written to 'example.fasta', 'ProteoDiscography_final.rds', and 'imported_transcripts_summary.csv'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PROTEODISCO_MANUAL_TRANSCRIPTS_WORKFLOW":
        proteodisco: \$(Rscript -e 'cat(as.character(packageVersion("proteodisco")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_manual_transcripts_workflow.csv versions.yml
    """
}

workflow BIOC_PROTEODISCO_MANUAL_TRANSCRIPTS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ manualSeq ] ]

    main:
    BIOC_PROTEODISCO_MANUAL_TRANSCRIPTS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_PROTEODISCO_MANUAL_TRANSCRIPTS_WORKFLOW.out.tables
    plots    = BIOC_PROTEODISCO_MANUAL_TRANSCRIPTS_WORKFLOW.out.plots
    objects  = BIOC_PROTEODISCO_MANUAL_TRANSCRIPTS_WORKFLOW.out.objects
    versions = BIOC_PROTEODISCO_MANUAL_TRANSCRIPTS_WORKFLOW.out.versions
}
