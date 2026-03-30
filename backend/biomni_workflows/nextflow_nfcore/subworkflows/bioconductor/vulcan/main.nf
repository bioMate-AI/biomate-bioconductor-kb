#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: vulcan
// Vulcan (VirtUaL ChIP-Seq Analysis through Networks) is a package that interrogates gene regulatory n
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/vulcan/inst/doc/vulcan.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("vulcan")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VULCAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-vulcan"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-vulcan:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-vulcan:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_vulcan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_vulcan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_vulcan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(vulcan)
    library(jsonlite)

    # --- Import [] ---
    # Key functions: import, vulcanexample, unlink
    # Import BAM and BED information into a list object
    # vobj<-vulcan.import(vfile)
    vobj<-vulcandata::vulcanexample()
    unlink(vfile)
    # --- Annotate [] ---
    # Key functions: annotate
    # Annotate peaks to gene names
    vobj<-vulcan.annotate(vobj,lborder=-10000,rborder=10000,method="sum")
    # --- Normalize [] ---
    # Key functions: normalize
    # Normalize data for VULCAN analysis
    vobj<-vulcan.normalize(vobj)
    # Detect which conditions are present in our imported object
    names(vobj$samples)
    # --- Vulcan [] ---
    # Key functions: vulcan
    vobj_analysis<-vulcan(vobj,network=network,contrast=c("t90","t0"),minsize=5)
    plot(vobj_analysis$msviper,mrs=7)
    # --- Setnames [] ---
    # Key functions: setNames, rnorm, sample, gsea
    reflist<-setNames(-sort(rnorm(1000)),paste0("gene",1:1000))
    set<-paste0("gene",sample(1:200,50))
    obj<-gsea(reflist,set,method="pareto")
    obj$p.value
    # --- Setnames [] ---
    # Key functions: setNames, rnorm, sample, rea
    signatures<-setNames(-sort(rnorm(1000)),paste0("gene",1:1000))
    set1<-paste0("gene",sample(1:200,50))
    set2<-paste0("gene",sample(1:1000,50))
    groups<-list(set1=set1,set2=set2)
    obj<-rea(signatures=signatures,groups=groups)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_vulcan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_vulcan_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_vulcan_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VULCAN:", paste0("    vulcan: ", packageVersion("vulcan"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vulcan_results.csv
    touch ${prefix}_vulcan_output.rds
    echo "BIOC_VULCAN:" > versions.yml
    echo "    vulcan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VULCAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VULCAN(ch_input)

    emit:
    results  = BIOC_VULCAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VULCAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VULCAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VULCAN.out.versions  // channel: path(versions.yml)
}
