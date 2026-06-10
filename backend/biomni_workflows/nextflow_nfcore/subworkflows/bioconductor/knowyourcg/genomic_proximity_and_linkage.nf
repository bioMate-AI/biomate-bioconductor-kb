#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: knowyourcg — genomic_proximity_and_linkage
// Link a set of CpG probes to proximal genes and perform Gene Ontology enrichment analysis, or test whether a query set of CpG probes shares close genomic proximi
// Input: query_probes
// Container: quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0
// R packages: SummarizedExperiment, gprofiler2, knowYourCG, sesameData
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG_GENOMIC_PROXIMITY_AND_LINKAGE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0"

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
    .bm_deps <- c("SummarizedExperiment", "gprofiler2", "knowYourCG", "sesameData")
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
    library(knowYourCG)
    library(sesameData)
    library(SummarizedExperiment)
    library(gprofiler2)
    
    # Read user input from the working directory
    if (file.exists("query_probes.txt")) {
      query_probes <- readLines("query_probes.txt")
    } else if (file.exists("query_probes.csv")) {
      query_probes <- read.csv("query_probes.csv", header = FALSE, stringsAsFactors = FALSE)[[1]]
    } else {
      stop("Required input file 'query_probes.txt' or 'query_probes.csv' not found in the working directory.")
    }
    
    # Clean query probes vector
    query_probes <- trimws(query_probes)
    query_probes <- query_probes[query_probes != ""]
    
    # 1. Link query probes to proximal genes
    genes <- linkProbesToProximalGenes (query_probes, platform = "MM285" ) \$ gene_name
    
    # Save linked genes output
    write.table(genes, file = "linked_genes.txt", row.names = FALSE, col.names = FALSE, quote = FALSE)
    
    # 2. Perform Gene Ontology enrichment on the linked genes
    gostres <- gprofiler2 :: gost (genes, organism = "mmusculus" )
    
    # Save GO enrichment results
    saveRDS(gostres, file = "gost_results.rds")
    if (!is.null(gostres) && !is.null(gostres\$result)) {
      write.csv(gostres\$result, file = "gost_results.csv", row.names = FALSE)
    }
    
    # 3. Test for genomic proximity and co-localization
    probes <- query_probes
    res <- testProbeProximity ( probeIDs= probes)
    
    # Save proximity results
    saveRDS(res, file = "probe_proximity_results.rds")
    if (!is.null(res)) {
      if (!is.null(res\$Stats)) {
        write.csv(res\$Stats, file = "proximity_stats.csv", row.names = FALSE)
      }
      if (!is.null(res\$Clusters)) {
        write.csv(res\$Clusters, file = "proximity_clusters.csv", row.names = FALSE)
      }
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KNOWYOURCG_GENOMIC_PROXIMITY_AND_LINKAGE":
        knowyourcg: \$(Rscript -e 'cat(as.character(packageVersion("knowyourcg")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomic_proximity_and_linkage.csv versions.yml
    """
}

workflow BIOC_KNOWYOURCG_GENOMIC_PROXIMITY_AND_LINKAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ query_probes ] ]

    main:
    BIOC_KNOWYOURCG_GENOMIC_PROXIMITY_AND_LINKAGE(ch_input)

    emit:
    tables   = BIOC_KNOWYOURCG_GENOMIC_PROXIMITY_AND_LINKAGE.out.tables
    plots    = BIOC_KNOWYOURCG_GENOMIC_PROXIMITY_AND_LINKAGE.out.plots
    objects  = BIOC_KNOWYOURCG_GENOMIC_PROXIMITY_AND_LINKAGE.out.objects
    versions = BIOC_KNOWYOURCG_GENOMIC_PROXIMITY_AND_LINKAGE.out.versions
}
