#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprseek — prime_editing_grna_design
// Design gRNAs and pegRNAs for prime editing.
// Input: inputseq.fa
// Container: quay.io/biocontainers/bioconductor-crisprseek:1.50.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRSEEK_PRIME_EDITING_GRNA_DESIGN {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-crisprseek:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biostrings", "CRISPRseek")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(CRISPRseek)
    library(Biostrings)
    
    # Define input and output paths
    input_file <- "inputseq.fa"
    outputDir <- getwd()
    
    # Read the user-provided FASTA file from the working directory
    # to construct the DNAStringSet object
    inputFilePath <- readDNAStringSet(input_file)
    
    # Run offTargetAnalysis with primeEditing = TRUE and the specified parameters
    res <- offTargetAnalysis(inputFilePath,
                             chromToSearch = "",
                             gRNAoutputName = "testPEgRNAs", # Required when inputFilePath is a DNAStringSet object.
                             primeEditing = TRUE,
                             targeted.seq.length.change = 0,
                             bp.after.target.end = 15,
                             PBS.length = 15,
                             RT.template.length = 8:30,
                             RT.template.pattern = "D\$",
                             target.start = 20,
                             target.end = 20,
                             corrected.seq = "T",
                             findPairedgRNAOnly = TRUE,
                             paired.orientation = "PAMin",
                             outputDir = outputDir, 
                             overwrite = TRUE)
    
    # Save the resulting DNAStringSet object to an RDS file
    saveRDS(res, file = "prime_editing_gRNAs.rds")
    
    # Print the results to the console
    print(res)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CRISPRSEEK_PRIME_EDITING_GRNA_DESIGN":
        crisprseek: \$(Rscript -e 'cat(as.character(packageVersion("crisprseek")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prime_editing_grna_design.csv versions.yml
    """
}

workflow BIOC_CRISPRSEEK_PRIME_EDITING_GRNA_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ inputseq.fa ] ]

    main:
    BIOC_CRISPRSEEK_PRIME_EDITING_GRNA_DESIGN(ch_input)

    emit:
    tables   = BIOC_CRISPRSEEK_PRIME_EDITING_GRNA_DESIGN.out.tables
    plots    = BIOC_CRISPRSEEK_PRIME_EDITING_GRNA_DESIGN.out.plots
    objects  = BIOC_CRISPRSEEK_PRIME_EDITING_GRNA_DESIGN.out.objects
    versions = BIOC_CRISPRSEEK_PRIME_EDITING_GRNA_DESIGN.out.versions
}
