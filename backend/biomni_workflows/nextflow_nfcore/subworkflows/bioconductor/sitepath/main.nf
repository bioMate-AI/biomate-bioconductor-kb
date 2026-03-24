#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sitePath
// Using site polymorphism is one of the ways to cluster DNA/protein sequences but it is possible for t
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sitePath/inst/doc/sitePath.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("sitePath")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SITEPATH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sitepath"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sitepath:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sitepath:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sitepath_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sitepath_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sitepath_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SNPsites)
    library(jsonlite)

    # --- bad tree example [] ---
    # Key functions: ggtree
    bad_tree <- read.tree(system.file("extdata", "WNV.newick", package = "sitePath"))
    ggtree::ggtree(bad_tree) + ggplot2::ggtitle("Do not use a tree like this")
    # --- Import Sequence Alignment [] ---
    # Key functions: addMSA
    alignment_file <- system.file("extdata", "ZIKV.fasta", package = "sitePath")
    options(list("cl.cores" = 1)) # Set this bigger than 1 to use multiprocessing
    paths <- addMSA(tree, msaPath = alignment_file, msaFormat = "fasta")
    # --- Choose Threshold [] ---
    # Key functions: sneakPeek
    preassessment <- sneakPeek(paths, makePlot = TRUE)
    # --- Identify Phylogenetic Pathways [] ---
    # Key functions: lineagePath
    paths <- lineagePath(preassessment, 18)
    # --- Minimize Entropy [] ---
    # Key functions: sitesMinEntropy
    minEntropy <- sitesMinEntropy(paths)
    # --- Find Fixation Mutations [] ---
    # Key functions: fixationSites, allSitesName
    fixations <- fixationSites(minEntropy)
    allSites <- allSitesName(fixations)
    # --- Extract Site Path [] ---
    # Key functions: extractSite
    sp <- extractSite(fixations, 139)
    # --- Extract Tip Names [] ---
    # Key functions: extractTips
    extractTips(fixations, 139)
    # --- Plot Site Path [] ---
    # Key functions: plotSingleSite
    plot(sp)
    plotSingleSite(fixations, 139)
    # --- Find Parallel Mutations [] ---
    # Key functions: parallelSites, plotSingleSite
    plot(fixations)
    paraSites <- parallelSites(minEntropy, minSNP = 1, mutMode = "exact")
    plotSingleSite(paraSites, 105)
    # --- plot Single Site [] ---
    # Key functions: plotSingleSite
    plotSingleSite(paths, 139)
    plotSingleSite(paths, 763)
    # --- Find SNP Sites [] ---
    # Key functions: SNPsites, plotMutSites, plotSingleSite
    snps <- SNPsites(paths)
    plotMutSites(snps)
    plotSingleSite(paths, snps[4])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sitepath_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sitepath_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sitepath_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SITEPATH:", paste0("    sitepath: ", packageVersion("sitePath"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sitepath_results.csv
    touch ${prefix}_sitepath_output.rds
    echo "BIOC_SITEPATH:" > versions.yml
    echo "    sitepath: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SITEPATH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SITEPATH(ch_input)

    emit:
    results  = BIOC_SITEPATH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SITEPATH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SITEPATH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SITEPATH.out.versions  // channel: path(versions.yml)
}
