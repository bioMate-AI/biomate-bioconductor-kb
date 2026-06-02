#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RMassBank
// Workflow to process tandem MS files and build MassBank records.  Functions include automated extract
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RMassBank/inst/doc/RMassBank.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RMassBank")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RMASSBANK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rmassbank"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rmassbank:3.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rmassbank:3.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rmassbank_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rmassbank_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rmassbank_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RMassBank)
    library(jsonlite)


    # --- Eval=true [] ---
    # Key functions: file.copy
    file.copy(system.file("list/NarcoticsDataset.csv", 
    	package="RMassBankData"), "./Compoundlist.csv")

    # --- Eval=true [] ---
    # Key functions: RmbSettingsTemplate, mysettings.ini
    RmbSettingsTemplate("mysettings.ini")

    # --- Eval=true [] ---
    # Key functions: msmsWorkflow, pH_narcotics
    w <- msmsWorkflow(w, mode="pH", steps=c(1:4), archivename = 
    				"pH_narcotics")

    # --- Eval=true [] ---
    # Key functions: loadMsmsWorkspace
    # In the really evaluated workflow, we do the following:
    # we run steps 1 through 3, load the recalibration curve from a stored workflow
    # and recalibrate the data using that curve.
    storedW <- loadMsmsWorkspace(system.file("results/pH_narcotics_RF.RData", 
    				package="RMassBankData"))

    # --- Fig=true [] ---
    # Key functions: msmsWorkflow, pH_narcotics
    # Just to display the recalibration curve as calculated from
    # the complete dataset:
    storedW <- msmsWorkflow(storedW, mode="pH", steps=4)
    # Copy the recalibration to workspace w and apply it
    # (no graph displayed here)
    w@rc <- storedW@parent@rc
    w@rc.ms1 <- storedW@parent@rc.ms1
    w <- msmsWorkflow(w, mode="pH", steps=4, archivename = 
    	"pH_narcotics", newRecalibration = FALSE)

    # --- Eval=false [] ---
    # Key functions: archiveResults, newMbWorkspace, resetInfolists, loadInfolists, infolists_incomplete
    #  archiveResults(w, filename)

    ## -----------------------------------------------------------------------
    mb <- newMbWorkspace(w)
    mb <- resetInfolists(mb)
    mb <- loadInfolists(mb, system.file("infolists_incomplete",
    		package="RMassBankData"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rmassbank_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rmassbank_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rmassbank_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RMASSBANK:", paste0("    rmassbank: ", packageVersion("RMassBank"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rmassbank_results.csv
    touch ${prefix}_rmassbank_output.rds
    echo "BIOC_RMASSBANK:" > versions.yml
    echo "    rmassbank: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RMASSBANK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RMASSBANK(ch_input)

    emit:
    results  = BIOC_RMASSBANK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RMASSBANK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RMASSBANK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RMASSBANK.out.versions  // channel: path(versions.yml)
}
