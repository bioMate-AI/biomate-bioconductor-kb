#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ssviz — pirna_ping_pong_and_composition
// Perform piRNA-specific analyses including ping-pong feedback loop overlap detection and 5-prime nucleotide frequency bias calculation.
// Input: file1.bam
// Container: quay.io/biocontainers/bioconductor-ssviz:1.44.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SSVIZ_PIRNA_PING_PONG_AND_COMPOSITION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ssviz:1.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("ssviz")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(ssviz)
    
    # 1. Load the dataset and extract collapsed read counts using getCountMatrix
    # Read the user input file "file1.bam"
    pctrlbam <- readBam("file1.bam")
    pctrlbam.count <- getCountMatrix(pctrlbam)
    
    # 2. Calculate sense and anti-sense piRNA overlap frequencies using pingpong
    pp.ctrl <- pingpong(pctrlbam.count)
    
    # 3. Plot the ping-pong overlap frequency using plotPP
    pdf("ping_pong_overlap_plot.pdf", width = 8, height = 6)
    plotPP(list(pp.ctrl), samplenames = c("Control"))
    dev.off()
    
    # 4. Compute nucleotide frequency over a specified length using ntfreq
    pctrlbam.count <- getCountMatrix(pctrlbam)
    freq.ctrl <- ntfreq(pctrlbam.count, ntlength = 10)
    
    # 5. Plot the nucleotide composition using plotFreq
    pdf("nucleotide_frequency_plot.pdf", width = 8, height = 6)
    plotFreq(freq.ctrl)
    dev.off()
    
    # Save meaningful results to files
    saveRDS(pp.ctrl, "pingpong_results.rds")
    saveRDS(freq.ctrl, "ntfreq_results.rds")
    
    tryCatch({
      write.csv(as.data.frame(pp.ctrl), "pingpong_results.csv", row.names = TRUE)
    }, error = function(e) {
      warning("Could not write pp.ctrl to CSV: ", e\$message)
    })
    
    tryCatch({
      write.csv(as.data.frame(freq.ctrl), "ntfreq_results.csv", row.names = TRUE)
    }, error = function(e) {
      warning("Could not write freq.ctrl to CSV: ", e\$message)
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SSVIZ_PIRNA_PING_PONG_AND_COMPOSITION":
        ssviz: \$(Rscript -e 'cat(as.character(packageVersion("ssviz")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pirna_ping_pong_and_composition.csv versions.yml
    """
}

workflow BIOC_SSVIZ_PIRNA_PING_PONG_AND_COMPOSITION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file1.bam ] ]

    main:
    BIOC_SSVIZ_PIRNA_PING_PONG_AND_COMPOSITION(ch_input)

    emit:
    tables   = BIOC_SSVIZ_PIRNA_PING_PONG_AND_COMPOSITION.out.tables
    plots    = BIOC_SSVIZ_PIRNA_PING_PONG_AND_COMPOSITION.out.plots
    objects  = BIOC_SSVIZ_PIRNA_PING_PONG_AND_COMPOSITION.out.objects
    versions = BIOC_SSVIZ_PIRNA_PING_PONG_AND_COMPOSITION.out.versions
}
