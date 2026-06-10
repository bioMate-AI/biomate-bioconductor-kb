#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snpstats — ld_analysis
// Calculate and visualize linkage disequilibrium (LD) statistics between SNPs.
// Input: ceph.1mb, support.ld
// Container: quay.io/biocontainers/bioconductor-snpstats:1.60.0--r45h01b2380_0
// R packages: Matrix, hexbin, snpStats
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNPSTATS_LD_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-snpstats:1.60.0--r45h01b2380_0"

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
    .bm_deps <- c("Matrix", "hexbin", "snpStats")
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
    library(snpStats)
    library(hexbin)
    library(Matrix)
    
    # Read user input files from the working directory
    ceph.1mb <- readRDS("ceph.1mb")
    support.ld <- readRDS("support.ld")
    
    # 1. Calculate LD statistics using ld
    ld.ceph <- ld(ceph.1mb, stats=c("D.prime", "R.squared"), depth=100)
    
    # Open PDF device to save visualizations
    pdf("ld_analysis_plots.pdf", width=10, height=8)
    
    # 2. Plot LD matrix using image
    print(image(ld.ceph\$D.prime, lwd=0))
    spectrum <- rainbow(10, start=0, end=1/6)[10:1]
    print(image(ld.ceph\$D.prime, lwd=0, cuts=9, col.regions=spectrum, colorkey=TRUE))
    
    # 3. Calculate physical distance between SNPs using bandSparse
    pos <- support.ld\$Position
    diags <- vector("list", 100)
    for (i in 1:100) diags[[i]] <- pos[(i+1):603] - pos[1:(603-i)]
    dist <- bandSparse(603, k=1:100, diagonals=diags)
    distance <- dist@x
    D.prime <- ld.ceph\$D.prime@x
    R.squared <- ld.ceph\$R.squared@x
    
    # 4. Plot LD statistics against physical distance using hexbin
    plot(hexbin(D.prime^2, R.squared))
    
    # Calculate Odds Ratio (OR) for specific SNPs
    OR <- ld(ceph.1mb[,1], ceph.1mb[,5], stats="OR")
    
    # 5. Perform hierarchical clustering on LD-derived distances using hclust
    use <- pos>=1.579e7 & pos<=1.587e7
    r2 <- forceSymmetric(ld.ceph\$R.squared[use, use])
    D <- as.dist(1-r2)
    hc <- hclust(D, method="complete")
    plot(hc)
    
    # Close PDF device
    dev.off()
    
    # Cut tree to define clusters
    clusters <- cutree(hc, h=0.5)
    
    # Save meaningful results to output files
    saveRDS(ld.ceph, "ld_ceph.rds")
    saveRDS(OR, "OR_stat.rds")
    write.csv(data.frame(SNP = names(clusters), Cluster = clusters), "clusters.csv", row.names=FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SNPSTATS_LD_ANALYSIS":
        snpstats: \$(Rscript -e 'cat(as.character(packageVersion("snpstats")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ld_analysis.csv versions.yml
    """
}

workflow BIOC_SNPSTATS_LD_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ceph.1mb, support.ld ] ]

    main:
    BIOC_SNPSTATS_LD_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SNPSTATS_LD_ANALYSIS.out.tables
    plots    = BIOC_SNPSTATS_LD_ANALYSIS.out.plots
    objects  = BIOC_SNPSTATS_LD_ANALYSIS.out.objects
    versions = BIOC_SNPSTATS_LD_ANALYSIS.out.versions
}
