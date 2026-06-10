#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msa — sequence_alignment_and_pretty_printing
// Align amino acid or nucleotide sequences and generate a highly customizable PDF visualization of the alignment.
// Input: exampleAA.fasta
// Container: quay.io/biocontainers/bioconductor-msa:1.42.0--r45he8cd136_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSA_SEQUENCE_ALIGNMENT_AND_PRETTY_PRINTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-msa:1.42.0--r45he8cd136_0"

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
    .bm_deps <- c("Biostrings", "ape", "msa", "pwalign", "seqinr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(msa)
    library(Biostrings)
    
    # 1. Read sequences using Biostrings from the working directory
    mySequenceFile <- "exampleAA.fasta"
    if (!file.exists(mySequenceFile)) {
      stop(paste("Required input file", mySequenceFile, "not found in the working directory."))
    }
    
    mySequences <- readAAStringSet(mySequenceFile)
    mySequences
    
    # 2. Perform multiple sequence alignment using msa
    myFirstAlignment <- msa(mySequences)
    myFirstAlignment
    
    # Save the alignment object as an RDS file for downstream analysis
    saveRDS(myFirstAlignment, file = "myFirstAlignment.rds")
    
    # 3. Print the complete alignment to the console
    print(myFirstAlignment, show="complete")
    
    # 4. Generate a pretty-printed PDF visualization using msaPrettyPrint
    # Wrapped in tryCatch because msaPrettyPrint requires a local LaTeX installation with texshade.sty
    tryCatch({
      msaPrettyPrint(myFirstAlignment, output="pdf", showNames="none", showLogo="none", askForOverwrite=FALSE, verbose=FALSE)
    }, error = function(e) {
      warning("msaPrettyPrint failed (this function requires a working system installation of LaTeX and texshade.sty): ", e\$message)
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MSA_SEQUENCE_ALIGNMENT_AND_PRETTY_PRINTING":
        msa: \$(Rscript -e 'cat(as.character(packageVersion("msa")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequence_alignment_and_pretty_printing.csv versions.yml
    """
}

workflow BIOC_MSA_SEQUENCE_ALIGNMENT_AND_PRETTY_PRINTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exampleAA.fasta ] ]

    main:
    BIOC_MSA_SEQUENCE_ALIGNMENT_AND_PRETTY_PRINTING(ch_input)

    emit:
    tables   = BIOC_MSA_SEQUENCE_ALIGNMENT_AND_PRETTY_PRINTING.out.tables
    plots    = BIOC_MSA_SEQUENCE_ALIGNMENT_AND_PRETTY_PRINTING.out.plots
    objects  = BIOC_MSA_SEQUENCE_ALIGNMENT_AND_PRETTY_PRINTING.out.objects
    versions = BIOC_MSA_SEQUENCE_ALIGNMENT_AND_PRETTY_PRINTING.out.versions
}
