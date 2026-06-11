#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mariner — loop_merging_and_replicate_comparison
// Merge chromatin loops from multiple replicates, resolve duplicates within a specified radius, and identify shared or unique loops.
// Input: FS_5kbLoops.txt, WT_5kbLoops.txt
// Container: quay.io/biocontainers/bioconductor-mariner:1.10.2--r45hdfd78af_0
// R packages: InteractionSet, mariner, marinerdata, strawr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MARINER_LOOP_MERGING_AND_REPLICATE_COMPARISON {
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
    .bm_deps <- c("InteractionSet", "mariner", "marinerdata", "strawr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    library(mariner)
    
    ## BEDPE-formatted files (read from working directory as requested)
    bedpeFiles <- c(
        "FS_5kbLoops.txt",
        "WT_5kbLoops.txt"
    )
    names(bedpeFiles) <- c("FS", "WT")
    
    ## Read as list of GInteractions
    giList <-
        lapply(bedpeFiles, read.table, header=TRUE) |>
        lapply(as_ginteractions)
    
    lapply(giList, summary)
    
    mgi <- mergePairs(
        x=giList,
        radius=10e3,
        column="APScoreAvg",
        selectMax=TRUE
    )
    mgi
    
    # Inspect specific clustered interaction
    if (length(mgi) >= 12772) {
        mgi[12772]
        clusters(mgi[12772])
    } else if (length(mgi) > 0) {
        mgi[1]
        clusters(mgi[1])
    }
    
    ## List the input sources
    sources(mgi)
    
    ## Interactions unique to each source
    sets(mgi) |> lapply(summary)
    
    ## Interactions shared by both sources
    shared_interactions <- sets(x=mgi, include=sources(mgi))
    shared_interactions
    
    ## Write meaningful output files
    # 1. Save the complete MergedGInteractions object as RDS
    saveRDS(mgi, file = "merged_interactions.rds")
    
    # 2. Save shared interactions as a CSV table
    shared_df <- as.data.frame(shared_interactions)
    write.csv(shared_df, file = "shared_interactions.csv", row.names = FALSE)
    
    # 3. Save unique interactions for each source set as CSV tables
    unique_sets <- sets(mgi)
    for (set_name in names(unique_sets)) {
        unique_df <- as.data.frame(unique_sets[[set_name]])
        write.csv(unique_df, file = paste0("unique_interactions_", set_name, ".csv"), row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_MARINER_LOOP_MERGING_AND_REPLICATE_COMPARISON":',
        paste0('        mariner: ', as.character(packageVersion("mariner")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_loop_merging_and_replicate_comparison.csv versions.yml
    """
}

workflow BIOC_MARINER_LOOP_MERGING_AND_REPLICATE_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ FS_5kbLoops.txt, WT_5kbLoops.txt ] ]

    main:
    BIOC_MARINER_LOOP_MERGING_AND_REPLICATE_COMPARISON(ch_input)

    emit:
    tables   = BIOC_MARINER_LOOP_MERGING_AND_REPLICATE_COMPARISON.out.tables
    plots    = BIOC_MARINER_LOOP_MERGING_AND_REPLICATE_COMPARISON.out.plots
    objects  = BIOC_MARINER_LOOP_MERGING_AND_REPLICATE_COMPARISON.out.objects
    versions = BIOC_MARINER_LOOP_MERGING_AND_REPLICATE_COMPARISON.out.versions
}
