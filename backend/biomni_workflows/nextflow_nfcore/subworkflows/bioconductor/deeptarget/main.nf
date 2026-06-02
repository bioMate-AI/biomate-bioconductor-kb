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
    library(DeepTarget)
    library(DMB)
    library(DTR)
    library(PredMaxSim)
    library(PredTarget)
    library(jsonlite)

    # --- Target Prediction [] ---
    # Key functions: PredTarget, PredMaxSim
    metadata <- OntargetM$DrugMetadata
    DrugTarcomputeCor <- PredTarget(List.sim, metadata)
    DrugGeneMaxSim <- PredMaxSim(List.sim, metadata)


    # --- Interaction Modeling [] ---
    # Key functions: DoInteractMutant, DoInteractExp
    d.mt <- OntargetM$mutations_mat
    d.expr <- OntargetM$expression_20Q4
    out.MutantTarget <- NULL
    out.LowexpTarget <- NULL
    for (i in seq_len(nrow(sec.prism.f))) {
        DRS <- as.data.frame(sec.prism.f[i, , drop = FALSE])
        Out.M <- DoInteractMutant(
            DrugTarcomputeCor[i, ], d.mt, DRS, KO.GES
        )
        TargetMutSpecificity <- data.frame(
            MaxTgt_Inter_Mut_strength = vapply(
                Out.M, function(x) x[1], numeric(1)
            ),
            MaxTgt_Inter_Mut_Pval = vapply(
                Out.M, function(x) x[2], numeric(1)
            )
        )
        out.MutantTarget <- rbind(out.MutantTarget, TargetMutSpecificity)
        Out.Expr <- DoInteractExp(
            DrugTarcomputeCor[i, ], d.expr, DRS, KO.GES, CutOff = 2
        )
        TargetExpSpecificity <- data.frame(
            MaxTgt_Inter_Exp_strength = vapply(
                Out.Expr, function(x) x[1], numeric(1)
            ),
            MaxTgt_Inter_Exp_Pval = vapply(
                Out.Expr, function(x) x[2], numeric(1)
            )
        )
        out.LowexpTarget <- rbind(out.LowexpTarget, TargetExpSpecificity)
    }


    # --- Low Expression Analysis [] ---
    # Key functions: computeCor
    predicted_resistance_mut <- ifelse(
        out.MutantTarget$MaxTgt_Inter_Mut_Pval < 0.1, TRUE, FALSE
    )
    Whether_interaction_Ex_based <- ifelse(
        out.LowexpTarget$MaxTgt_Inter_Exp_strength < 0 & 
        out.LowexpTarget$MaxTgt_Inter_Exp_Pval < 0.2, TRUE, FALSE
    )
    Pred.d <- cbind(
        DrugTarcomputeCor, DrugGeneMaxSim, 
        out.MutantTarget, predicted_resistance_mut
    )
    mutant.C <- vapply(
        Pred.d[, 3], 
        function(x) tryCatch(sum(d.mt[x, ] == 1), error = function(e) NA), 
        FUN.VALUE = numeric(1)
    )
    Pred.d$mutant.C <- mutant.C
    Low.Exp.C <- vapply(
        Pred.d[, 3], 
        function(x) tryCatch(sum(d.expr[x, ] < 2), error = function(e) NA), 
        FUN.VALUE = numeric(1)
    )
    Pred.d <- cbind(
        Pred.d, out.LowexpTarget, 
        Whether_interaction_Ex_based, Low.Exp.C
    )
    Low.i <- which(Pred.d$Low.Exp.C > 5)
    Pred.d.f <- Pred.d[Low.i, ]
    Low.Exp.G <- list()
    for (i in seq_len(nrow(Pred.d.f))) {
        Gene.i <- Pred.d.f[, 3][i]
        Temp <- tryCatch(
            names(which(d.expr[Gene.i, ] < 2)), 
            error = function(e) NA
        )
        Low.Exp.G[[Pred.d.f[, 3][i]]] <- Temp
    }
    sim.LowExp <- list()
    sec.prism.f.f <- sec.prism.f[Low.i, , drop = FALSE]
    for (i in seq_len(nrow(Pred.d.f))) {
        DRS.L <- sec.prism.f.f[
            i, Low.Exp.G[[unlist(Pred.d.f[i, 3])]], drop = FALSE
        ]
        out <- computeCor(Pred.d.f[i, 1], DRS.L, KO.GES)
        sim.LowExp[[Pred.d.f[i, 1]]] <- out
    }


    # --- Visualization [] ---
    # Key functions: plotCor, DMB
    DOI <- 'AMG-232'
    GOI <- 'MDM2'
    plotCor(DOI, GOI, Pred.d, sec.prism.f, KO.GES, plot = TRUE)
    Pred.d.f <- Pred.d[, c(1:3, 12:15)]
    Pred.d.f.f <- Pred.d.f[which(Pred.d.f$predicted_resistance_mut == TRUE), ]
    if (nrow(Pred.d.f.f) > 0) {
        DOI <- Pred.d.f.f$drugName[1]
        GOI <- Pred.d.f.f$MaxTargetName[1]
        DrugID <- Pred.d.f.f$DrugID[1]
        DRS <- as.data.frame(sec.prism.f[DrugID, , drop = FALSE])
        out_dmb <- DMB(
            DOI, GOI, Pred.d.f.f[1, ], d.mt, DRS, KO.GES, plot = TRUE
        )
    }

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
