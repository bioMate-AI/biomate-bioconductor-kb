#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DeepTarget
// This package predicts a drug’s primary target(s) or secondary target(s) by integrating large-scale g
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DeepTarget/inst/doc/DeepTarget_Vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DeepTarget")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEEPTARGET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-deeptarget"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-deeptarget:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-deeptarget:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_deeptarget_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_deeptarget_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_deeptarget_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DMB)
    library(DTR)
    library(PredMaxSim)
    library(PredTarget)
    library(jsonlite)

    # --- Computing a correlation between the every gene crispr KO vs each drug response for all interesting drugs [] ---
    # Key functions: computeCor

    # --- section.cap="Predicting Similarity Across Known Targeted Genes and All Genes" [] ---
    # Key functions: PredTarget, PredMaxSim
    DrugTarcomputeCor <- PredTarget(List.sim,metadata)
    DrugGeneMaxSim <- PredMaxSim(List.sim,metadata)
    # --- Calculating Drug KO Similarities in cell lines with low primary target [] ---
    # Key functions: computeCor

    # --- Finding a primary target [] ---
    # Key functions: plotCor
    plotCor(DOI,GOI,Pred.d,sec.prism.f,KO.GES,plot=TRUE)
    # --- Predicting whether the drug specifically targets the wild [] ---
    # Key functions: DMB, form
    Pred.d.f <- Pred.d[,c(1:3,12:15)]
    Pred.d.f.f <- Pred.d.f[which (Pred.d.f$predicted_resistance_mut==TRUE), ]
    DRS=as.data.frame(sec.prism.f[DrugID,])
    # --- Predicting secondary target [] ---
    # Key functions: DTR
    identical (Pred.d$DrugID, row.names(sec.prism.f))
    DRS <- as.data.frame(sec.prism.f[14,])
    DRS <- t(DRS)
    # --- Predicting secondary target(s) that mediate its response when the primary target is not expressed [] ---
    # Key functions: plotSim
    sim.LowExp.Strength=vapply(sim.LowExp, function(x) x[,2],FUN.VALUE = numeric(nrow(sim.LowExp[[1]])))
    dim(sim.LowExp.Strength)
    sim.LowExp.Pval=vapply(sim.LowExp, function(x) x[,1], FUN.VALUE = numeric(nrow(sim.LowExp[[1]])))
    # --- Conclusion [] ---
    # Key functions: DTR
    out <- DTR (DOI,GOI,Pred.d[14,],d.expr,DRS,KO.GES,CutOff= 2)
    print (out)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_deeptarget_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_deeptarget_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_deeptarget_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEEPTARGET:", paste0("    deeptarget: ", packageVersion("DeepTarget"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_deeptarget_results.csv
    touch ${prefix}_deeptarget_output.rds
    echo "BIOC_DEEPTARGET:" > versions.yml
    echo "    deeptarget: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEEPTARGET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DEEPTARGET(ch_input)

    emit:
    results  = BIOC_DEEPTARGET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEEPTARGET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEEPTARGET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEEPTARGET.out.versions  // channel: path(versions.yml)
}
