#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snprelate — pca_and_population_structure
// Perform LD-based SNP pruning and Principal Component Analysis (PCA) to identify population structure and calculate SNP-PC correlations.
// Input: genofile
// Container: quay.io/biocontainers/bioconductor-snprelate:1.44.0--r45ha27e39d_0
// R packages: SNPRelate, gdsfmt
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNPRELATE_PCA_AND_POPULATION_STRUCTURE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-snprelate:1.44.0--r45ha27e39d_0"

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
    .bm_deps <- c("SNPRelate", "gdsfmt")
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
    
    # Load required libraries
    library(gdsfmt)
    library(SNPRelate)
    
    # --- Open the GDS file ---
    # The pipeline expects the user input file "genofile" or "genofile.gds" in the working directory
    input_file <- "genofile"
    if (!file.exists(input_file) && file.exists("genofile.gds")) {
      input_file <- "genofile.gds"
    }
    
    genofile <- snpgdsOpen(input_file)
    
    set.seed(1000)
    
    # --- Perform LD-based SNP pruning ---
    snpset <- snpgdsLDpruning(genofile, ld.threshold=0.2)
    
    # --- Extract pruned SNP IDs ---
    snpset.id <- unlist(unname(snpset))
    
    # Save pruned SNP IDs to a CSV file
    write.csv(data.frame(snp.id = snpset.id), "pruned_snp_ids.csv", row.names = FALSE)
    
    # --- Run PCA ---
    pca <- snpgdsPCA(genofile, snp.id=snpset.id, num.thread=2)
    
    # Calculate variance proportion (%)
    pc.percent <- pca\$varprop*100
    variance_df <- data.frame(
      PC = paste0("PC", seq_along(pc.percent)),
      VarianceProportion = pc.percent
    )
    write.csv(variance_df, "pca_variance_proportion.csv", row.names = FALSE)
    
    # Make a data.frame of eigenvectors
    tab <- data.frame(sample.id = pca\$sample.id,
        EV1 = pca\$eigenvect[,1],    # the first eigenvector
        EV2 = pca\$eigenvect[,2],    # the second eigenvector
        stringsAsFactors = FALSE)
    
    # Save PCA results to a CSV file
    write.csv(tab, "pca_results.csv", row.names = FALSE)
    
    # Draw and save the PCA plot
    pdf("pca_plot.pdf", width = 6, height = 6)
    plot(tab\$EV2, tab\$EV1, xlab="eigenvector 2", ylab="eigenvector 1")
    dev.off()
    
    # --- Calculate PC-correlated SNPs ---
    chr <- read.gdsn(index.gdsn(genofile, "snp.chromosome"))
    CORR <- snpgdsPCACorr(pca, genofile, eig.which=1:4)
    
    # Save correlation results to an RDS file
    saveRDS(CORR, "snp_pc_correlation.rds")
    
    # Plot and save SNP-PC correlations
    pdf("snp_correlation_plot.pdf", width = 8, height = 6)
    savepar <- par(mfrow=c(2,1), mai=c(0.45, 0.55, 0.1, 0.25))
    for (i in 1:2) {
        plot(abs(CORR\$snpcorr[i,]), ylim=c(0,1), xlab="", ylab=paste("PC", i),
            col=chr, pch="+")
    }
    par(savepar)
    dev.off()
    
    # --- Close the GDS file ---
    snpgdsClose(genofile)

    writeLines(c(
        '"BIOC_SNPRELATE_PCA_AND_POPULATION_STRUCTURE":',
        paste0('        snprelate: ', as.character(packageVersion("snprelate")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_and_population_structure.csv versions.yml
    """
}

workflow BIOC_SNPRELATE_PCA_AND_POPULATION_STRUCTURE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genofile ] ]

    main:
    BIOC_SNPRELATE_PCA_AND_POPULATION_STRUCTURE(ch_input)

    emit:
    tables   = BIOC_SNPRELATE_PCA_AND_POPULATION_STRUCTURE.out.tables
    plots    = BIOC_SNPRELATE_PCA_AND_POPULATION_STRUCTURE.out.plots
    objects  = BIOC_SNPRELATE_PCA_AND_POPULATION_STRUCTURE.out.objects
    versions = BIOC_SNPRELATE_PCA_AND_POPULATION_STRUCTURE.out.versions
}
