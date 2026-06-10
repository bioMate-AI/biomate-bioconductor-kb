#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chemminer — chemical_structure_analysis_and_clustering
// Import small molecules, calculate physicochemical properties, generate descriptors, perform similarity searches, cluster the compounds, and visualize the result
// Input: sdfsample.sdf
// Container: quay.io/biocontainers/bioconductor-chemminer:3.62.0--r45ha27e39d_0
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
    .bm_deps <- c("chemminer", "fmcsr", "gplots", "rcurl", "rgl", "scatterplot3d")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(ChemmineR)
    
    # Stage 1: Import and validate SDF structures
    # Reading the user-provided local file "sdfsample.sdf"
    sdfset <- read.SDFset("sdfsample.sdf")
    valid <- validSDF(sdfset)
    sdfset <- sdfset[valid]
    
    # Stage 2: Calculate molecular weight, formula, and atom counts
    propma <- data.frame(MF=MF(sdfset), MW=MW(sdfset), atomcountMA(sdfset))
    write.csv(propma, "molecular_properties.csv", row.names = TRUE)
    
    # Stage 3: Generate atom pair descriptors
    apset <- sdf2ap(sdfset)
    saveRDS(apset, "atom_pair_descriptors.rds")
    
    # Stage 4: Perform structural similarity search
    search_results <- cmp.search(apset, apset[1], type=3, cutoff = 0.3, quiet=TRUE)
    write.csv(search_results, "similarity_search_results.csv", row.names = FALSE)
    
    # Stage 5: Cluster compounds using binning clustering
    clusters <- cmp.cluster(db=apset, cutoff = c(0.7, 0.8, 0.9), quiet = TRUE)
    write.csv(clusters, "compound_clusters.csv", row.names = FALSE)
    
    # Stage 6: Plot chemical structures
    pdf("chemical_structures.pdf", width = 8, height = 8)
    plot(sdfset[1:4], regenCoords=TRUE, print=FALSE)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CHEMMINER_CHEMICAL_STRUCTURE_ANALYSIS_AND_CLUSTERING":
        chemminer: \$(Rscript -e 'cat(as.character(packageVersion("chemminer")))')
    END_VERSIONS
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
