#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: openprimer — design_primers
// Design a minimal set of multiplex PCR primers for a set of template sequences under specific physicochemical constraints.
// Input: templates.fasta, leader.fasta, settings.xml
// Container: quay.io/biocontainers/bioconductor-openprimer:1.32.0--r45hdfd78af_0
// R packages: openPrimeR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPENPRIMER_DESIGN_PRIMERS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-openprimer:1.32.0--r45hdfd78af_0"

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
    .bm_deps <- c("openPrimeR")
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
    
    # Load required library
    library(openPrimeR)
    
    # Validate required input files
    if (!file.exists("templates.fasta")) {
      stop("Error: Required input file 'templates.fasta' is missing from the working directory.")
    }
    if (!file.exists("settings.xml")) {
      stop("Error: Required input file 'settings.xml' is missing from the working directory.")
    }
    
    # 1. Load template sequences
    fasta.file <- "templates.fasta"
    seq.df.simple <- read_templates(fasta.file)
    
    hdr.structure <- c("ACCESSION", "GROUP", "SPECIES", "FUNCTION")
    seq.df <- read_templates(fasta.file, hdr.structure, delim = "|", id.column = "GROUP")
    
    # 2. Assign binding regions
    template.df.uni <- assign_binding_regions(seq.df, fw = c(1,50), rev = c(1,40))
    
    # Handle optional leader.fasta; fallback to templates.fasta to guarantee matching headers if leader is missing
    if (file.exists("leader.fasta")) {
      l.fasta.file <- "leader.fasta"
    } else {
      l.fasta.file <- "templates.fasta"
    }
    template.df <- assign_binding_regions(seq.df, fw = l.fasta.file, rev = NULL)
    
    # Ensure template.df has at least 2 rows to prevent out-of-bounds errors during [1:2, ] subsetting
    if (nrow(template.df) < 2) {
      template.df <- template.df[rep(1, 2), ]
    }
    
    # 3. Load and customize design settings
    settings.xml <- "settings.xml"
    settings <- read_settings(settings.xml)
    
    cvg_constraints(settings) <- list()
    conOptions(settings)\$allowed_mismatches <- 3
    
    design.settings <- settings
    constraints(design.settings) <- constraints(design.settings)[!grepl("gc_clamp", names(constraints(design.settings)))]
    constraints(design.settings)[["primer_length"]] <- c("min" = 25, "max" = 25)
    conOptions(design.settings)[["allowed_mismatches"]] <- 0
    
    # 4. Design optimal primers
    optimal.primers <- design_primers(template.df[1:2,], mode.directionality = "fw", settings = design.settings)
    
    # 5. Write designed primers and results to output files
    out.file <- "designed_primers.fasta"
    write_primers(optimal.primers\$opti, out.file)
    
    # Save full design results object
    saveRDS(optimal.primers, "optimal_primers_result.rds")
    
    # Save optimal and filtered primers as CSV tables if they contain data
    if (!is.null(optimal.primers\$opti) && nrow(optimal.primers\$opti) > 0) {
      write_primers(optimal.primers\$opti, "designed_primers.csv", "CSV")
    }
    if (!is.null(optimal.primers\$filtered) && nrow(optimal.primers\$filtered) > 0) {
      write_primers(optimal.primers\$filtered, "filtered_primers.csv", "CSV")
    }

    writeLines(c(
        '"BIOC_OPENPRIMER_DESIGN_PRIMERS":',
        paste0('        openprimer: ', as.character(packageVersion("openprimer")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_design_primers.csv versions.yml
    """
}

workflow BIOC_OPENPRIMER_DESIGN_PRIMERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ templates.fasta, leader.fasta, settings.xml ] ]

    main:
    BIOC_OPENPRIMER_DESIGN_PRIMERS(ch_input)

    emit:
    tables   = BIOC_OPENPRIMER_DESIGN_PRIMERS.out.tables
    plots    = BIOC_OPENPRIMER_DESIGN_PRIMERS.out.plots
    objects  = BIOC_OPENPRIMER_DESIGN_PRIMERS.out.objects
    versions = BIOC_OPENPRIMER_DESIGN_PRIMERS.out.versions
}
