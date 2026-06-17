#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mariner — loop_enrichment_analysis
// Calculate loop enrichment over local background using custom foreground and background selection matrices.
// Input: WT_5kbLoops.txt, LEUK_HEK_PJA27_inter_30.hic, LEUK_HEK_PJA30_inter_30.hic
// Container: quay.io/biocontainers/bioconductor-mariner:1.10.2--r45hdfd78af_0
// R packages: GenomeInfoDb, InteractionSet, mariner
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomeInfoDb, InteractionSet, mariner
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read BEDPE file and convert to GInteractions using as_ginteractions
//  * 2. [Core Analysis] Assign interactions to bins using assignToBins
//  * 3. [Core Analysis] Standardize chromosome naming style using seqlevelsStyle
//  * 4. [Input & Preparation] Define foreground and background selection matrices using selectCenterPixel, selectTopLeft, and selectBottomRight
//  * 5. [Core Analysis] Calculate loop enrichment using calcLoopEnrichment

nextflow.enable.dsl = 2

process BIOC_MARINER_LOOP_ENRICHMENT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(mariner)
    library(InteractionSet)
    library(GenomeInfoDb)
    
    # Define hicFiles from the working directory
    hicFiles <- c(
        "LEUK_HEK_PJA27_inter_30.hic",
        "LEUK_HEK_PJA30_inter_30.hic"
    ) |> setNames(c("FS", "WT"))
    
    # Read in loops from the working directory
    loops <- 
        "WT_5kbLoops.txt" |>
        setNames("WT") |>
        read.table(header=TRUE, nrows=1000) |>
        as_ginteractions() |>
        assignToBins(binSize=100e3) |>
        GenomeInfoDb::`seqlevelsStyle<-`('ENSEMBL')
    
    # Define foreground & background
    buffer <- 10
    fg <- selectCenterPixel(mhDist=0:1, buffer=buffer)
    bg <- selectTopLeft(n=2, buffer=buffer) +
        selectBottomRight(n=2, buffer=buffer)
    
    # Calculate loop enrichment
    enrich <- calcLoopEnrichment(
        x=loops,
        files=hicFiles,
        fg=fg,
        bg=bg
    )
    
    # Save the meaningful results
    # 1. Save the raw DelayedMatrix object as RDS
    saveRDS(enrich, file = "loop_enrichment.rds")
    
    # 2. Convert to a standard matrix and save as CSV
    enrich_matrix <- as.matrix(enrich)
    write.csv(enrich_matrix, file = "loop_enrichment.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_MARINER_LOOP_ENRICHMENT_ANALYSIS":',
        paste0('    mariner: ', as.character(packageVersion('mariner')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_loop_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_MARINER_LOOP_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ WT_5kbLoops.txt, LEUK_HEK_PJA27_inter_30.hic, LEUK_HEK_PJA30_inter_30.hic ] ]

    main:
    BIOC_MARINER_LOOP_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MARINER_LOOP_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_MARINER_LOOP_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_MARINER_LOOP_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_MARINER_LOOP_ENRICHMENT_ANALYSIS.out.versions
}
