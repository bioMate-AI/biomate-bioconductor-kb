#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SNPRelate — identity_by_state_clustering
// Perform Identity-By-State (IBS) analysis, multidimensional scaling (MDS), and hierarchical clustering to group individuals.
// Input: genofile, pop_code
// Container: quay.io/biocontainers/bioconductor-snprelate:1.44.0--r45ha27e39d_0
// R packages: SNPRelate, gdsfmt
// Bioconductor: 3.20 | R: 4.4
// Requires: SNPRelate, gdsfmt
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate average IBS pairwise identities using snpgdsIBS
//  * 2. [Core Analysis] Perform multidimensional scaling on IBS distances using cmdscale
//  * 3. [Core Analysis] Perform hierarchical clustering using snpgdsHCluster
//  * 4. [Core Analysis] Determine and cut cluster groups automatically or by population using snpgdsCutTree

nextflow.enable.dsl = 2

process BIOC_SNPRELATE_IDENTITY_BY_STATE_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    
    # Read user inputs from the working directory
    # genofile can be provided as a GDS file directly or its path stored in an RDS file
    if (file.exists("genofile.rds")) {
      gds_path <- readRDS("genofile.rds")
    } else if (file.exists("genofile.gds")) {
      gds_path <- "genofile.gds"
    } else {
      stop("Error: GDS file ('genofile.gds') or path RDS ('genofile.rds') not found in the working directory.")
    }
    
    # Open the GDS file
    genofile <- snpgdsOpen(gds_path)
    
    # Read the population codes
    if (file.exists("pop_code.rds")) {
      pop_code <- readRDS("pop_code.rds")
    } else if (file.exists("pop_code.txt")) {
      pop_code <- scan("pop_code.txt", what = character(), quiet = TRUE)
    } else {
      stop("Error: Population codes file ('pop_code.rds' or 'pop_code.txt') not found in the working directory.")
    }
    
    # --- Documented Workflow Steps ---
    
    # 1. Calculate average IBS pairwise identities
    ibs <- snpgdsIBS(genofile, num.thread=2)
    
    # 2. Perform multidimensional scaling on IBS distances
    loc <- cmdscale(1 - ibs\$ibs, k = 2)
    
    # 3. Perform hierarchical clustering
    ibs.hc <- snpgdsHCluster(snpgdsIBS(genofile, num.thread=2))
    
    # 4. Determine and cut cluster groups automatically
    rv <- snpgdsCutTree(ibs.hc)
    
    # 5. Determine and cut cluster groups by population
    rv2 <- snpgdsCutTree(ibs.hc, samp.group=as.factor(pop_code))
    
    # --- Save Outputs ---
    
    # Save RDS objects of the analysis results
    saveRDS(ibs, "ibs_results.rds")
    saveRDS(ibs.hc, "ibs_hierarchical_clustering.rds")
    saveRDS(rv, "cut_tree_automatic.rds")
    saveRDS(rv2, "cut_tree_by_population.rds")
    
    # Save MDS coordinates to a CSV file
    mds_df <- data.frame(
      sample.id = ibs\$sample.id,
      Dim1 = loc[, 1],
      Dim2 = loc[, 2],
      pop_code = pop_code,
      stringsAsFactors = FALSE
    )
    write.csv(mds_df, "mds_coordinates.csv", row.names = FALSE)
    
    # Save clustering group assignments to a CSV file
    groups_df <- data.frame(
      sample.id = ibs\$sample.id,
      pop_code = pop_code,
      group_automatic = rv\$samp.group,
      group_by_population = rv2\$samp.group,
      stringsAsFactors = FALSE
    )
    write.csv(groups_df, "clustering_group_assignments.csv", row.names = FALSE)
    
    # Generate and save diagnostic plots to a PDF
    pdf("ibs_clustering_plots.pdf", width = 10, height = 8)
    
    # Plot 1: MDS Plot
    race <- as.factor(pop_code)
    plot(loc[, 1], loc[, 2], col = race, xlab = "Dimension 1", ylab = "Dimension 2",
         main = "Multidimensional Scaling Analysis (IBS)")
    legend("topleft", legend = levels(race), pch = "o", text.col = 1:nlevels(race))
    
    # Plot 2: Dendrogram with Automatic Cuts
    plot(rv\$dendrogram, leaflab = "none", main = "Hierarchical Clustering (Automatic Cut)")
    
    # Plot 3: Dendrogram with Population-based Cuts
    plot(rv2\$dendrogram, leaflab = "none", main = "Hierarchical Clustering (Population Cut)")
    legend("topright", legend = levels(race), col = 1:nlevels(race), pch = 19, ncol = 4)
    
    dev.off()
    
    # Close the GDS file connection
    snpgdsClose(genofile)

    writeLines(c(
        '"BIOC_SNPRELATE_IDENTITY_BY_STATE_CLUSTERING":',
        paste0('    SNPRelate: ', as.character(packageVersion('SNPRelate')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_identity_by_state_clustering.csv versions.yml
    """
}

workflow BIOC_SNPRELATE_IDENTITY_BY_STATE_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genofile, pop_code ] ]

    main:
    BIOC_SNPRELATE_IDENTITY_BY_STATE_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_SNPRELATE_IDENTITY_BY_STATE_CLUSTERING.out.tables
    plots    = BIOC_SNPRELATE_IDENTITY_BY_STATE_CLUSTERING.out.plots
    objects  = BIOC_SNPRELATE_IDENTITY_BY_STATE_CLUSTERING.out.objects
    versions = BIOC_SNPRELATE_IDENTITY_BY_STATE_CLUSTERING.out.versions
}
