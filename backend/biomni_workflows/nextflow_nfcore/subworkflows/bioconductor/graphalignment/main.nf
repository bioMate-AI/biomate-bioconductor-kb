#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GraphAlignment
// Graph alignment is an extension package for the R programming environment which provides functions f
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GraphAlignment/inst/doc/GraphAlignment.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GraphAlignment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GRAPHALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-graphalignment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-graphalignment:1.70.0--r44_0' :
        'quay.io/biocontainers/bioconductor-graphalignment:1.70.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_graphalignment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_graphalignment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_graphalignment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AlignNetworks)
    library(AlignedPairs)
    library(AnalyzeAlignment)
    library(ComputeLinkParameters)
    library(ComputeNodeParameters)
    library(ComputeScores)
    library(GenerateExample)
    library(InitialAlignment)
    library(jsonlite)

    # --- Vignette [] ---
    # Key functions: edit
    ## vignette(all=FALSE)
    ## edit(vignette("GraphAlignment"))
    # --- Generateexample [] ---
    # Key functions: GenerateExample
    library(GraphAlignment)
    ex<-GenerateExample(dimA=22, dimB=22, filling=.5,
        covariance=.6, symmetric=TRUE, numOrths=10, correlated=seq(1,18))
    # --- Initialalignment [] ---
    # Key functions: InitialAlignment
    pinitial<-InitialAlignment(psize=34, r=ex$r, mode="reciprocal")
    # --- Computelinkparameters [] ---
    # Key functions: ComputeLinkParameters
    linkParams<-ComputeLinkParameters(ex$a, ex$b, pinitial, lookupLink)
    # --- Alignnetworks [] ---
    # Key functions: AlignNetworks
    al<-AlignNetworks(A=ex$a, B=ex$b, R=ex$r, P=pinitial,
        linkScore=linkParams$ls,
        selfLinkScore=linkParams$ls,
        nodeScore1=nodeParams$s1, nodeScore0=nodeParams$s0,
        lookupLink=lookupLink, lookupNode=lookupNode,
    # --- Computescores [] ---
    # Key functions: ComputeScores
    ComputeScores(A=ex$a, B=ex$b, R=ex$r, P=al,
        linkScore=linkParams$ls,
        selfLinkScore=linkParams$ls,
        nodeScore1=nodeParams$s1, nodeScore0=nodeParams$s0,
        lookupLink=lookupLink, lookupNode=lookupNode,
    # --- Analyzealignment [] ---
    # Key functions: AnalyzeAlignment
    AnalyzeAlignment(A=ex$a, B=ex$b, R=ex$r, P=al, lookupNode,
        epsilon=.5)
    # --- Generateexample [] ---
    # Key functions: GenerateExample, InitialAlignment, ComputeLinkParameters
    ex<-GenerateExample(30, 30, filling=1, covariance=.95,
        numOrths=20, symmetric=FALSE)
    a=ex$a;b=ex$b
    a[a>.5]=1;a[a<=.5]=0
    b[b>.5]=1;b[b<=.5]=0
    # --- Alignedpairs [] ---
    # Key functions: AlignedPairs
    AlignedPairs(A, B, p0);
    # --- Alignnetworks [] ---
    # Key functions: AlignNetworks
    al <- AlignNetworks(A, B, R, p0, linkParams$ls, linkParams$lsSelf, nodeParams$s1, nodeParams$s0, lookupLink, lookupNode, bStart = 0.001, bEnd = 1000, maxNumSteps = 100, clamp = TRUE);
    # --- Computelinkparameters [] ---
    # Key functions: ComputeLinkParameters, ComputeNodeParameters
    linkParams <- ComputeLinkParameters(A, B, al, lookupLink);
    nodeParams <- ComputeNodeParameters(dim(A)[1], dim(B)[1], R, al, lookupNode);
    # --- Alignnetworks [] ---
    # Key functions: AlignNetworks
    al == AlignNetworks(A, B, R, al, linkParams$ls, linkParams$lsSelf, nodeParams$s1, nodeParams$s0, lookupLink, lookupNode, bStart = 0.001, bEnd = 1000, maxNumSteps = 100, clamp = TRUE);
    # --- Alignedpairs [] ---
    # Key functions: AlignedPairs
    al;
    AlignedPairs(A, B, al);
    # --- Computescores [] ---
    # Key functions: ComputeScores
    ComputeScores(A, B, R, al, linkParams$ls, linkParams$lsSelf, nodeParams$s1, nodeParams$s0, lookupLink, lookupNode, symmetric = TRUE, clamp = TRUE);

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_graphalignment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_graphalignment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_graphalignment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GRAPHALIGNMENT:", paste0("    graphalignment: ", packageVersion("GraphAlignment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_graphalignment_results.csv
    touch ${prefix}_graphalignment_output.rds
    echo "BIOC_GRAPHALIGNMENT:" > versions.yml
    echo "    graphalignment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GRAPHALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GRAPHALIGNMENT(ch_input)

    emit:
    results  = BIOC_GRAPHALIGNMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GRAPHALIGNMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GRAPHALIGNMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GRAPHALIGNMENT.out.versions  // channel: path(versions.yml)
}
