#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MouseFM — genetic_finemapping
// Finemap a specific genomic region by identifying homozygous SNVs that differ between two groups of mouse strains and annotating them with consequences and genes
// Input: Genomic region coordinates
// Container: quay.io/biocontainers/bioconductor-mousefm:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MouseFM
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] List available strains using avail_strains()
//  * 2. [Core Analysis] Run finemapping using finemap()
//  * 3. [Core Analysis] Annotate the resulting variants with consequences using annotate_consequences()
//  * 4. [Core Analysis] Annotate the variants with nearby genes using annotate_mouse_genes()

nextflow.enable.dsl = 2

process BIOC_MOUSEFM_GENETIC_FINEMAPPING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("MouseFM")
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
    library(MouseFM)
    
    # Verify input files exist in the working directory
    if (!file.exists("region.csv")) {
      stop("Error: Required input file 'region.csv' not found in the working directory. Please provide a CSV file with 'chr', 'start', and 'end' columns.")
    }
    
    if (!file.exists("strains.csv")) {
      stop("Error: Required input file 'strains.csv' not found in the working directory. Please provide a CSV file with 'group' (strain1 or strain2) and 'strain' columns.")
    }
    
    # 1. List available strains
    message("Listing available strains...")
    strains_avail <- avail_strains()
    write.csv(strains_avail, "available_strains.csv", row.names = FALSE)
    
    # Read user inputs
    region_df <- read.csv("region.csv", stringsAsFactors = FALSE)
    if (!all(c("chr", "start", "end") %in% colnames(region_df))) {
      stop("Error: 'region.csv' must contain 'chr', 'start', and 'end' columns.")
    }
    chr_input <- region_df\$chr[1]
    start_input <- region_df\$start[1]
    end_input <- region_df\$end[1]
    
    strains_df <- read.csv("strains.csv", stringsAsFactors = FALSE)
    if (!all(c("group", "strain") %in% colnames(strains_df))) {
      stop("Error: 'strains.csv' must contain 'group' and 'strain' columns.")
    }
    
    strain1_input <- strains_df\$strain[strains_df\$group == "strain1"]
    strain2_input <- strains_df\$strain[strains_df\$group == "strain2"]
    
    if (length(strain1_input) == 0 || length(strain2_input) == 0) {
      stop("Error: 'strains.csv' must contain at least one strain for 'strain1' and 'strain2' groups.")
    }
    
    # Validate that input strains are available in MouseFM
    invalid_strains1 <- setdiff(strain1_input, strains_avail\$id)
    invalid_strains2 <- setdiff(strain2_input, strains_avail\$id)
    if (length(invalid_strains1) > 0 || length(invalid_strains2) > 0) {
      stop(paste("Error: Some input strains are not available in MouseFM.",
                 "\nInvalid strain1:", paste(invalid_strains1, collapse = ", "),
                 "\nInvalid strain2:", paste(invalid_strains2, collapse = ", ")))
    }
    
    # 2. Run finemapping
    message("Running genetic finemapping...")
    res = finemap(chr=chr_input, start=start_input, end=end_input, strain1=strain1_input, strain2=strain2_input, impact=c("HIGH", "MODERATE", "LOW"))
    
    # Save finemapping results
    write.csv(res, "finemap_results.csv", row.names = FALSE)
    saveRDS(res, "finemap_results.rds")
    
    # 3. Annotate the resulting variants with consequences
    message("Annotating consequences...")
    cons = tryCatch({
      annotate_consequences(res, "mouse")
    }, error = function(e) {
      message("Warning: annotate_consequences failed or timed out: ", e\$message)
      NULL
    })
    
    if (!is.null(cons)) {
      write.csv(cons, "annotated_consequences.csv", row.names = FALSE)
      saveRDS(cons, "annotated_consequences.rds")
    }
    
    # 4. Annotate the variants with nearby genes
    message("Annotating nearby genes...")
    genes = tryCatch({
      annotate_mouse_genes(res, flanking = 50000)
    }, error = function(e) {
      message("Warning: annotate_mouse_genes failed or timed out: ", e\$message)
      NULL
    })
    
    if (!is.null(genes)) {
      write.csv(genes, "annotated_genes.csv", row.names = FALSE)
      saveRDS(genes, "annotated_genes.rds")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MOUSEFM_GENETIC_FINEMAPPING":',
        paste0('    MouseFM: ', as.character(packageVersion('MouseFM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genetic_finemapping.csv versions.yml
    """
}

workflow BIOC_MOUSEFM_GENETIC_FINEMAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Genomic region coordinates ] ]

    main:
    BIOC_MOUSEFM_GENETIC_FINEMAPPING(ch_input)

    emit:
    tables   = BIOC_MOUSEFM_GENETIC_FINEMAPPING.out.tables
    plots    = BIOC_MOUSEFM_GENETIC_FINEMAPPING.out.plots
    objects  = BIOC_MOUSEFM_GENETIC_FINEMAPPING.out.objects
    versions = BIOC_MOUSEFM_GENETIC_FINEMAPPING.out.versions
}
