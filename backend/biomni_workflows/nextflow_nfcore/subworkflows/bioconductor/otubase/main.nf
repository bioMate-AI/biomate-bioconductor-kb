#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: otubase — otu_based_analysis
// Import Mothur OTU files and metadata, generate an abundance table, estimate richness, cluster samples, and subset the dataset.
// Input: sogin.groups, sogin.unique.filter.fn.list, sample_metadata.txt, sogin.fasta
// Container: quay.io/biocontainers/bioconductor-otubase:1.60.0--r45hdfd78af_0
// R packages: OTUbase, vegan
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: cluster plot

nextflow.enable.dsl = 2

process BIOC_OTUBASE_OTU_BASED_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-otubase:1.60.0--r45hdfd78af_0"

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
    .bm_deps <- c("OTUbase", "vegan")
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
    library(OTUbase)
    library(vegan)
    
    # --- Define directory path (working directory where user files ---
    dirPath <- "."
    
    # --- Read OTU data and metadata using readOTUset ---
    soginOTU <- readOTUset(
      dirPath = dirPath,
      level = "0.03",
      samplefile = "sogin.groups",
      fastafile = "sogin.fasta",
      otufile = "sogin.unique.filter.fn.list",
      sampleADF = "sample_metadata.txt"
    )
    
    # Print object summary
    print(soginOTU)
    
    # --- Access sequence and sample IDs ---
    cat("--- Sequence IDs ---\n")
    print(head(id(soginOTU)))
    
    cat("--- Sequences ---\n")
    print(head(sread(soginOTU)))
    
    cat("--- Sample IDs ---\n")
    print(head(sampleID(soginOTU)))
    
    cat("--- Sample Metadata ---\n")
    print(head(sData(soginOTU)))
    
    cat("--- OTU IDs ---\n")
    print(head(otuID(soginOTU)))
    
    # --- Generate OTU abundance table ---
    abundOTU <- abundance(soginOTU, weighted = FALSE, collab = 'Site')
    cat("--- Abundance Table ---\n")
    print(head(abundOTU))
    
    # Save abundance table to CSV
    write.csv(abundOTU, file = "abundance_table.csv", row.names = TRUE)
    
    # --- Estimate richness using vegan::estimateR ---
    estrichOTU <- apply(abundOTU, 2, estimateR)
    cat("--- Richness Estimates ---\n")
    print(estrichOTU)
    
    # Save richness estimates to CSV
    write.csv(estrichOTU, file = "richness_estimates.csv", row.names = TRUE)
    
    # --- Cluster samples (plots a dendrogram, save to PDF) ---
    pdf("sample_clustering.pdf", width = 8, height = 6)
    clusterSamples(soginOTU, distmethod = 'jaccard', clustermethod = 'complete', collab = 'Site')
    dev.off()
    
    # --- Subset the OTU set ---
    # Wrapped in tryCatch to handle cases where user-provided metadata/groups 
    # might not contain these exact sample IDs.
    tryCatch({
      soginReduced <- subOTUset(soginOTU, samples = c("137", "138", "53R", "55R"))
      print(soginReduced)
      saveRDS(soginReduced, file = "sogin_reduced.rds")
    }, error = function(e) {
      warning("Could not subset OTU set with the specified sample IDs: ", e\$message)
    })

    writeLines(c(
        '"BIOC_OTUBASE_OTU_BASED_ANALYSIS":',
        paste0('        otubase: ', as.character(packageVersion("otubase")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_otu_based_analysis.csv versions.yml
    """
}

workflow BIOC_OTUBASE_OTU_BASED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sogin.groups, sogin.unique.filter.fn.list, sample_metadata.txt, sogin.fasta ] ]

    main:
    BIOC_OTUBASE_OTU_BASED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_OTUBASE_OTU_BASED_ANALYSIS.out.tables
    plots    = BIOC_OTUBASE_OTU_BASED_ANALYSIS.out.plots
    objects  = BIOC_OTUBASE_OTU_BASED_ANALYSIS.out.objects
    versions = BIOC_OTUBASE_OTU_BASED_ANALYSIS.out.versions
}
