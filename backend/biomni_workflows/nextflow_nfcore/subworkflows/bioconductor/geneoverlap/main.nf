#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneOverlap — pairwise_gene_overlap
// Test the statistical significance of the overlap between two individual gene lists and retrieve detailed association statistics.
// Input: list1.txt, list2.txt, background_size
// Container: quay.io/biocontainers/bioconductor-geneoverlap:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GeneOverlap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a GeneOverlap object using newGeneOverlap
//  * 2. [Core Analysis] Run the statistical test using testGeneOverlap
//  * 3. [Core Analysis] Print detailed results and retrieve specific statistics (intersection, odds ratio, contingency table, genome size) using accessors

nextflow.enable.dsl = 2

process BIOC_GENEOVERLAP_PAIRWISE_GENE_OVERLAP {
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
    .bm_deps <- c("GeneOverlap")
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
    
    # Load the required library
    library(GeneOverlap)
    
    # Read user inputs from the working directory
    list1 <- scan("list1.txt", what = character(), quiet = TRUE)
    list2 <- scan("list2.txt", what = character(), quiet = TRUE)
    bg_size <- as.integer(scan("background_size", what = integer(), quiet = TRUE)[1])
    
    # 1. Create a GeneOverlap object using newGeneOverlap
    go.obj <- newGeneOverlap(list1, 
                             list2, 
                             genome.size=bg_size)
    
    # 2. Run the statistical test using testGeneOverlap
    go.obj <- testGeneOverlap(go.obj)
    
    # 3. Print detailed results and retrieve specific statistics using accessors
    print(go.obj)
    head(getIntersection(go.obj))
    getOddsRatio(go.obj)
    getContbl(go.obj)
    getGenomeSize(go.obj)
    
    # Write meaningful results to output files
    # Save the intersection genes
    writeLines(getIntersection(go.obj), "intersection_genes.txt")
    
    # Save the contingency table
    write.csv(getContbl(go.obj), "contingency_table.csv", row.names = TRUE)
    
    # Save detailed statistics
    stats_df <- data.frame(
      GenomeSize = getGenomeSize(go.obj),
      OddsRatio = getOddsRatio(go.obj),
      PValue = getPval(go.obj),
      JaccardIndex = getJaccard(go.obj)
    )
    write.csv(stats_df, "overlap_statistics.csv", row.names = FALSE)
    
    # Save the GeneOverlap object as an RDS file
    saveRDS(go.obj, "gene_overlap_object.rds")

    writeLines(c(
        '"BIOC_GENEOVERLAP_PAIRWISE_GENE_OVERLAP":',
        paste0('    GeneOverlap: ', as.character(packageVersion('GeneOverlap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_gene_overlap.csv versions.yml
    """
}

workflow BIOC_GENEOVERLAP_PAIRWISE_GENE_OVERLAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ list1.txt, list2.txt, background_size ] ]

    main:
    BIOC_GENEOVERLAP_PAIRWISE_GENE_OVERLAP(ch_input)

    emit:
    tables   = BIOC_GENEOVERLAP_PAIRWISE_GENE_OVERLAP.out.tables
    plots    = BIOC_GENEOVERLAP_PAIRWISE_GENE_OVERLAP.out.plots
    objects  = BIOC_GENEOVERLAP_PAIRWISE_GENE_OVERLAP.out.objects
    versions = BIOC_GENEOVERLAP_PAIRWISE_GENE_OVERLAP.out.versions
}
