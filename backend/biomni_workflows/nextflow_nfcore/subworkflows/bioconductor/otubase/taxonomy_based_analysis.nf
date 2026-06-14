#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: otubase — taxonomy_based_analysis
// Import RDP taxonomic classification files and metadata, generate a taxonomic abundance table, estimate richness, and cluster samples.
// Input: sogin.groups, sogin.unique.fix.tax, sogin.names, sample_metadata.txt, sogin.fasta
// Container: quay.io/biocontainers/bioconductor-otubase:1.60.0--r45hdfd78af_0
// R packages: OTUbase, vegan
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: cluster plot

nextflow.enable.dsl = 2

process BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS {
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
    library("OTUbase")
    library("vegan")
    
    # --- Define directory path (using current working directory ---
    dirPath <- "."
    
    # --- Read taxonomy data and metadata using readTAXset ---
    soginTAX <- readTAXset(dirPath=dirPath, fastafile='sogin.fasta', sampleADF='sample_metadata.txt', taxfile='sogin.unique.fix.tax', namefile='sogin.names', samplefile='sogin.groups')
    print(soginTAX)
    
    # --- Access taxonomic classifications ---
    tax_data <- tax(soginTAX)
    print(head(tax_data))
    write.csv(tax_data, "taxonomic_classifications.csv", row.names=TRUE)
    
    # --- Generate taxonomic abundance table at a specific rank ---
    abundTAX <- abundance(soginTAX, weighted=F, taxCol='genus', collab='Site')
    print(head(abundTAX))
    write.csv(abundTAX, "taxonomic_abundance_genus.csv", row.names=TRUE)
    
    # --- Estimate richness ---
    estrichTAX <- apply(abundTAX, 2, estimateR)
    print(estrichTAX)
    write.csv(estrichTAX, "richness_estimates_genus.csv", row.names=TRUE)
    
    # --- Cluster samples and save the dendrogram plot ---
    pdf("sample_clustering_genus.pdf")
    clusterSamples(soginTAX, taxCol='genus', distmethod='jaccard', clustermethod='complete', collab='Site')
    dev.off()
    
    # Save the constructed TAXset object
    saveRDS(soginTAX, "soginTAX.rds")

    writeLines(c(
        '"BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS":',
        paste0('        otubase: ', as.character(packageVersion("otubase")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_taxonomy_based_analysis.csv versions.yml
    """
}

workflow BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sogin.groups, sogin.unique.fix.tax, sogin.names, sample_metadata.txt, sogin.fasta ] ]

    main:
    BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS.out.tables
    plots    = BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS.out.plots
    objects  = BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS.out.objects
    versions = BIOC_OTUBASE_TAXONOMY_BASED_ANALYSIS.out.versions
}
