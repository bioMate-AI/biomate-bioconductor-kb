#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: triplex — triplex_search_and_visualization
// Search for intramolecular triplexes in a DNA sequence, visualize the alignments in text, 2D, or 3D, and export the results to GFF3 and FASTA formats.
// Input: DNAString, BSgenome
// Container: quay.io/biocontainers/bioconductor-triplex:1.50.0--r45h01b2380_0
// R packages: Biostrings, rtracklayer, triplex
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, rtracklayer, triplex
// Visualizations: coverage plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the triplex package and define the target DNA sequence
//  * 2. [Core Analysis] Search for triplexes using triplex.search with optional filtering parameters (type, min_len, max_len, iso_pen, min_score)
//  * 3. [Core Analysis] Sort or subset the resulting TriplexViews object
//  * 4. [Visualization & Output] Visualize the triplexes using triplex.alignment, triplex.diagram, or triplex.3D
//  * 5. [Visualization & Output] Convert the results to GRanges and export to GFF3 format
//  * 6. [Visualization & Output] Convert the results to DNAStringSet and export to FASTA format
//  * 7. [Visualization & Output] Plot statistics such as score distribution histograms and coverage plots

nextflow.enable.dsl = 2

process BIOC_TRIPLEX_TRIPLEX_SEARCH_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("Biostrings", "rtracklayer", "triplex")
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
    library(triplex)
    library(rtracklayer)
    library(Biostrings)
    
    # ==========================================
    # 1. Load User Input Files
    # ==========================================
    
    # Load DNAString input
    if (file.exists("DNAString.fa")) {
      seq <- readDNAStringSet("DNAString.fa")[[1]]
    } else if (file.exists("DNAString.txt")) {
      seq <- DNAString(paste(readLines("DNAString.txt"), collapse = ""))
    } else if (file.exists("DNAString")) {
      seq <- tryCatch({
        readDNAStringSet("DNAString")[[1]]
      }, error = function(e) {
        DNAString(paste(readLines("DNAString"), collapse = ""))
      })
    } else {
      stop("Required input file 'DNAString' (or DNAString.fa/txt) not found in the working directory.")
    }
    
    # Load BSgenome input
    if (file.exists("BSgenome.rds")) {
      bs_genome <- readRDS("BSgenome.rds")
    } else if (file.exists("BSgenome.fa")) {
      bs_genome <- readDNAStringSet("BSgenome.fa")
    } else if (file.exists("BSgenome")) {
      bs_genome <- tryCatch({
        readRDS("BSgenome")
      }, error = function(e) {
        readDNAStringSet("BSgenome")
      })
    } else {
      stop("Required input file 'BSgenome' (or BSgenome.rds/fa) not found in the working directory.")
    }
    
    # Extract target chromosome/sequence from the loaded genome object
    if (inherits(bs_genome, "BSgenome")) {
      chrom_names <- seqnames(bs_genome)
      if ("chrX" %in% chrom_names) {
        chr_seq <- bs_genome[["chrX"]]
      } else {
        chr_seq <- bs_genome[[chrom_names[1]]]
      }
    } else if (inherits(bs_genome, "DNAStringSet")) {
      idx <- grep("chrX", names(bs_genome))
      if (length(idx) > 0) {
        chr_seq <- bs_genome[[idx[1]]]
      } else {
        chr_seq <- bs_genome[[1]]
      }
    } else if (inherits(bs_genome, "DNAString")) {
      chr_seq <- bs_genome
    } else {
      stop("Unknown format for BSgenome input.")
    }
    
    # Limit to the first 100,000 bp as in the documented workflow
    target_len <- min(100000, length(chr_seq))
    chr_seq <- chr_seq[1:target_len]
    
    
    # ==========================================
    # 2. Search and Analyze (DNAString Sequence)
    # ==========================================
    
    # Run searches with various parameters as documented
    triplex.search(seq)
    triplex.search(seq, type=1)
    triplex.search(seq, min_len=10, max_len=20)
    triplex.search(seq, iso_pen=2)
    triplex.search(seq, min_score=14)
    
    # Perform the main search and store results
    t <- triplex.search(seq)
    t
    
    # Save TriplexViews object
    saveRDS(t, "triplex_views_seq.rds")
    
    # Alignments and Visualizations
    if (length(t) > 0) {
      triplex.alignment(t[1])
      
      pdf("triplex_diagram_seq.pdf")
      triplex.diagram(t[1])
      dev.off()
      
      tryCatch({
        triplex.3D(t[1])
      }, error = function(e) {
        warning("triplex.3D failed (likely due to headless environment): ", e\$message)
      })
    }
    
    # Convert and Export to GFF3
    gr <- as(t, "GRanges")
    gr
    export(gr, "test_seq.gff", version="3")
    
    # Convert and Export to FASTA
    dss <- as(t, "DNAStringSet")
    dss
    writeXStringSet(dss, file="test_seq.fa", format="fasta")
    
    
    # ==========================================
    # 3. Search and Analyze (Genome Sequence)
    # ==========================================
    
    # Search within the genomic sequence
    t <- triplex.search(chr_seq, min_score=17, min_len=8)
    t
    
    # Save TriplexViews object
    saveRDS(t, "triplex_views_genome.rds")
    
    # Sort results by score
    ts <- t[order(score(t), decreasing=TRUE)]
    ts
    
    # Alignments and Visualizations for sorted results
    if (length(ts) > 0) {
      pdf("triplex_diagram_genome.pdf")
      triplex.diagram(ts[1])
      dev.off()
      
      tryCatch({
        triplex.3D(ts[1])
      }, error = function(e) {
        warning("triplex.3D failed (likely due to headless environment): ", e\$message)
      })
      
      triplex.alignment(ts[1])
    }
    
    # Export genome search results
    export(as(t, "GRanges"), "test_genome.gff", version="3")
    writeXStringSet(as(t, "DNAStringSet"), file="test_genome.fa", format="fasta")
    
    
    # ==========================================
    # 4. Plot Statistics
    # ==========================================
    
    if (length(t) > 0) {
      # Score distribution histogram
      pdf("score_histogram.pdf")
      hist(score(t), breaks=20)
      dev.off()
      
      # Coverage plot along the analyzed sequence
      pdf("coverage_plot.pdf")
      plot(coverage(ts[0:length(t)]), type="s", col="grey75")
      dev.off()
    }

    writeLines(c(
        '"BIOC_TRIPLEX_TRIPLEX_SEARCH_AND_VISUALIZATION":',
        paste0('    triplex: ', as.character(packageVersion('triplex')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_triplex_search_and_visualization.csv versions.yml
    """
}

workflow BIOC_TRIPLEX_TRIPLEX_SEARCH_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ DNAString, BSgenome ] ]

    main:
    BIOC_TRIPLEX_TRIPLEX_SEARCH_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_TRIPLEX_TRIPLEX_SEARCH_AND_VISUALIZATION.out.tables
    plots    = BIOC_TRIPLEX_TRIPLEX_SEARCH_AND_VISUALIZATION.out.plots
    objects  = BIOC_TRIPLEX_TRIPLEX_SEARCH_AND_VISUALIZATION.out.objects
    versions = BIOC_TRIPLEX_TRIPLEX_SEARCH_AND_VISUALIZATION.out.versions
}
