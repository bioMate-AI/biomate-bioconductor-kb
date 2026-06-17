#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iBMQ — eqtl_mapping_ris
// Perform eQTL mapping, cis/trans classification, and hotspot detection for Recombinant Inbred Strains (RIS) where genotypes are homozygous (coded 0/1).
// Input: snp, gene, snppos, genepos
// Container: quay.io/biocontainers/bioconductor-ibmq:1.50.0--r45h57f0213_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, ggplot2, iBMQ
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load genotype and expression data
//  * 2. [Core Analysis] Run MCMC to calculate Posterior Probabilities of Association (PPA)
//  * 3. [Core Analysis] Calculate FDR threshold
//  * 4. [Core Analysis] Identify significant eQTLs
//  * 5. [Input & Preparation] Load genomic positions and classify eQTLs as cis or trans
//  * 6. [Visualization & Output] Plot genome-wide eQTL distribution
//  * 7. [Core Analysis] Identify trans-eQTL hotspots

nextflow.enable.dsl = 2

process BIOC_IBMQ_EQTL_MAPPING_RIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("iBMQ", "Biobase", "ggplot2")
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
    library(iBMQ)
    library(Biobase)
    library(ggplot2)
    
    # 1. Load genotype and expression data, and genomic positions
    message("Loading input files...")
    
    # Load snp (SnpSet object)
    if (file.exists("snp.rds")) {
      snp <- readRDS("snp.rds")
    } else if (file.exists("snp")) {
      snp <- readRDS("snp")
    } else {
      stop("Error: snp file (SnpSet object) not found in the working directory.")
    }
    
    # Load gene (ExpressionSet object)
    if (file.exists("gene.rds")) {
      gene <- readRDS("gene.rds")
    } else if (file.exists("gene")) {
      gene <- readRDS("gene")
    } else {
      stop("Error: gene file (ExpressionSet object) not found in the working directory.")
    }
    
    # Load snppos (Data frame)
    if (file.exists("snppos.csv")) {
      snppos <- read.csv("snppos.csv", stringsAsFactors = FALSE)
    } else if (file.exists("snppos.rds")) {
      snppos <- readRDS("snppos.rds")
    } else if (file.exists("snppos")) {
      snppos <- read.csv("snppos", stringsAsFactors = FALSE)
    } else {
      stop("Error: snppos file not found in the working directory.")
    }
    
    # Load genepos (Data frame)
    if (file.exists("genepos.csv")) {
      genepos <- read.csv("genepos.csv", stringsAsFactors = FALSE)
    } else if (file.exists("genepos.rds")) {
      genepos <- readRDS("genepos.rds")
    } else if (file.exists("genepos")) {
      genepos <- read.csv("genepos", stringsAsFactors = FALSE)
    } else {
      stop("Error: genepos file not found in the working directory.")
    }
    
    # 2. Run MCMC to calculate Posterior Probabilities of Association (PPA)
    message("Running MCMC to calculate Posterior Probabilities of Association (PPA)...")
    PPA <-  eqtlMcmc(snp, gene, n.iter=100, burn.in=100, n.sweep=20, mc.cores=1, RIS=TRUE)
    saveRDS(PPA, "PPA.rds")
    
    # 3. Calculate FDR threshold
    message("Calculating FDR threshold...")
    cutoff <- calculateThreshold(PPA, 0.1)
    writeLines(as.character(cutoff), "threshold_cutoff.txt")
    
    # 4. Identify significant eQTLs
    message("Identifying significant eQTLs...")
    eqtl <- eqtlFinder(PPA, cutoff)
    write.csv(eqtl, "significant_eqtls.csv", row.names = FALSE)
    
    # 5. Classify eQTLs as cis or trans
    message("Classifying eQTLs as cis or trans...")
    eqtltype <- eqtlClassifier(eqtl, snppos, genepos,1000000)
    write.csv(eqtltype, "classified_eqtls.csv", row.names = FALSE)
    
    # 6. Plot genome-wide eQTL distribution
    message("Plotting genome-wide eQTL distribution...")
    p <- ggplot(eqtltype, aes(y=GeneStart, x=MarkerPosition)) +
      geom_point(aes(y=GeneStart, x=MarkerPosition,color = PPA), size = 1.5)+
      facet_grid(GeneChrm~MarkerChrm)+theme_bw(base_size = 12, base_family = "")+  
      theme(axis.ticks = element_blank(), axis.text.x = element_blank(), axis.text.y = element_blank())+scale_x_reverse()
    ggsave("genome_wide_eqtl_plot.pdf", plot = p, width = 10, height = 8)
    
    # 7. Identify trans-eQTL hotspots
    message("Identifying trans-eQTL hotspots...")
    hotspot <- hotspotFinder(eqtltype, 10)
    saveRDS(hotspot, "hotspots.rds")
    
    # Write a summary of hotspots
    if (length(hotspot) > 0) {
      hotspot_summary <- data.frame(
        Marker = names(hotspot),
        NumGenes = sapply(hotspot, nrow)
      )
    } else {
      hotspot_summary <- data.frame(
        Marker = character(0),
        NumGenes = integer(0)
      )
    }
    write.csv(hotspot_summary, "hotspots_summary.csv", row.names = FALSE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_IBMQ_EQTL_MAPPING_RIS":',
        paste0('    iBMQ: ', as.character(packageVersion('iBMQ')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_eqtl_mapping_ris.csv versions.yml
    """
}

workflow BIOC_IBMQ_EQTL_MAPPING_RIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ snp, gene, snppos, genepos ] ]

    main:
    BIOC_IBMQ_EQTL_MAPPING_RIS(ch_input)

    emit:
    tables   = BIOC_IBMQ_EQTL_MAPPING_RIS.out.tables
    plots    = BIOC_IBMQ_EQTL_MAPPING_RIS.out.plots
    objects  = BIOC_IBMQ_EQTL_MAPPING_RIS.out.objects
    versions = BIOC_IBMQ_EQTL_MAPPING_RIS.out.versions
}
