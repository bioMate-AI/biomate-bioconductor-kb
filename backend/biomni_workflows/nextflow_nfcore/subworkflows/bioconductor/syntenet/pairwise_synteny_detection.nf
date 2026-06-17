#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: syntenet — pairwise_synteny_detection
// Detect and parse intra- and inter-species syntenic blocks and anchor pairs.
// Input: FASTA files, GFF/GTF files, DIAMOND/BLAST tabular output files
// Container: quay.io/biocontainers/bioconductor-syntenet:1.12.0--r45ha27e39d_0
// R packages: Biostrings, GenomicRanges, syntenet
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYNTENET_PAIRWISE_SYNTENY_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-syntenet:1.12.0--r45ha27e39d_0"

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
    .bm_deps <- c("Biostrings", "GenomicRanges", "syntenet")
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
    library(syntenet)
    library(GenomicRanges)
    library(Biostrings)
    
    # Helper function to read DIAMOND/BLAST tabular files robustly
    read_diamond_file <- function(path) {
      if (!file.exists(path)) {
        stop(paste("Required DIAMOND/BLAST file not found in the working directory:", path))
      }
      df <- read.table(path, header = FALSE, sep = "\t", stringsAsFactors = FALSE)
      colnames(df) <- c("query", "db", "perc_identity", "length", "mismatches",
                        "gap_open", "qstart", "qend", "tstart", "tend", "evalue", "bitscore")
      return(df)
    }
    
    # ==========================================
    # --- Preprocess inputs using process_input() ---
    # ==========================================
    message("Reading FASTA files from the working directory...")
    all_seqs <- fasta2AAStringSetlist(".")
    
    message("Reading GFF/GTF files from the working directory...")
    all_annots <- gff2GRangesList(".")
    
    # Perform input checks
    message("Checking input data validity...")
    if (!check_input(all_seqs, all_annots)) {
      stop("Input check failed! Please ensure sequence names match gene IDs and there are no multiple isoforms.")
    }
    
    # Process inputs
    message("Processing input sequences and annotations...")
    pdata_all <- process_input(all_seqs, all_annots)
    
    # Extract specific annotations for the workflow
    # We assume the files are named such that the list elements are "Scerevisiae", "Olucimarinus", and "OspRCC809"
    scerevisiae_annot <- pdata_all\$annotation["Scerevisiae"]
    pdata <- list(
      annotation = pdata_all\$annotation[c("Olucimarinus", "OspRCC809")]
    )
    
    # Load DIAMOND/BLAST tabular files from the working directory
    message("Loading DIAMOND/BLAST tabular files...")
    scerevisiae_diamond <- list(
      Scerevisiae_Scerevisiae = read_diamond_file("Scerevisiae_Scerevisiae.tsv")
    )
    
    algae_inter <- list(
      Olucimarinus_OspRCC809 = read_diamond_file("Olucimarinus_OspRCC809.tsv"),
      OspRCC809_Olucimarinus = read_diamond_file("OspRCC809_Olucimarinus.tsv")
    )
    
    # ==========================================================
    # --- Detect intraspecies synteny using intraspecies_synteny() ---
    # ==========================================================
    message("Detecting intraspecies synteny for S. cerevisiae...")
    intra_syn <- intraspecies_synteny(scerevisiae_diamond, scerevisiae_annot)
    
    # ==========================================================
    # --- Parse intraspecies collinearity files using ---
    # ==========================================================
    message("Parsing intraspecies collinearity...")
    anchors <- parse_collinearity(intra_syn)
    blocks <- parse_collinearity(intra_syn, as = "blocks")
    intrasyn_all <- parse_collinearity(intra_syn, as = "all")
    
    # ==========================================================
    # --- Set up bidirectional comparisons using ---
    # ==========================================================
    message("Setting up bidirectional comparisons...")
    comp <- data.frame(
      query = "Olucimarinus",
      db = "OspRCC809"
    )
    comp_bi <- make_bidirectional(comp)
    
    # ==========================================================
    # --- Detect interspecies synteny using interspecies_synteny() ---
    # ==========================================================
    message("Detecting interspecies synteny...")
    intersyn <- interspecies_synteny(algae_inter, pdata\$annotation)
    
    # ==========================================================
    # --- Parse interspecies collinearity files using ---
    # ==========================================================
    message("Parsing interspecies collinearity...")
    algae_anchors <- parse_collinearity(intersyn)
    algae_blocks <- parse_collinearity(intersyn, as = "blocks")
    algae_all <- parse_collinearity(intersyn, as = "all")
    
    # ==========================================
    # Write named output files for results
    # ==========================================
    message("Writing output files...")
    write.csv(anchors, "intraspecies_anchors.csv", row.names = FALSE)
    write.csv(blocks, "intraspecies_blocks.csv", row.names = FALSE)
    write.csv(intrasyn_all, "intraspecies_all.csv", row.names = FALSE)
    write.csv(algae_anchors, "algae_anchors.csv", row.names = FALSE)
    write.csv(algae_blocks, "algae_blocks.csv", row.names = FALSE)
    write.csv(algae_all, "algae_all.csv", row.names = FALSE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_SYNTENET_PAIRWISE_SYNTENY_DETECTION":',
        paste0('        syntenet: ', as.character(packageVersion("syntenet")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_synteny_detection.csv versions.yml
    """
}

workflow BIOC_SYNTENET_PAIRWISE_SYNTENY_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ FASTA files, GFF/GTF files, DIAMOND/BLAST tabular output files ] ]

    main:
    BIOC_SYNTENET_PAIRWISE_SYNTENY_DETECTION(ch_input)

    emit:
    tables   = BIOC_SYNTENET_PAIRWISE_SYNTENY_DETECTION.out.tables
    plots    = BIOC_SYNTENET_PAIRWISE_SYNTENY_DETECTION.out.plots
    objects  = BIOC_SYNTENET_PAIRWISE_SYNTENY_DETECTION.out.objects
    versions = BIOC_SYNTENET_PAIRWISE_SYNTENY_DETECTION.out.versions
}
