#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rprimer — standard_oligo_assay_design
// Design degenerate primers, probes, and qPCR assays from a multiple DNA sequence alignment using the default ambiguous strategy.
// Input: example_alignment.txt
// Container: quay.io/biocontainers/bioconductor-rprimer:1.14.0--r45hdfd78af_0
// R packages: Biostrings, kableExtra, rprimer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_RPRIMER_STANDARD_OLIGO_ASSAY_DESIGN {
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
    .bm_deps <- c("Biostrings", "kableExtra", "rprimer")
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
    library(rprimer)
    library(Biostrings)
    
    # Define input file path (must be in the working directory)
    filepath <- "example_alignment.txt"
    
    if (!file.exists(filepath)) {
      stop(paste("Error: Input file", filepath, "not found in the working directory."))
    }
    
    # Start PDF device to capture all visual plots
    pdf("rprimer_workflow_plots.pdf", width = 11, height = 8.5)
    
    # --- Import alignment using readDNAMultipleAlignment() ---
    myAlignment <- readDNAMultipleAlignment(filepath, format = "fasta")
    
    # --- Generate consensus profile using consensusProfile() ---
    myConsensusProfile <- consensusProfile(myAlignment, ambiguityThreshold = 0.05)
    saveRDS(myConsensusProfile, "myConsensusProfile.rds")
    
    # Visualize consensus profile
    plotData(myConsensusProfile)
    
    # Subset consensus profile for a specific region
    selection <- myConsensusProfile[
      myConsensusProfile\$position >= 5000 & myConsensusProfile\$position <= 5800, 
    ]
    plotData(selection)
    
    # --- Design oligos using designOligos() ---
    myOligos <- designOligos(myConsensusProfile)
    saveRDS(myOligos, "myOligos.rds")
    
    # Inspect properties of the first designed oligo
    myOligos\$sequence[[1]]
    myOligos\$gcContent[[1]]
    myOligos\$tm[[1]]
    
    # Visualize designed oligos
    plotData(myOligos)
    
    # Select the best scoring oligos
    bestOligoScore <- min(myOligos\$score)
    oligoSelection <- myOligos[myOligos\$score == bestOligoScore, ]
    
    # Identify and plot the binding region of the first selected oligo
    bindingRegion <- myConsensusProfile[
      myConsensusProfile\$position >= oligoSelection[1, ]\$start & 
        myConsensusProfile\$position <= oligoSelection[1, ]\$end,
    ]
    plotData(bindingRegion, type = "nucleotide")
    
    # --- Design assays using designAssays() ---
    myAssays <- designAssays(myOligos)
    saveRDS(myAssays, "myAssays.rds")
    
    # Visualize designed assays
    plotData(myAssays)
    
    # Select the best scoring assays
    bestAssayScore <- min(myAssays\$score)
    myAssaySelection <- myAssays[myAssays\$score == bestAssayScore, ]
    
    # Identify and highlight the amplicon region in the consensus profile
    from <- myAssaySelection[1, ]\$start
    to <- myAssaySelection[1, ]\$end
    plotData(myConsensusProfile, highlight = c(from, to))
    
    # Subset and plot the nucleotide distribution of the assay region
    myAssayRegion <- myConsensusProfile[
      myConsensusProfile\$position >= from & 
        myConsensusProfile\$position <= to, 
    ]
    plotData(myAssayRegion, type = "nucleotide")
    
    # Retrieve the consensus amplicon sequence
    consensus_sequence <- paste(myAssayRegion\$iupac, collapse = "")
    
    # --- Check matches against target sequences using checkMatch() ---
    oligoSelectionMatch <- checkMatch(oligoSelection[1:3, ], target = myAlignment)
    saveRDS(oligoSelectionMatch, "oligoSelectionMatch.rds")
    
    # Inspect mismatch IDs for the first checked oligo
    oligoSelectionMatch\$idOneMismatch[[1]]
    
    # Visualize match results
    plotData(oligoSelectionMatch)
    
    # Coerce oligos and assays to DNAStringSet objects
    as(myOligos[1:2, ], "DNAStringSet")
    as(myAssays[1:2, ], "DNAStringSet")
    
    # --- Export results to CSV, TXT, and FASTA formats ---
    write.csv(myAssays, file = "myAssays.csv", quote = FALSE, row.names = FALSE)
    write.table(myAssays, file = "myAssays.txt", quote = FALSE, row.names = FALSE)
    
    toFile <- as(myOligos[1:2, ], "DNAStringSet")
    writeXStringSet(toFile, file = "myOligos.txt")
    
    # Close the PDF device
    dev.off()

    writeLines(c(
        '"BIOC_RPRIMER_STANDARD_OLIGO_ASSAY_DESIGN":',
        paste0('        rprimer: ', as.character(packageVersion("rprimer")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_oligo_assay_design.csv versions.yml
    """
}

workflow BIOC_RPRIMER_STANDARD_OLIGO_ASSAY_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_alignment.txt ] ]

    main:
    BIOC_RPRIMER_STANDARD_OLIGO_ASSAY_DESIGN(ch_input)

    emit:
    tables   = BIOC_RPRIMER_STANDARD_OLIGO_ASSAY_DESIGN.out.tables
    plots    = BIOC_RPRIMER_STANDARD_OLIGO_ASSAY_DESIGN.out.plots
    objects  = BIOC_RPRIMER_STANDARD_OLIGO_ASSAY_DESIGN.out.objects
    versions = BIOC_RPRIMER_STANDARD_OLIGO_ASSAY_DESIGN.out.versions
}
