#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: norce — go_enrichment_ncrna_genes
// Perform GO enrichment analysis for a list of ncRNA genes using neighborhood, custom TAD boundaries, or correlation.
// Input: brain_disorder_ncRNA, DER-18_TAD_adultbrain.txt, miRCancer.db
// Container: quay.io/biocontainers/bioconductor-norce:1.22.0--r45hdfd78af_0
// R packages: NoRCE, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORCE_GO_ENRICHMENT_NCRNA_GENES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-norce:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("NoRCE", "rtracklayer")
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
    library(NoRCE)
    library(rtracklayer)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read User Input Files from Working Directory
    # -----------------------------------------------------------------------------
    
    # 1. Read the ncRNA gene list
    ncrna_file <- "brain_disorder_ncRNA"
    if (!file.exists(ncrna_file)) {
      stop(paste("Required input file missing:", ncrna_file))
    }
    # Read lines and clean up any empty elements
    brain_disorder_ncRNA <- readLines(ncrna_file)
    brain_disorder_ncRNA <- brain_disorder_ncRNA[brain_disorder_ncRNA != ""]
    
    # 2. Path to custom TAD boundaries BED file
    cus_TAD <- "DER-18_TAD_adultbrain.txt"
    if (!file.exists(cus_TAD)) {
      stop(paste("Required input file missing:", cus_TAD))
    }
    
    # 3. Path to local correlation database
    db_file <- "miRCancer.db"
    if (!file.exists(db_file)) {
      stop(paste("Required input file missing:", db_file))
    }
    
    # -----------------------------------------------------------------------------
    # Stage 2: Set Neighborhood Parameters
    # -----------------------------------------------------------------------------
    type <- c('downstream', 'upstream')
    value <- c(2000, 30000)
    setParameters(type, value)
    setParameters("searchRegion", "exon")
    
    # -----------------------------------------------------------------------------
    # Stage 3: Run GO Enrichment based on Neighborhood
    # -----------------------------------------------------------------------------
    ncGO <- geneGOEnricher(
      gene = brain_disorder_ncRNA, 
      org_assembly = 'hg19', 
      near = TRUE, 
      genetype = 'Ensembl_gene'
    )
    
    # Save RDS of the neighborhood enrichment result
    saveRDS(ncGO, "ncGO_neighborhood.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 4: Run GO Enrichment incorporating Custom TAD Boundaries
    # -----------------------------------------------------------------------------
    tad_custom <- rtracklayer::import(cus_TAD, format = 'bed')
    
    ncGO_tad <- geneGOEnricher(
      gene = brain_disorder_ncRNA, 
      org_assembly = 'hg19', 
      genetype = 'Ensembl_gene', 
      isTADSearch = TRUE, 
      TAD = tad_custom
    )
    
    # Save RDS of the TAD-based enrichment result
    saveRDS(ncGO_tad, "ncGO_tad.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 5: Run GO Enrichment incorporating Correlation Analysis
    # -----------------------------------------------------------------------------
    ncGO_corr <- geneGOEnricher(
      gene = brain_disorder_ncRNA, 
      org_assembly = 'hg19', 
      genetype = 'Ensembl_gene',
      near = TRUE, 
      express = TRUE, 
      databaseFile = db_file, 
      cancer = 'GBMLGG'
    )
    
    # Save RDS of the correlation-based enrichment result
    saveRDS(ncGO_corr, "ncGO_corr.rds")
    
    # -----------------------------------------------------------------------------
    # Stage 6: Export and Visualize Results
    # -----------------------------------------------------------------------------
    
    # Export tabular results
    writeEnrichment(
      mrnaObject = ncGO, 
      fileName = "result_all.txt", 
      sept = "\t", 
      type = "pvalue"
    )
    
    writeEnrichment(
      mrnaObject = ncGO, 
      fileName = "result_top5.txt", 
      sept = "\t", 
      type = "pvalue", 
      n = 5
    )
    
    # Export Dot Plot to PDF
    pdf("dotplot.pdf", width = 8, height = 8)
    drawDotPlot(mrnaObject = ncGO, type = "pvalue", n = 25)
    dev.off()
    
    # Export Network Plot to PDF
    pdf("network.pdf", width = 10, height = 10)
    createNetwork(mrnaObject = ncGO, type = 'pvalue', n = 2, isNonCode = TRUE)
    dev.off()
    
    # Export GO DAG to PNG
    getGoDag(
      mrnaObject = ncGO, 
      type = 'pvalue', 
      n = 2, 
      filename = 'dag.png', 
      imageFormat = "png"
    )

    cat <<-END_VERSIONS > versions.yml
    "BIOC_NORCE_GO_ENRICHMENT_NCRNA_GENES":
        norce: \$(Rscript -e 'cat(as.character(packageVersion("norce")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_go_enrichment_ncrna_genes.csv versions.yml
    """
}

workflow BIOC_NORCE_GO_ENRICHMENT_NCRNA_GENES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ brain_disorder_ncRNA, DER-18_TAD_adultbrain.txt, miRCancer.db ] ]

    main:
    BIOC_NORCE_GO_ENRICHMENT_NCRNA_GENES(ch_input)

    emit:
    tables   = BIOC_NORCE_GO_ENRICHMENT_NCRNA_GENES.out.tables
    plots    = BIOC_NORCE_GO_ENRICHMENT_NCRNA_GENES.out.plots
    objects  = BIOC_NORCE_GO_ENRICHMENT_NCRNA_GENES.out.objects
    versions = BIOC_NORCE_GO_ENRICHMENT_NCRNA_GENES.out.versions
}
