#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rBiopaxParser
// Parses BioPAX files and represents them in R, at the moment BioPAX level 2 and level 3 are supported
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rBiopaxParser/inst/doc/rBiopaxParserVignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rBiopaxParser")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBIOPAXPARSER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rbiopaxparser"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rbiopaxparser:2.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rbiopaxparser:2.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rbiopaxparser_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rbiopaxparser_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rbiopaxparser_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rBiopaxParser)
    library(jsonlite)

    # --- Extract Pathway Components [] ---
    # Key functions: listPathwayComponents, selectInstances
    data(biopaxexample)
    pwid1 <- "pid_p_100002_wntpathway"
    pw_1_component_list <- listPathwayComponents(biopax, pwid1)
    pw_1_components <- selectInstances(
        biopax,
        id=pw_1_component_list$id
    )


    # --- Build BioPAX Model Entities [] ---
    # Key functions: createBiopax, addPhysicalEntity, addPhysicalEntityParticipant, addBiochemicalReaction
    biopax <- createBiopax()
    for(i in LETTERS[1:5]) {
        biopax <- addPhysicalEntity(biopax, class="protein",
            NAME=paste("protein", i, sep="_"), 
            id=paste("proteinid", i, sep="_"))
        biopax <- addPhysicalEntityParticipant(biopax,
            referencedPhysicalEntityID=paste("proteinid", i, sep="_"), 
            id=paste("PEPid", i, sep="_"))
        biopax <- addBiochemicalReaction(biopax,
            LEFT=paste("PEPid", i, sep="_"),
            RIGHT=paste("PEPid", i, sep="_"),
            id=paste("BCRid", i, sep="_"))
    }


    # --- Define Regulatory Controls [] ---
    # Key functions: addControl
    biopax <- addControl(biopax, CONTROL_TYPE="ACTIVATION",
        CONTROLLER="PEPid_A", CONTROLLED=c("BCRid_B"), id="control_1")
    biopax <- addControl(biopax, CONTROL_TYPE="INHIBITION",
        CONTROLLER="PEPid_A", CONTROLLED=c("BCRid_C"), id="control_2")
    biopax <- addControl(biopax, CONTROL_TYPE="ACTIVATION",
        CONTROLLER="PEPid_C", CONTROLLED=c("BCRid_D"), id="control_3")
    biopax <- addControl(biopax, CONTROL_TYPE="INHIBITION",
        CONTROLLER="PEPid_C", CONTROLLED=c("BCRid_E"), id="control_4")


    # --- Assemble and Merge Pathways [] ---
    # Key functions: addPathway, mergePathways
    biopax <- addPathway(biopax, NAME="pw1",
        PATHWAY_COMPONENTS=c("control_1", "control_2"), id="pwid1")
    biopax <- addPathway(biopax, NAME="pw2",
        PATHWAY_COMPONENTS=c("control_3", "control_4"), id="pwid2")
    biopax <- mergePathways(biopax, "pwid1", "pwid2",
        NAME="pw3", id="pwid3")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rbiopaxparser_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rbiopaxparser_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rbiopaxparser_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RBIOPAXPARSER:", paste0("    rbiopaxparser: ", packageVersion("rBiopaxParser"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rbiopaxparser_results.csv
    touch ${prefix}_rbiopaxparser_output.rds
    echo "BIOC_RBIOPAXPARSER:" > versions.yml
    echo "    rbiopaxparser: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RBIOPAXPARSER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RBIOPAXPARSER(ch_input)

    emit:
    results  = BIOC_RBIOPAXPARSER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RBIOPAXPARSER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RBIOPAXPARSER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RBIOPAXPARSER.out.versions  // channel: path(versions.yml)
}
