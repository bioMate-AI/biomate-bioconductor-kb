#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowMatch — template_construction_and_metaclustering
// Build a representative template and meta-clusters from a collection of multiple clustered flow cytometry samples, and visualize the results.
// Input: sample_list.rds
// Container: quay.io/biocontainers/bioconductor-flowmatch:1.46.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowMatch
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Loop through each sample, cluster it, and create ClusteredSample objects. 2. Store all ClusteredSample objects in a list. 3. Const

nextflow.enable.dsl = 2

process BIOC_FLOWMATCH_TEMPLATE_CONSTRUCTION_AND_METACLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(flowMatch)
    
    # Read user input
    sample_list <- readRDS("sample_list.rds")
    
    # Set seed for reproducible clustering
    set.seed(1234)
    
    # 1. Loop through each sample, cluster it, and create ClusteredSample objects.
    # 2. Store all ClusteredSample objects in a list.
    clustSamples = list()
    for(i in 1:length(sample_list))
    {
      sample1 = sample_list[[i]]
      clust1 = kmeans(sample1, centers=4, nstart=20)
      cluster.labels1 = clust1\$cluster
      clustSample1 = ClusteredSample(labels=cluster.labels1, sample=sample1)
      clustSamples = c(clustSamples, clustSample1)
    }
    
    # 3. Construct a template from the list of clustered samples using create.template.
    template = create.template(clustSamples)
    
    # Save template summary to a text file
    sink("template_summary.txt")
    summary(template)
    sink()
    
    # Save template object
    saveRDS(template, "template.rds")
    
    # 4. Visualize the hierarchical relationship of the samples using template.tree.
    pdf("template_tree.pdf")
    template.tree(template)
    dev.off()
    
    # 5. Plot the template contours using various visualization options.
    pdf("template_plots.pdf")
    plot(template)
    plot(template, color.mc=c('blue','black','green3','red'))
    plot(template, plot.mc=TRUE, color.mc=c('blue','black','green3','red'))
    plot(template, colorbysample=TRUE)
    dev.off()
    
    # 6. Retrieve, summarize, and plot individual meta-clusters.
    mc = get.metaClusters(template)[[1]]
    
    sink("metacluster_summary.txt")
    summary(mc)
    sink()
    
    # Save meta-cluster object
    saveRDS(mc, "metacluster_1.rds")
    
    pdf("metacluster_plots.pdf")
    plot(mc)
    plot(mc, plot.mc=TRUE)
    dev.off()

    writeLines(c(
        '"BIOC_FLOWMATCH_TEMPLATE_CONSTRUCTION_AND_METACLUSTERING":',
        paste0('    flowMatch: ', as.character(packageVersion('flowMatch')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_template_construction_and_metaclustering.csv versions.yml
    """
}

workflow BIOC_FLOWMATCH_TEMPLATE_CONSTRUCTION_AND_METACLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_list.rds ] ]

    main:
    BIOC_FLOWMATCH_TEMPLATE_CONSTRUCTION_AND_METACLUSTERING(ch_input)

    emit:
    tables   = BIOC_FLOWMATCH_TEMPLATE_CONSTRUCTION_AND_METACLUSTERING.out.tables
    plots    = BIOC_FLOWMATCH_TEMPLATE_CONSTRUCTION_AND_METACLUSTERING.out.plots
    objects  = BIOC_FLOWMATCH_TEMPLATE_CONSTRUCTION_AND_METACLUSTERING.out.objects
    versions = BIOC_FLOWMATCH_TEMPLATE_CONSTRUCTION_AND_METACLUSTERING.out.versions
}
