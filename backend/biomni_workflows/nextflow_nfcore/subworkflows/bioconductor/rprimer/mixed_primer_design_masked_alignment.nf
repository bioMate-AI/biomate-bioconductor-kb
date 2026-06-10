#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rprimer — mixed_primer_design_masked_alignment
// Design longer, low-degeneracy primers using the mixed (CODEHOP-like) strategy targeting specific masked regions of a multiple DNA sequence alignment.
// Input: example_alignment.txt
// Container: quay.io/biocontainers/bioconductor-rprimer:1.14.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RPRIMER_MIXED_PRIMER_DESIGN_MASKED_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rprimer:1.14.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biostrings", "rprimer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(rprimer)
    library(Biostrings)
    
    # 1. Import alignment using readDNAMultipleAlignment()
    filepath <- "example_alignment.txt"
    if (!file.exists(filepath)) {
      stop("Required input file 'example_alignment.txt' not found in the working directory.")
    }
    
    myAlignment <- readDNAMultipleAlignment(filepath, format = "fasta")
    
    # 2. Mask non-target regions using colmask()
    myMaskedAlignment <- myAlignment
    colmask(myMaskedAlignment, invert = TRUE) <- c(3000:4000, 5000:6000)
    
    # 3. Generate consensus profile of the masked alignment using consensusProfile()
    myMaskedConsensusProfile <- consensusProfile(myMaskedAlignment, ambiguityThreshold = 0.05)
    
    # Save consensus profile results
    write.csv(as.data.frame(myMaskedConsensusProfile), file = "myMaskedConsensusProfile.csv", row.names = FALSE)
    saveRDS(myMaskedConsensusProfile, file = "myMaskedConsensusProfile.rds")
    
    # 4. Design mixed primers (without probes) using designOligos() with modified settings
    myMaskedMixedPrimers <- designOligos(myMaskedConsensusProfile,
                                         maxDegeneracyPrimer = 8,
                                         lengthPrimer = c(24:28),
                                         tmPrimer = c(65,70),
                                         designStrategyPrimer = "mixed", 
                                         probe = FALSE)
    
    # Save designed mixed primers results
    write.csv(as.data.frame(myMaskedMixedPrimers), file = "myMaskedMixedPrimers.csv", row.names = FALSE)
    saveRDS(myMaskedMixedPrimers, file = "myMaskedMixedPrimers.rds")
    
    # 5. Visualize the designed mixed primers using plotData()
    pdf("myMaskedMixedPrimers_plot.pdf", width = 12, height = 8)
    plotData(myMaskedMixedPrimers)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RPRIMER_MIXED_PRIMER_DESIGN_MASKED_ALIGNMENT":
        rprimer: \$(Rscript -e 'cat(as.character(packageVersion("rprimer")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mixed_primer_design_masked_alignment.csv versions.yml
    """
}

workflow BIOC_RPRIMER_MIXED_PRIMER_DESIGN_MASKED_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_alignment.txt ] ]

    main:
    BIOC_RPRIMER_MIXED_PRIMER_DESIGN_MASKED_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_RPRIMER_MIXED_PRIMER_DESIGN_MASKED_ALIGNMENT.out.tables
    plots    = BIOC_RPRIMER_MIXED_PRIMER_DESIGN_MASKED_ALIGNMENT.out.plots
    objects  = BIOC_RPRIMER_MIXED_PRIMER_DESIGN_MASKED_ALIGNMENT.out.objects
    versions = BIOC_RPRIMER_MIXED_PRIMER_DESIGN_MASKED_ALIGNMENT.out.versions
}
