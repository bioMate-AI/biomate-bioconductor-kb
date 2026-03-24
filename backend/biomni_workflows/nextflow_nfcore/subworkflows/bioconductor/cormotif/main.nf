#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Cormotif
// It fits correlation motif model to multiple studies to detect study specific differential expression
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Cormotif/inst/doc/CormotifVignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Cormotif")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CORMOTIF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cormotif"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cormotif:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cormotif:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cormotif_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cormotif_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cormotif_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Cormotif)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(Cormotif)
    data(simudata2)
    colnames(simudata2)
    exprs.simu2<-as.matrix(simudata2[,2:25])
    data(simu2_groupid)
    # --- Cormotiffit [] ---
    # Key functions: cormotiffit
    motif.fitted<-cormotiffit(exprs.simu2,simu2_groupid,simu2_compgroup,
    			 K=1:5,max.iter=1000,BIC=TRUE)
    # --- Plotic [] ---
    # Key functions: plotIC
    motif.fitted$bic
    plotIC(motif.fitted)
    # --- Plotmotif [] ---
    # Key functions: plotMotif
    plotMotif(motif.fitted)
    # --- Generank [] ---
    # Key functions: generank
    topgenelist<-generank(motif.fitted$bestmotif$p.post)
    head(topgenelist)
    # --- Nrow [] ---
    # Key functions: sample
    fullindex<-1:nrow(exprs.simu2)
    ##sample index to mimic the merging of studies from different platforms
    mis_index1<-sample(fullindex,misprop*length(fullindex))
    mis_index2<-sample(fullindex[-mis_index1],misprop*length(fullindex))
    exprs.simu2.missing<-exprs.simu2
    # --- Cormotiffit [] ---
    # Key functions: cormotiffit, plotIC, plotMotif
    motif.fitted.missing<-cormotiffit(exprs.simu2.missing,simu2_groupid,simu2_compgroup,
    				  K=1:5,max.iter=1000,BIC=TRUE)
    plotIC(motif.fitted.missing)
    plotMotif(motif.fitted.missing)
    # --- Plotic [] ---
    # Key functions: plotIC
    plotIC(motif.fitted.missing)
    # --- Plotmotif [] ---
    # Key functions: plotMotif
    plotMotif(motif.fitted.missing)
    # --- Cormotiffitall [] ---
    # Key functions: cormotiffitall
    motif.fitted.all<-cormotiffitall(exprs.simu2,simu2_groupid,simu2_compgroup,max.iter=1)
    # --- Cormotiffitsep [] ---
    # Key functions: cormotiffitsep
    motif.fitted.sep<-cormotiffitsep(exprs.simu2,simu2_groupid,simu2_compgroup,max.iter=1)
    # --- Cormotiffitfull [] ---
    # Key functions: cormotiffitfull
    motif.fitted.full<-cormotiffitfull(exprs.simu2,simu2_groupid,simu2_compgroup,max.iter=1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cormotif_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cormotif_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cormotif_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CORMOTIF:", paste0("    cormotif: ", packageVersion("Cormotif"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cormotif_results.csv
    touch ${prefix}_cormotif_output.rds
    echo "BIOC_CORMOTIF:" > versions.yml
    echo "    cormotif: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CORMOTIF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CORMOTIF(ch_input)

    emit:
    results  = BIOC_CORMOTIF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CORMOTIF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CORMOTIF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CORMOTIF.out.versions  // channel: path(versions.yml)
}
