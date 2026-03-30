#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: immunogenViewer
// Plots protein properties and visualizes position of peptide immunogens within protein sequence. Allo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/immunogenViewer/inst/doc/immunogenViewer_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("immunogenViewer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IMMUNOGENVIEWER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-immunogenviewer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-immunogenviewer:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-immunogenviewer:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_immunogenviewer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_immunogenviewer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_immunogenviewer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(immunogenViewer)
    library(jsonlite)

    # --- get Protein Features [] ---
    # Key functions: getProteinFeatures, datatable
    protein <- getProteinFeatures("Q9NZC2")
    DT::datatable(protein, width = "80%", options = list(scrollX = TRUE))
    # --- add Immunogen [] ---
    # Key functions: addImmunogen
    protein <- addImmunogen(protein, start = 142, end = 192, name = "ABIN2783734_")
    protein <- addImmunogen(protein, start = 196, end = 230, name = "HPA010917")
    protein <- addImmunogen(protein, seq = "HGQKPGTHPPSELD", name = "EB07921")
    # --- rename Immunogen [] ---
    # Key functions: renameImmunogen
    protein <- renameImmunogen(protein, oldName = "ABIN2783734_", newName = "ABIN2783734")
    colnames(protein)
    # --- remove Immunogen [] ---
    # Key functions: removeImmunogen
    protein <- removeImmunogen(protein, name = "HPA010917")
    colnames(protein)
    # --- visualize protein [] ---
    # Key functions: plotProtein
    plotProtein(protein)
    # --- visualize immunogen [] ---
    # Key functions: plotImmunogen
    plotImmunogen(protein, "ABIN2783734")
    # --- evaluate Immunogen [] ---
    # Key functions: evaluateImmunogen, datatable
    immunogens <- evaluateImmunogen(protein)
    DT::datatable(immunogens, width = "80%", options = list(scrollX = TRUE))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_immunogenviewer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_immunogenviewer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_immunogenviewer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IMMUNOGENVIEWER:", paste0("    immunogenviewer: ", packageVersion("immunogenViewer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_immunogenviewer_results.csv
    touch ${prefix}_immunogenviewer_output.rds
    echo "BIOC_IMMUNOGENVIEWER:" > versions.yml
    echo "    immunogenviewer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IMMUNOGENVIEWER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IMMUNOGENVIEWER(ch_input)

    emit:
    results  = BIOC_IMMUNOGENVIEWER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IMMUNOGENVIEWER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IMMUNOGENVIEWER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IMMUNOGENVIEWER.out.versions  // channel: path(versions.yml)
}
