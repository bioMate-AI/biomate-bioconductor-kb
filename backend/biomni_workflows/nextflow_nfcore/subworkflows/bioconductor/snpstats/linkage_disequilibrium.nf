#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snpStats — linkage_disequilibrium
// Calculate and visualize linkage disequilibrium (LD) between SNPs and perform LD-based clustering.
// Input: ceph.1mb, support.ld$Position
// Container: quay.io/biocontainers/bioconductor-snpstats:1.60.0--r45h01b2380_0
// R packages: Matrix, snpStats
// Bioconductor: 3.20 | R: 4.4
// Requires: Matrix, snpStats
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate LD statistics (D' and R^2) using ld
//  * 2. [Visualization & Output] Visualize LD matrices using image
//  * 3. [Core Analysis] Calculate physical distances between SNPs
//  * 4. [Core Analysis] Perform hierarchical clustering on LD-based distances using hclust and cutree

nextflow.enable.dsl = 2

process BIOC_SNPSTATS_LINKAGE_DISEQUILIBRIUM {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("Matrix", "snpStats")
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
        library(snpStats)
        library(Matrix)
        
        # Read user input files from the working directory
        ceph.1mb <- readRDS("ceph.1mb")
        support.ld <- readRDS("support.ld")
        
        # 1. Calculate LD statistics (D' and R^2) using ld
        ld.ceph <- ld(ceph.1mb, stats=c("D.prime", "R.squared"), depth=100)
        
        # 2. Visualize LD matrices using image
        pdf("ld_ceph_dprime.pdf")
        print(image(ld.ceph\$D.prime, lwd=0))
        dev.off()
        
        # 3. Calculate physical distances between SNPs
        pos <- support.ld\$Position
        n_snps <- length(pos)
        max_k <- min(100, n_snps - 1)
        diags <- vector("list", max_k)
        for (i in seq_len(max_k)) diags[[i]] <- pos[(i+1):n_snps] - pos[1:(n_snps-i)]
        dist <- bandSparse(n_snps, k=seq_len(max_k), diagonals=diags)
        distance <- dist@x
        D.prime <- ld.ceph\$D.prime@x
        R.squared <- ld.ceph\$R.squared@x
        
        # Additional documented LD calculations
        idx1 <- 1
        idx5 <- min(5, n_snps)
        OR <- ld(ceph.1mb[,idx1], ceph.1mb[,idx5], stats="OR")
        
        idx168 <- min(168, n_snps)
        lr100 <- max(1, idx168 - 100):min(n_snps, idx168 + 100)
        lr100 <- lr100[lr100 != idx168]
        D.prime <- ld(ceph.1mb[,idx168], ceph.1mb[,lr100], stats="D.prime")
        where <- pos[lr100]
        
        # 4. Perform hierarchical clustering on LD-based distances using hclust and cutree
        use <- rep(FALSE, n_snps)
        use[max(1, floor(n_snps/2) - 25):min(n_snps, floor(n_snps/2) + 25)] <- TRUE
        r2 <- forceSymmetric(ld.ceph\$R.squared[use, use])
        D <- as.dist(1-r2)
        hc <- hclust(D, method="complete")
        
        # Plot the dendrogram
        pdf("ld_hclust_dendrogram.pdf")
        par(cex=0.5)
        plot(hc)
        dev.off()
        
        clusters <- cutree(hc, h=0.5)
        
        # Save meaningful results to output files
        saveRDS(ld.ceph, "ld_ceph_results.rds")
        saveRDS(clusters, "ld_clusters.rds")
        write.csv(as.data.frame(clusters), "ld_clusters.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_SNPSTATS_LINKAGE_DISEQUILIBRIUM":',
        paste0('    snpStats: ', as.character(packageVersion('snpStats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_linkage_disequilibrium.csv versions.yml
    """
}

workflow BIOC_SNPSTATS_LINKAGE_DISEQUILIBRIUM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ceph.1mb, support.ld$Position ] ]

    main:
    BIOC_SNPSTATS_LINKAGE_DISEQUILIBRIUM(ch_input)

    emit:
    tables   = BIOC_SNPSTATS_LINKAGE_DISEQUILIBRIUM.out.tables
    plots    = BIOC_SNPSTATS_LINKAGE_DISEQUILIBRIUM.out.plots
    objects  = BIOC_SNPSTATS_LINKAGE_DISEQUILIBRIUM.out.objects
    versions = BIOC_SNPSTATS_LINKAGE_DISEQUILIBRIUM.out.versions
}
