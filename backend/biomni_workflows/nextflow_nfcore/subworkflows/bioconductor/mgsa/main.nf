#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mgsa — mgsa_gene_ontology
// Perform model-based gene set enrichment analysis using Gene Ontology annotations loaded from a GAF file.
// Input: gene_association.gaf, study_genes.txt
// Container: quay.io/biocontainers/bioconductor-mgsa:1.58.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mgsa
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load GO annotations from a GAF file using readGAF
//  * 2. [Core Analysis] Run MGSA using mgsa
//  * 3. [Visualization & Output] Plot the posterior probabilities using plot
//  * 4. [Core Analysis] Extract and filter results using setsResults and subset

nextflow.enable.dsl = 2

process BIOC_MGSA_MGSA_GENE_ONTOLOGY {
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
    .bm_deps <- c("mgsa")
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
    library(mgsa)
    
    # 1. Load GO annotations from the user-provided GAF file
    # The documented code uses readGAF() to load GAF files.
    # We assign the result to 'example_go' to match the documented mgsa() call.
    example_go = readGAF("gene_association.gaf")
    
    # Load the study genes from the user-provided text file
    # We assign this to 'example_o' to match the documented mgsa() call.
    example_o = readLines("study_genes.txt")
    example_o = trimws(example_o)
    example_o = example_o[example_o != ""]
    
    # 2. Run MGSA using mgsa()
    set.seed(0)
    fit = mgsa(example_o, example_go)
    
    # Print the fit object to stdout
    print(fit)
    
    # 3. Plot the posterior probabilities using plot() and save to PDF
    pdf("mgsa_plot.pdf", width = 10, height = 8)
    plot(fit)
    dev.off()
    
    # 4. Extract and filter results using setsResults and subset
    res = setsResults(fit)
    filtered_res = subset(res, estimate > 0.5)
    
    # Write the results to output files
    write.csv(res, "mgsa_results_all.csv", row.names = TRUE)
    write.csv(filtered_res, "mgsa_results_filtered.csv", row.names = TRUE)
    saveRDS(fit, "mgsa_fit.rds")

    writeLines(c(
        '"BIOC_MGSA_MGSA_GENE_ONTOLOGY":',
        paste0('    mgsa: ', as.character(packageVersion('mgsa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mgsa_gene_ontology.csv versions.yml
    """
}

workflow BIOC_MGSA_MGSA_GENE_ONTOLOGY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_association.gaf, study_genes.txt ] ]

    main:
    BIOC_MGSA_MGSA_GENE_ONTOLOGY(ch_input)

    emit:
    tables   = BIOC_MGSA_MGSA_GENE_ONTOLOGY.out.tables
    plots    = BIOC_MGSA_MGSA_GENE_ONTOLOGY.out.plots
    objects  = BIOC_MGSA_MGSA_GENE_ONTOLOGY.out.objects
    versions = BIOC_MGSA_MGSA_GENE_ONTOLOGY.out.versions
}
