#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: meshes
// MeSH (Medical Subject Headings) is the NLM controlled vocabulary used to manually index articles for
//
// Source : https://yulab-smu.top/biomedical-knowledge-mining-book/013-meshes-semantic-similarity.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("meshes")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MESHES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-meshes"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-meshes:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-meshes:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_meshes_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_meshes_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_meshes_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(MeSHDb)
    library(jsonlite)

    # --- Supported organisms [] ---
    # Key functions: AnnotationHub, query, MeSHDb, meshdata
    #############################
    ## BioC 2.14 to BioC 3.13  ##
    #############################
    ##
    ## library(MeSH.Hsa.eg.db)
    ## db <- MeSH.Hsa.eg.db
    ##
    ##---------------------------
    
    # From BioC 3.14 (Nov. 2021, with R-4.2.0)
    library(AnnotationHub)
    library(MeSHDbi)
    # --- MeSH semantic similarity measurement [] ---
    # Key functions: meshSim
    library(meshes)
    meshSim("D000009", "D009130", semData=hsamd, measure="Resnik")
    
    meshSim("D000009", "D009130", semData=hsamd, measure="Rel")
    
    meshSim("D000009", "D009130", semData=hsamd, measure="Jiang")
    
    meshSim("D000009", "D009130", semData=hsamd, measure="Wang")
    
    meshSim(c("D001369", "D002462"), c("D017629", "D002890", "D008928"), semData=hsamd, measure="Wang")
    # --- Gene semantic similarity measurement [] ---
    # Key functions: geneSim
    geneSim("241", "251", semData=hsamd, measure="Wang", combine="BMA")
    
    geneSim(c("241", "251"), c("835", "5261","241", "994"), semData=hsamd, measure="Wang", combine="BMA")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_meshes_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_meshes_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_meshes_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MESHES:", paste0("    meshes: ", packageVersion("meshes"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meshes_results.csv
    touch ${prefix}_meshes_output.rds
    echo "BIOC_MESHES:" > versions.yml
    echo "    meshes: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MESHES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MESHES(ch_input)

    emit:
    results  = BIOC_MESHES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MESHES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MESHES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MESHES.out.versions  // channel: path(versions.yml)
}
