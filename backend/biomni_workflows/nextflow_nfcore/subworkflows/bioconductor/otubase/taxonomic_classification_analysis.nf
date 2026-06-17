#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OTUbase — taxonomic_classification_analysis
// Import RDP classifier taxonomy files, Mothur names/groups files, and sample metadata to perform taxonomic abundance profiling, richness estimation, and sample c
// Input: sogin.fasta, sample_metadata.txt, sogin.unique.fix.tax, sogin.names, sogin.groups
// Container: quay.io/biocontainers/bioconductor-otubase:1.60.0--r45hdfd78af_0
// R packages: OTUbase, vegan
// Bioconductor: 3.20 | R: 4.4
// Requires: OTUbase, vegan
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define directory path containing input files
//  * 2. [Input & Preparation] Read taxonomic classification data and metadata using readTAXset
//  * 3. [Core Analysis] Access taxonomic assignments using tax
//  * 4. [Core Analysis] Generate a taxonomic abundance table at a specific taxonomic level using abundance
//  * 5. [Core Analysis] Estimate richness using apply and estimateR
//  * 6. [Core Analysis] Cluster samples at a specific taxonomic level using clusterSamples

nextflow.enable.dsl = 2

process BIOC_OTUBASE_TAXONOMIC_CLASSIFICATION_ANALYSIS {
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
    
    # 1. Define directory path containing input files (current working directory)
    dirPath <- "."
    
    # 2. Read taxonomic classification data and metadata using readTAXset
    soginTAX <- readTAXset(
      dirPath = dirPath, 
      fastafile = 'sogin.fasta', 
      sampleADF = 'sample_metadata.txt', 
      taxfile = 'sogin.unique.fix.tax', 
      namefile = 'sogin.names', 
      samplefile = 'sogin.groups'
    )
    
    # Print summary of the imported TAXset object
    print(soginTAX)
    
    # 3. Access taxonomic assignments using tax
    tax_assignments <- tax(soginTAX)
    print(head(tax_assignments))
    write.csv(tax_assignments, "taxonomic_assignments.csv", row.names = TRUE)
    
    # 4. Generate a taxonomic abundance table at a specific taxonomic level using abundance
    abundTAX <- abundance(soginTAX, weighted = F, taxCol = 'genus', collab = 'Site')
    print(head(abundTAX))
    write.csv(abundTAX, "taxonomic_abundance_genus.csv", row.names = TRUE)
    
    # 5. Estimate richness using apply and estimateR
    estrichTAX <- apply(abundTAX, 2, estimateR)
    print(estrichTAX)
    write.csv(estrichTAX, "richness_estimates.csv", row.names = TRUE)
    
    # 6. Cluster samples at a specific taxonomic level using clusterSamples
    # Open a PDF device to capture the cluster plot
    pdf("sample_clustering_genus.pdf", width = 8, height = 6)
    clust_res <- clusterSamples(
      soginTAX, 
      taxCol = 'genus', 
      distmethod = 'jaccard', 
      clustermethod = 'complete', 
      collab = 'Site'
    )
    
    # If clusterSamples returns an hclust object, plot it explicitly to ensure it is written to the PDF
    if (inherits(clust_res, "hclust")) {
      plot(clust_res, main = "Sample Clustering (Genus level, Jaccard distance)")
    }
    dev.off()
    
    # Save the key R objects to disk for downstream analysis
    saveRDS(soginTAX, "soginTAX.rds")
    saveRDS(abundTAX, "abundTAX.rds")
    saveRDS(estrichTAX, "estrichTAX.rds")
    saveRDS(clust_res, "clust_res.rds")
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_OTUBASE_TAXONOMIC_CLASSIFICATION_ANALYSIS":',
        paste0('    OTUbase: ', as.character(packageVersion('OTUbase')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_taxonomic_classification_analysis.csv versions.yml
    """
}

workflow BIOC_OTUBASE_TAXONOMIC_CLASSIFICATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sogin.fasta, sample_metadata.txt, sogin.unique.fix.tax, sogin.names, sogin.groups ] ]

    main:
    BIOC_OTUBASE_TAXONOMIC_CLASSIFICATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_OTUBASE_TAXONOMIC_CLASSIFICATION_ANALYSIS.out.tables
    plots    = BIOC_OTUBASE_TAXONOMIC_CLASSIFICATION_ANALYSIS.out.plots
    objects  = BIOC_OTUBASE_TAXONOMIC_CLASSIFICATION_ANALYSIS.out.objects
    versions = BIOC_OTUBASE_TAXONOMIC_CLASSIFICATION_ANALYSIS.out.versions
}
