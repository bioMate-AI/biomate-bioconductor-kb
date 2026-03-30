#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RCy3
// Vizualize, analyze and explore networks using Cytoscape via R. Anything you can do using the graphic
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RCy3/inst/doc/Cancer-networks-and-data.R
// Upstream  : RColorBrewer, ndexr
// Downstream: none
//
// Install: BiocManager::install("RCy3")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RCY3 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rcy3"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rcy3:2.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rcy3:2.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rcy3_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rcy3_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rcy3_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RCy3)
    library(jsonlite)

    # --- Cytoscapeping [] ---
    # Key functions: cytoscapePing
    ---------------------------------------------------------------------
    #  cytoscapePing()
    # --- Commandsrun [] ---
    # Key functions: commandsRun
    ---------------------------------------------------------------------
    #  string.cmd = 'string disease query disease="breast cancer" cutoff=0.9 species="Homo sapiens" limit=150'
    #  commandsRun(string.cmd)
    # --- Getnetworklist [] ---
    # Key functions: getNetworkList
    ---------------------------------------------------------------------
    #  getNetworkList()
    # --- Layoutnetwork [] ---
    # Key functions: layoutNetwork
    ---------------------------------------------------------------------
    #  layoutNetwork(layout.name='circular')
    # --- Getlayoutnames [] ---
    # Key functions: getLayoutNames
    ---------------------------------------------------------------------
    #  getLayoutNames()
    # --- Getlayoutpropertynames [] ---
    # Key functions: getLayoutPropertyNames, layoutNetwork
    ---------------------------------------------------------------------
    #  getLayoutPropertyNames(layout.name='force-directed')
    #  layoutNetwork('force-directed defaultSpringCoefficient=0.0000008 defaultSpringLength=70')
    # --- Gettablecolumnnames [] ---
    # Key functions: getTableColumnNames
    ---------------------------------------------------------------------
    #  getTableColumnNames('node')
    # --- Gettablecolumns [] ---
    # Key functions: getTableColumns
    ---------------------------------------------------------------------
    #  disease.score.table <- getTableColumns('node','stringdb::disease score')
    #  disease.score.table
    # --- Quantile [] ---
    # Key functions: createSubnetwork
    ---------------------------------------------------------------------
    #  top.quart <- quantile(disease.score.table[,1], 0.75)
    #  top.nodes <- row.names(disease.score.table)[which(disease.score.table[,1]>top.quart)]
    #  createSubnetwork(top.nodes,subnetwork.name ='top disease quartile')
    #  #returns a Cytoscape network SUID
    # --- Createsubnetwork [] ---
    # Key functions: createSubnetwork
    ---------------------------------------------------------------------
    #  createSubnetwork(edges='all',subnetwork.name='top disease quartile connected')  #handy way to exclude unconnected nodes!
    # --- Setcurrentnetwork [] ---
    # Key functions: setCurrentNetwork, selectNodes, selectFirstNeighbors, createSubnetwork, edges
    ---------------------------------------------------------------------
    #  setCurrentNetwork(network="STRING network - ovarian cancer")
    #  top.nodes <- row.names(disease.score.table)[tail(order(disease.score.table[,1]),3)]
    #  selectNodes(nodes=top.nodes)
    #  selectFirstNeighbors()
    # --- Setcurrentnetwork [] ---
    # Key functions: setCurrentNetwork, selectNodes, commandsPOST, createSubnetwork, layoutNetwork
    ---------------------------------------------------------------------
    #  setCurrentNetwork(network="STRING network - ovarian cancer")
    #  selectNodes(nodes=top.nodes)
    #  commandsPOST('diffusion diffuse') # diffusion!
    #  createSubnetwork('selected',subnetwork.name = 'top disease diffusion')
    # --- Setcurrentnetwork [] ---
    # Key functions: setCurrentNetwork, layoutNetwork
    ---------------------------------------------------------------------
    #  setCurrentNetwork(network="STRING network - breast cancer")
    #  layoutNetwork('force-directed') #uses same settings as previously set
    # --- Loadtabledata [] ---
    # Key functions: loadTableData
    ---------------------------------------------------------------------
    #  ?loadTableData
    #  loadTableData(brc.expr,table.key.column = "display name")  #default data.frame key is row.names
    #  loadTableData(brc.mut,'Hugo_Symbol',table.key.column = "display name")  #specify column name if not default
    # --- Createvisualstyle [] ---
    # Key functions: createVisualStyle, setVisualStyle, setNodeShapeDefault, setNodeSizeDefault, setNodeColorDefault, setEdgeLineWidthDefault, setNodeLabelMapping
    ---------------------------------------------------------------------
    #  style.name = "dataStyle"
    #  createVisualStyle(style.name)
    #  setVisualStyle(style.name)
    #

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rcy3_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rcy3_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rcy3_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RCY3:", paste0("    rcy3: ", packageVersion("RCy3"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rcy3_results.csv
    touch ${prefix}_rcy3_output.rds
    echo "BIOC_RCY3:" > versions.yml
    echo "    rcy3: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RCY3_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RCY3(ch_input)

    emit:
    results  = BIOC_RCY3.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RCY3.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RCY3.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RCY3.out.versions  // channel: path(versions.yml)
}
