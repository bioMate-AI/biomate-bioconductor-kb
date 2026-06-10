#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rblast — create_custom_blast_db
// Create a custom BLAST database from user-provided sequences and query it locally.
// Input: RNA_example.fasta, fragment
// Container: quay.io/biocontainers/bioconductor-rblast:1.6.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rblast:1.6.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biostrings", "rBLAST")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(rBLAST)
    library(Biostrings)
    
    # 1. Read sequences using readRNAStringSet from the user-provided FASTA file
    seq <- readRNAStringSet("RNA_example.fasta")
    
    # 2. Write sequences to a FASTA file using writeXStringSet
    writeXStringSet(seq, filepath = "seqs.fasta")
    
    # 3. Build the BLAST database using makeblastdb
    makeblastdb("seqs.fasta", db_name = "db/small", dbtype = "nucl")
    
    # 4. Load the custom database using blast
    db <- blast("db/small")
    
    # 5. Extract a query fragment using subseq (documented stage)
    fragment <- subseq(seq[1], start = 101, end = 200)
    
    # Read the user-provided query sequence from the "fragment" file
    # and use it as the query sequence for the prediction
    if (file.exists("fragment")) {
      fragment <- readRNAStringSet("fragment")
    }
    
    # 6. Query the custom database using predict
    results <- predict(db, fragment)
    
    # Write named output files for the meaningful results
    write.csv(results, "blast_results.csv", row.names = FALSE)
    saveRDS(results, "blast_results.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB":
        rblast: \$(Rscript -e 'cat(as.character(packageVersion("rblast")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_create_custom_blast_db.csv versions.yml
    """
}

workflow BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ RNA_example.fasta, fragment ] ]

    main:
    BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB(ch_input)

    emit:
    tables   = BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB.out.tables
    plots    = BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB.out.plots
    objects  = BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB.out.objects
    versions = BIOC_RBLAST_CREATE_CUSTOM_BLAST_DB.out.versions
}
