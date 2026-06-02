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

    # --- Downloadbiopax [] ---
    # Key functions: downloadBiopaxData
    ## file = downloadBiopaxData("NCI","biocarta")
    # --- Parsebiopax [] ---
    # Key functions: readBiopax
    ## biopax = readBiopax(file)
    ## print(biopax)
    # --- Accessingbiopax [] ---
    # Key functions: listInstances, selectInstances, getInstanceProperty, listPathwayComponents
    pw_list = listInstances(biopax, class="pathway")
    pw_complete = selectInstances(biopax, class="pathway")
    pwid1 = "pid_p_100002_wntpathway"
    pwid2 = "pid_p_100146_hespathway"
    getInstanceProperty(biopax, pwid1, property="NAME")
    # --- Pathwaytoregulatorygraphs [] ---
    # Key functions: pathway2AdjacancyMatrix, pathway2RegulatoryGraph
    ## pw_1_adj = pathway2AdjacancyMatrix(biopax, pwid1, expandSubpathways=TRUE,
    ## splitComplexMolecules=TRUE, verbose=TRUE)
    ## pw_1_graph = pathway2RegulatoryGraph(biopax, pwid1,
    ## splitComplexMolecules=TRUE, verbose=TRUE)
    ## pw_2_adj = pathway2AdjacancyMatrix(biopax, pwid2, expandSubpathways=TRUE,
    # --- Layoutgraphs [] ---
    # Key functions: layoutRegulatoryGraph
    ## pw_1_graph_laidout = layoutRegulatoryGraph(pw_1_graph)
    ## pw_2_graph_laidout = layoutRegulatoryGraph(pw_2_graph)
    # --- Plotgraphs [] ---
    # Key functions: plotRegulatoryGraph
    ## plotRegulatoryGraph(pw_1_graph)
    ## plotRegulatoryGraph(pw_2_graph)
    # --- Mergedgraph [] ---
    # Key functions: uniteGraphs, plotRegulatoryGraph
    ## merged_graph = uniteGraphs(pw_1_graph_laidout,pw_2_graph_laidout)
    ## plotRegulatoryGraph(merged_graph, layoutGraph=FALSE)
    # --- Beautifygraphs [] ---
    # Key functions: nodeRenderInfo, plotRegulatoryGraph
    ## nodeRenderInfo(merged_graph)$cex = 1
    ## nodeRenderInfo(merged_graph)$textCol = "red"
    ## nodeRenderInfo(merged_graph)$fill = "green"
    ## plotRegulatoryGraph(merged_graph, layoutGraph=FALSE)
    # --- Modifypathways [] ---
    # Key functions: mergePathways, pathway2RegulatoryGraph, plotRegulatoryGraph, layoutRegulatoryGraph
    ## biopax = mergePathways(biopax, pwid1, pwid2, NAME="mergedpw1", ID="mergedpwid1")
    ## mergedpw_graph = pathway2RegulatoryGraph(biopax,
    ## 		"mergedpwid1", splitComplexMolecules=TRUE, verbose=TRUE)
    ## plotRegulatoryGraph(layoutRegulatoryGraph(mergedpw_graph))
    # --- Createbiopax1 [] ---
    # Key functions: createBiopax, addPhysicalEntity, addPhysicalEntityParticipant, addBiochemicalReaction
    biopax = createBiopax()
    for(i in LETTERS[1:5]) {
    	biopax = addPhysicalEntity(biopax, class="protein",
    		NAME=paste("protein",i,sep="_"),
    		id=paste("proteinid",i,sep="_"))
    # --- Createbiopax2 [] ---
    # Key functions: addControl
    biopax = addControl(biopax, CONTROL_TYPE="ACTIVATION",
    	CONTROLLER="PEPid_A", CONTROLLED=c("BCRid_B"),id="control_1")
    biopax = addControl(biopax, CONTROL_TYPE="INHIBITION",
    	CONTROLLER="PEPid_A", CONTROLLED=c("BCRid_C"),id="control_2")
    biopax = addControl(biopax, CONTROL_TYPE="ACTIVATION",
    # --- Createbiopax3 [] ---
    # Key functions: addPathway, mergePathways
    biopax = addPathway(biopax, NAME="pw1",
    	PATHWAY_COMPONENTS=c("control_1","control_2"), id="pwid1")
    biopax = addPathway(biopax, NAME="pw2",
    	PATHWAY_COMPONENTS=c("control_3","control_4"), id="pwid2")
    biopax = mergePathways(biopax, "pwid1", "pwid2", NAME="pw3", id="pwid3")
    # --- Createbiopax4 [] ---
    # Key functions: pathway2RegulatoryGraph
    ## pw1_graph = pathway2RegulatoryGraph(biopax, "pwid1",
    ## 	splitComplexMolecules=TRUE, verbose=TRUE)
    ## pw2_graph = pathway2RegulatoryGraph(biopax, "pwid2",
    ## 	splitComplexMolecules=TRUE, verbose=TRUE)
    ## pw3_graph = pathway2RegulatoryGraph(biopax, "pwid3",
    # --- Createbiopax5 [] ---
    # Key functions: plotRegulatoryGraph, layoutRegulatoryGraph
    ## plotRegulatoryGraph(layoutRegulatoryGraph(pw1_graph))
    ## plotRegulatoryGraph(layoutRegulatoryGraph(pw2_graph))
    ## plotRegulatoryGraph(layoutRegulatoryGraph(pw3_graph))
    # --- Removebiopaxinstances [] ---
    # Key functions: removeProperties, removeInstance
    ## temp = biopax
    ## temp = removeProperties(temp, id="newpwid2", properties="PATHWAY-COMPONENTS")
    ## temp = removeInstance(temp, id="newpwid3")

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
