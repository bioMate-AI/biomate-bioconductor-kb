#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: snprelate — ibs_and_cluster_analysis
// Perform Identity-By-State (IBS) analysis, multidimensional scaling (MDS), and hierarchical clustering to group individuals.
// Input: genofile
// Container: quay.io/biocontainers/bioconductor-snprelate:1.44.0--r45ha27e39d_0
// R packages: SNPRelate, gdsfmt
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNPRELATE_IBS_AND_CLUSTER_ANALYSIS {
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
    library(gdsfmt)
    library(SNPRelate)
    
    # Define input file path (assuming "input.gds" in the working directory)
    input_gds_path <- "input.gds"
    
    # Open the GDS file
    genofile <- snpgdsOpen(input_gds_path)
    
    # Get population information
    pop_code <- read.gdsn(index.gdsn(genofile, path="sample.annot/pop.group"))
    
    # Get sample IDs for output tables
    sample_id <- read.gdsn(index.gdsn(genofile, "sample.id"))
    
    # Calculate average IBS pairwise identities
    ibs <- snpgdsIBS(genofile, num.thread=2)
    
    # Save IBS heatmap to PDF
    pdf("ibs_heatmap.pdf", width=7, height=7)
    pop.idx <- order(pop_code)
    image(ibs\$ibs[pop.idx, pop.idx], col=terrain.colors(16))
    dev.off()
    
    # Perform multidimensional scaling (MDS)
    loc <- cmdscale(1 - ibs\$ibs, k = 2)
    x <- loc[, 1]; y <- loc[, 2]
    race <- as.factor(pop_code)
    
    # Save MDS plot to PDF
    pdf("mds_plot.pdf", width=7, height=7)
    plot(x, y, col=race, xlab = "", ylab = "", main = "Multidimensional Scaling Analysis (IBS)")
    legend("topleft", legend=levels(race), pch="o", text.col=1:nlevels(race))
    dev.off()
    
    # Save MDS coordinates to CSV
    mds_df <- data.frame(
      sample.id = sample_id, 
      MDS_Dim1 = x, 
      MDS_Dim2 = y, 
      pop_group = pop_code, 
      stringsAsFactors = FALSE
    )
    write.csv(mds_df, "mds_coordinates.csv", row.names = FALSE)
    
    # Perform hierarchical clustering
    set.seed(100)
    ibs.hc <- snpgdsHCluster(snpgdsIBS(genofile, num.thread=2))
    
    # Determine groups of individuals automatically
    rv <- snpgdsCutTree(ibs.hc)
    
    # Save automatic clustering dendrogram to PDF
    pdf("dendrogram_auto.pdf", width=8, height=6)
    plot(rv\$dendrogram, leaflab="none", main="HapMap Phase II")
    dev.off()
    
    # Determine groups of individuals by population information
    rv2 <- snpgdsCutTree(ibs.hc, samp.group=as.factor(pop_code))
    
    # Save population-guided clustering dendrogram to PDF
    pdf("dendrogram_pop.pdf", width=8, height=6)
    plot(rv2\$dendrogram, leaflab="none", main="HapMap Phase II")
    legend("topright", legend=levels(race), col=1:nlevels(race), pch=19, ncol=4)
    dev.off()
    
    # Save cluster assignments to CSV
    cluster_df <- data.frame(
      sample.id = sample_id,
      pop_group = pop_code,
      auto_group = rv\$samp.group,
      pop_guided_group = rv2\$samp.group,
      stringsAsFactors = FALSE
    )
    write.csv(cluster_df, "cluster_assignments.csv", row.names = FALSE)
    
    # Save R objects to RDS for downstream analysis
    saveRDS(ibs, "ibs_results.rds")
    saveRDS(ibs.hc, "ibs_hcluster.rds")
    saveRDS(rv, "cut_tree_auto.rds")
    saveRDS(rv2, "cut_tree_pop.rds")
    
    # Close the GDS file
    snpgdsClose(genofile)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SNPRELATE_IBS_AND_CLUSTER_ANALYSIS":
        snprelate: \$(Rscript -e 'cat(as.character(packageVersion("snprelate")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ibs_and_cluster_analysis.csv versions.yml
    """
}

workflow BIOC_SNPRELATE_IBS_AND_CLUSTER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genofile ] ]

    main:
    BIOC_SNPRELATE_IBS_AND_CLUSTER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SNPRELATE_IBS_AND_CLUSTER_ANALYSIS.out.tables
    plots    = BIOC_SNPRELATE_IBS_AND_CLUSTER_ANALYSIS.out.plots
    objects  = BIOC_SNPRELATE_IBS_AND_CLUSTER_ANALYSIS.out.objects
    versions = BIOC_SNPRELATE_IBS_AND_CLUSTER_ANALYSIS.out.versions
}
