#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chemminer — chemical_structure_analysis_and_clustering
// Import small molecules, calculate physicochemical properties, generate descriptors, perform similarity searches, cluster the compounds, and visualize the result
// Input: sdfsample.sdf
// Container: quay.io/biocontainers/bioconductor-chemminer:3.62.0--r45ha27e39d_0
// R packages: ChemmineR, fmcsR, gplots, rcurl, rgl, scatterplot3d
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHEMMINER_CHEMICAL_STRUCTURE_ANALYSIS_AND_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chemminer:3.62.0--r45ha27e39d_0"

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
    .bm_deps <- c("ChemmineR", "fmcsR", "gplots", "rcurl", "rgl", "scatterplot3d")
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
    
    # Load required library
    library(ChemmineR)
    
    # --- Import and validate SDF structures ---
    # Reading the user-provided local file "sdfsample.sdf"
    sdfset <- read.SDFset("sdfsample.sdf")
    valid <- validSDF(sdfset)
    sdfset <- sdfset[valid]
    
    # --- Calculate molecular weight, formula, and atom counts ---
    propma <- data.frame(MF=MF(sdfset), MW=MW(sdfset), atomcountMA(sdfset))
    write.csv(propma, "molecular_properties.csv", row.names = TRUE)
    
    # --- Generate atom pair descriptors ---
    apset <- sdf2ap(sdfset)
    saveRDS(apset, "atom_pair_descriptors.rds")
    
    # --- Perform structural similarity search ---
    search_results <- cmp.search(apset, apset[1], type=3, cutoff = 0.3, quiet=TRUE)
    write.csv(search_results, "similarity_search_results.csv", row.names = FALSE)
    
    # --- Cluster compounds using binning clustering ---
    clusters <- cmp.cluster(db=apset, cutoff = c(0.7, 0.8, 0.9), quiet = TRUE)
    write.csv(clusters, "compound_clusters.csv", row.names = FALSE)
    
    # --- Plot chemical structures ---
    pdf("chemical_structures.pdf", width = 8, height = 8)
    plot(sdfset[1:4], regenCoords=TRUE, print=FALSE)
    dev.off()

    writeLines(c(
        '"BIOC_CHEMMINER_CHEMICAL_STRUCTURE_ANALYSIS_AND_CLUSTERING":',
        paste0('        chemminer: ', as.character(packageVersion("chemminer")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chemical_structure_analysis_and_clustering.csv versions.yml
    """
}

workflow BIOC_CHEMMINER_CHEMICAL_STRUCTURE_ANALYSIS_AND_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sdfsample.sdf ] ]

    main:
    BIOC_CHEMMINER_CHEMICAL_STRUCTURE_ANALYSIS_AND_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_CHEMMINER_CHEMICAL_STRUCTURE_ANALYSIS_AND_CLUSTERING.out.tables
    plots    = BIOC_CHEMMINER_CHEMICAL_STRUCTURE_ANALYSIS_AND_CLUSTERING.out.plots
    objects  = BIOC_CHEMMINER_CHEMICAL_STRUCTURE_ANALYSIS_AND_CLUSTERING.out.objects
    versions = BIOC_CHEMMINER_CHEMICAL_STRUCTURE_ANALYSIS_AND_CLUSTERING.out.versions
}
