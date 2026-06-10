#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mariner — calculate_loop_enrichment
// Calculate the enrichment of chromatin loops compared to their local background.
// Input: WT_5kbLoops.txt, LEUK_HEK_PJA27_inter_30.hic, LEUK_HEK_PJA30_inter_30.hic
// Container: quay.io/biocontainers/bioconductor-mariner:1.10.2--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MARINER_CALCULATE_LOOP_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mariner:1.10.2--r45hdfd78af_0"

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
    .bm_deps <- c("GenomeInfoDb", "InteractionSet", "mariner")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(mariner)
    library(InteractionSet)
    library(GenomeInfoDb)
    
    ## Define hicFiles from the working directory
    hicFiles <- c(
        "LEUK_HEK_PJA27_inter_30.hic",
        "LEUK_HEK_PJA30_inter_30.hic"
    ) |> setNames(c("FS", "WT"))
    
    ## Read in loops from the working directory
    loops <- 
        "WT_5kbLoops.txt" |>
        setNames("WT") |>
        read.table(header=TRUE, nrows=1000) |>
        as_ginteractions() |>
        assignToBins(binSize=100e3) |>
        GenomeInfoDb::`seqlevelsStyle<-`('ENSEMBL')
    
    ## Define foreground & background
    buffer <- 10
    fg <- selectCenterPixel(mhDist=0:1, buffer=buffer)
    bg <- selectTopLeft(n=2, buffer=buffer) +
        selectBottomRight(n=2, buffer=buffer)
    
    ## Calculate loop enrichment
    enrich <- calcLoopEnrichment(
        x=loops,
        files=hicFiles,
        fg=fg,
        bg=bg
    )
    
    # Display the enrichment results
    print(enrich)
    
    # Save the meaningful results to output files
    # Convert DelayedMatrix to a standard matrix for CSV export
    enrich_matrix <- as.matrix(enrich)
    write.csv(enrich_matrix, "loop_enrichment_results.csv", row.names = FALSE)
    saveRDS(enrich, "loop_enrichment_results.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MARINER_CALCULATE_LOOP_ENRICHMENT":
        mariner: \$(Rscript -e 'cat(as.character(packageVersion("mariner")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_calculate_loop_enrichment.csv versions.yml
    """
}

workflow BIOC_MARINER_CALCULATE_LOOP_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ WT_5kbLoops.txt, LEUK_HEK_PJA27_inter_30.hic, LEUK_HEK_PJA30_inter_30.hic ] ]

    main:
    BIOC_MARINER_CALCULATE_LOOP_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_MARINER_CALCULATE_LOOP_ENRICHMENT.out.tables
    plots    = BIOC_MARINER_CALCULATE_LOOP_ENRICHMENT.out.plots
    objects  = BIOC_MARINER_CALCULATE_LOOP_ENRICHMENT.out.objects
    versions = BIOC_MARINER_CALCULATE_LOOP_ENRICHMENT.out.versions
}
