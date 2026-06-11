#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ontoProc — import_and_visualize_owl_ontology
// Import an OWL ontology from a URL, cache it, parse it into an ontology index, and visualize a subset of terms.
// Input: url
// Container: quay.io/biocontainers/bioconductor-ontoproc:2.4.0--r45hdfd78af_0
// R packages: ontoProc
// Bioconductor: 3.20 | R: 4.4
// Requires: ontoProc
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Cache the OWL file locally using owl2cache
//  * 2. [Visualization & Output] Read and clean the OWL file to remove known problematic
//  * 3. [Visualization & Output] Parse the OWL file into an ontology index using
//  * 4. [Visualization & Output] Visualize selected terms using onto_plot2

nextflow.enable.dsl = 2

process BIOC_ONTOPROC_IMPORT_AND_VISUALIZE_OWL_ONTOLOGY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("ontoProc")
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
        library(ontoProc)
        
        # Read the URL from the input file 'url' in the working directory
        if (!file.exists("url")) {
          stop("Error: Input file 'url' containing the ontology URL is missing from the working directory.")
        }
        
        url_str <- trimws(readLines("url", warn = FALSE)[1])
        
        # --- Cache the OWL file locally using owl2cache ---
        clont_path = owl2cache(url=url_str)
        
        # --- Read and clean the OWL file to remove known problematic ---
        tmp = readLines(clont_path)
        
        bad = grep("STATO_0000416", tmp)[1:2]
        bad = bad[!is.na(bad)]
        if (length(bad) > 0) {
          tmp = tmp[-bad]
        }
        
        bad = grep("STATO_0000663", tmp)[1:2]
        bad = bad[!is.na(bad)]
        if (length(bad) > 0) {
          tmp = tmp[-bad]
        }
        
        tf = tempfile()
        writeLines(tmp, tf)
        
        # --- Parse the OWL file into an ontology index using ---
        cle = setup_entities2(tf)
        
        # Save the parsed ontology index as an RDS object
        saveRDS(cle, "parsed_ontology.rds")
        
        # --- Visualize selected terms using onto_plot2 ---
        # Documented selection of terms
        sel = c("CL_0000492", "CL_0001054", "CL_0000236", "CL_0000625", "CL_0000576", "CL_0000623", "CL_0000451", "CL_0000556")
        
        # If the input ontology is not Cell Ontology, the documented terms might not exist.
        # Fallback to a subset of existing terms in the ontology to ensure the plot is generated.
        intersecting_terms <- intersect(sel, names(cle\$name))
        if (length(intersecting_terms) == 0) {
          sel <- head(names(cle\$name), 8)
        } else {
          sel <- intersecting_terms
        }
        
        # Save the visualization to a PDF file
        pdf("ontology_visualization.pdf", width=10, height=8)
        tryCatch({
          onto_plot2(cle, sel)
        }, error = function(e) {
          warning("Plotting failed with error: ", e\$message)
        })
        dev.off()

    writeLines(c(
        '"BIOC_ONTOPROC_IMPORT_AND_VISUALIZE_OWL_ONTOLOGY":',
        paste0('    ontoProc: ', as.character(packageVersion('ontoProc')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_import_and_visualize_owl_ontology.csv versions.yml
    """
}

workflow BIOC_ONTOPROC_IMPORT_AND_VISUALIZE_OWL_ONTOLOGY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ url ] ]

    main:
    BIOC_ONTOPROC_IMPORT_AND_VISUALIZE_OWL_ONTOLOGY(ch_input)

    emit:
    tables   = BIOC_ONTOPROC_IMPORT_AND_VISUALIZE_OWL_ONTOLOGY.out.tables
    plots    = BIOC_ONTOPROC_IMPORT_AND_VISUALIZE_OWL_ONTOLOGY.out.plots
    objects  = BIOC_ONTOPROC_IMPORT_AND_VISUALIZE_OWL_ONTOLOGY.out.objects
    versions = BIOC_ONTOPROC_IMPORT_AND_VISUALIZE_OWL_ONTOLOGY.out.versions
}
