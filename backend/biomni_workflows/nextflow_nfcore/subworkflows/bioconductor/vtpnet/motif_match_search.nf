#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vtpnet — motif_match_search
// Generate custom motif-match ranges across the genome using parallelized PWM matching.
// Input: motif_query.txt, reference_genome.pkg
// Container: quay.io/biocontainers/bioconductor-vtpnet:0.50.0--r45hdfd78af_0
// R packages: BSgenome, Biostrings, GenomicRanges, MotifDb, doParallel, foreach, genome_pkg
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VTPNET_MOTIF_MATCH_SEARCH {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-vtpnet:0.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome", "Biostrings", "GenomicRanges", "MotifDb", "doParallel", "foreach", "genome_pkg")
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
    
    # Load required libraries
    library(foreach)
    library(doParallel)
    library(MotifDb)
    library(Biostrings)
    library(GenomicRanges)
    library(BSgenome)
    
    # Read user inputs
    if (!file.exists("motif_query.txt")) {
      stop("Required input file 'motif_query.txt' not found in the working directory.")
    }
    if (!file.exists("reference_genome.pkg")) {
      stop("Required input file 'reference_genome.pkg' not found in the working directory.")
    }
    
    tf_name <- trimws(readLines("motif_query.txt", warn = FALSE)[1])
    genome_pkg <- trimws(readLines("reference_genome.pkg", warn = FALSE)[1])
    
    # Load the user-specified BSgenome package and retrieve the genome object
    library(genome_pkg, character.only = TRUE)
    Hsapiens <- getBSgenome(genome_pkg)
    
    # Register parallel backend
    registerDoParallel(cores=12)
    
    # Retrieve chromosome names
    sn = seqnames(Hsapiens)[1:24]
    
    # Query MotifDb for the target transcription factor
    pax4 = query(MotifDb, tf_name)[[1]]
    
    # Run parallelized matchPWM across chromosomes
    ans = foreach(i=1:24) %dopar% {
     cat(i)
     subj = Hsapiens[[ sn[i] ]]
     matchPWM( pax4, subj, "75%" )
    }
    
    # Combine results into a single GRanges object
    pax4_75 = 
     do.call(c, lapply(1:length(ans), function(x) 
      {GRanges(sn[x], as(ans[[x]], "IRanges"))}))
    
    # Save outputs in multiple formats
    save(pax4_75, file="pax4_75.rda")
    saveRDS(pax4_75, file="pax4_75.rds")
    write.csv(as.data.frame(pax4_75), file="pax4_75.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_VTPNET_MOTIF_MATCH_SEARCH":',
        paste0('        vtpnet: ', as.character(packageVersion("vtpnet")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motif_match_search.csv versions.yml
    """
}

workflow BIOC_VTPNET_MOTIF_MATCH_SEARCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ motif_query.txt, reference_genome.pkg ] ]

    main:
    BIOC_VTPNET_MOTIF_MATCH_SEARCH(ch_input)

    emit:
    tables   = BIOC_VTPNET_MOTIF_MATCH_SEARCH.out.tables
    plots    = BIOC_VTPNET_MOTIF_MATCH_SEARCH.out.plots
    objects  = BIOC_VTPNET_MOTIF_MATCH_SEARCH.out.objects
    versions = BIOC_VTPNET_MOTIF_MATCH_SEARCH.out.versions
}
