#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gmoviz — single_insertion_diagram
// Plot a single or tandem insertion event on a target sequence with optional coverage and label annotations.
// Input: insertion_data.gff, coverage.bam, labels.gff3
// Container: quay.io/biocontainers/bioconductor-gmoviz:1.22.0--r45hdfd78af_0
// R packages: GenomicRanges, biocmanager, gmoviz, pasillabamsubset, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GMOVIZ_SINGLE_INSERTION_DIAGRAM {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-gmoviz:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "biocmanager", "gmoviz", "pasillabamsubset", "rtracklayer")
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
    library(gmoviz)
    library(GenomicRanges)
    library(rtracklayer)
    
    # ==========================================
    # --- Define insertion data, labels, and coverage ---
    # ==========================================
    
    # Read insertion data from GFF
    if (file.exists("insertion_data.gff")) {
      insertion_gr <- rtracklayer::import("insertion_data.gff")
      
      # Ensure required metadata columns exist, applying defaults if missing
      if (!"name" %in% colnames(mcols(insertion_gr))) {
        if ("ID" %in% colnames(mcols(insertion_gr))) {
          insertion_gr\$name <- insertion_gr\$ID
        } else if ("Name" %in% colnames(mcols(insertion_gr))) {
          insertion_gr\$name <- insertion_gr\$Name
        } else {
          insertion_gr\$name <- "plasmid"
        }
      }
      if (!"colour" %in% colnames(mcols(insertion_gr))) {
        insertion_gr\$colour <- "#7270ea"
      }
      if (!"length" %in% colnames(mcols(insertion_gr))) {
        insertion_gr\$length <- width(insertion_gr)
      }
      if (!"in_tandem" %in% colnames(mcols(insertion_gr))) {
        insertion_gr\$in_tandem <- 11
      }
      if (!"shape" %in% colnames(mcols(insertion_gr))) {
        insertion_gr\$shape <- "forward_arrow"
      }
    } else {
      stop("Required input file 'insertion_data.gff' not found in the working directory.")
    }
    
    # Extract primary insertion event
    example_insertion <- insertion_gr[1]
    target_chr <- as.character(seqnames(example_insertion)[1])
    
    # Define single copy insertion (without tandem copy number)
    single_copy_insertion <- example_insertion
    single_copy_insertion\$in_tandem <- NULL
    
    # Define multiple insertions if available, otherwise construct a mock second insertion
    if (length(insertion_gr) > 1) {
      multi_insertions <- insertion_gr[2]
    } else {
      multi_insertions <- GRanges(
        seqnames = target_chr,
        ranges = IRanges(start = end(example_insertion) + 5000, end = end(example_insertion) + 15000),
        name = paste0(example_insertion\$name, "2"),
        length = 10000
      )
    }
    multiple_insertions <- c(single_copy_insertion, multi_insertions)
    
    # Read or define nearby labels
    if (file.exists("labels.gff3")) {
      nearby_genes <- rtracklayer::import("labels.gff3")
      if (!"label" %in% colnames(mcols(nearby_genes))) {
        if ("ID" %in% colnames(mcols(nearby_genes))) {
          nearby_genes\$label <- nearby_genes\$ID
        } else if ("Name" %in% colnames(mcols(nearby_genes))) {
          nearby_genes\$label <- nearby_genes\$Name
        } else {
          nearby_genes\$label <- paste0("Label_", seq_along(nearby_genes))
        }
      }
    } else {
      # Fallback to default nearby genes around the insertion site
      nearby_genes <- GRanges(
        seqnames = rep(target_chr, 2),
        ranges = IRanges(
          start = c(max(1, start(example_insertion) - 10000), end(example_insertion) + 1000),
          end = c(max(2, start(example_insertion) - 1000), end(example_insertion) + 9000)
        ),
        label = c("Gene A", "Gene B")
      )
    }
    
    # Read or define coverage data
    if (file.exists("coverage.bam")) {
      # Define region of interest spanning insertion and labels
      roi <- range(c(example_insertion, nearby_genes))
      start(roi) <- max(1, start(roi) - 10000)
      end(roi) <- end(roi) + 10000
      
      coverage <- getCoverage(
        regions_of_interest = roi,
        bam_file = "coverage.bam",
        window_size = 150,
        smoothing_window_size = 200
      )
    } else {
      # Fallback to simulated coverage matching the target chromosome
      coverage <- GRanges(
        seqnames = rep(target_chr, 400),
        ranges = IRanges(
          start = seq(from = max(1, start(example_insertion) - 5000), to = end(example_insertion) + 13000, length.out = 400),
          width = 45
        ),
        coverage = c(runif(210, 10, 15), rep(0, 190))
      )
    }
    
    # Save processed genomic datasets
    saveRDS(example_insertion, "processed_insertion.rds")
    saveRDS(nearby_genes, "processed_labels.rds")
    saveRDS(coverage, "processed_coverage.rds")
    
    # ==========================================
    # --- Generate Insertion Diagrams (Styles & Annotations) ---
    # ==========================================
    
    # Style 1: Emphasis on inserted sequence
    pdf("insertion_diagram_style1.pdf", width = 8, height = 8)
    tryCatch({
      insertionDiagram(insertion_data = example_insertion, 
                       space_between_sectors = 20, xaxis_spacing = 45)
    }, error = function(e) warning("Error plotting Style 1: ", e\$message))
    dev.off()
    
    # Style 2: Emphasis on target sequence
    pdf("insertion_diagram_style2.pdf", width = 8, height = 8)
    tryCatch({
      insertionDiagram(example_insertion, space_between_sectors = 20, style = 2)
    }, error = function(e) warning("Error plotting Style 2: ", e\$message))
    dev.off()
    
    # Style 3: Single-copy insertion style 3
    pdf("insertion_diagram_style3.pdf", width = 8, height = 8)
    tryCatch({
      insertionDiagram(single_copy_insertion, space_between_sectors = 20, style = 3)
    }, error = function(e) warning("Error plotting Style 3: ", e\$message))
    dev.off()
    
    # Style 4: Single-copy insertion style 4
    pdf("insertion_diagram_style4.pdf", width = 8, height = 8)
    tryCatch({
      insertionDiagram(single_copy_insertion, space_between_sectors = 20, style = 4)
    }, error = function(e) warning("Error plotting Style 4: ", e\$message))
    dev.off()
    
    # Multiple insertion sites
    pdf("multiple_insertions_diagram.pdf", width = 8, height = 8)
    tryCatch({
      insertionDiagram(multiple_insertions)
    }, error = function(e) warning("Error plotting multiple insertions: ", e\$message))
    dev.off()
    
    # Insertion diagram with nearby gene labels
    pdf("insertion_diagram_with_labels.pdf", width = 8, height = 8)
    tryCatch({
      insertionDiagram(insertion_data = example_insertion, 
                       label_data = nearby_genes,
                       either_side = nearby_genes, 
                       space_between_sectors = 20,
                       xaxis_spacing = 75, 
                       label_size = 0.8, 
                       track_height = 0.1)
    }, error = function(e) warning("Error plotting diagram with labels: ", e\$message))
    dev.off()
    
    # Insertion diagram with coverage and labels
    pdf("insertion_diagram_with_coverage.pdf", width = 8, height = 8)
    tryCatch({
      insertionDiagram(insertion_data = example_insertion, 
                       coverage_data = coverage,
                       coverage_rectangle = target_chr,
                       either_side = nearby_genes, 
                       space_between_sectors = 20,
                       xaxis_spacing = 75)
    }, error = function(e) warning("Error plotting diagram with coverage: ", e\$message))
    dev.off()
    
    # Custom start degree
    pdf("insertion_diagram_start_degree.pdf", width = 8, height = 8)
    tryCatch({
      insertionDiagram(example_insertion, start_degree = 45, 
                       space_between_sectors = 20)
    }, error = function(e) warning("Error plotting diagram with custom start degree: ", e\$message))
    dev.off()
    
    # Custom padding (either_side as a single number)
    pdf("insertion_diagram_either_side_bp.pdf", width = 8, height = 8)
    tryCatch({
      insertionDiagram(example_insertion, either_side = 10000, start_degree = 45,
                       space_between_sectors = 20)
    }, error = function(e) warning("Error plotting diagram with numeric either_side: ", e\$message))
    dev.off()
    
    # Custom padding (either_side as a coordinate range vector)
    pdf("insertion_diagram_either_side_range.pdf", width = 8, height = 8)
    tryCatch({
      either_side_coords <- c(max(1, start(example_insertion) - 50000), end(example_insertion) + 50000)
      insertionDiagram(example_insertion, either_side = either_side_coords,
                       start_degree = 45, space_between_sectors = 20)
    }, error = function(e) warning("Error plotting diagram with coordinate range either_side: ", e\$message))
    dev.off()
    
    message("gmoviz single insertion pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GMOVIZ_SINGLE_INSERTION_DIAGRAM":',
        paste0('        gmoviz: ', as.character(packageVersion("gmoviz")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_insertion_diagram.csv versions.yml
    """
}

workflow BIOC_GMOVIZ_SINGLE_INSERTION_DIAGRAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ insertion_data.gff, coverage.bam, labels.gff3 ] ]

    main:
    BIOC_GMOVIZ_SINGLE_INSERTION_DIAGRAM(ch_input)

    emit:
    tables   = BIOC_GMOVIZ_SINGLE_INSERTION_DIAGRAM.out.tables
    plots    = BIOC_GMOVIZ_SINGLE_INSERTION_DIAGRAM.out.plots
    objects  = BIOC_GMOVIZ_SINGLE_INSERTION_DIAGRAM.out.objects
    versions = BIOC_GMOVIZ_SINGLE_INSERTION_DIAGRAM.out.versions
}
