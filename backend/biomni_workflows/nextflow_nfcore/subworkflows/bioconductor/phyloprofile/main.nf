#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PhyloProfile
// PhyloProfile is a tool for exploring complex phylogenetic profiles. Phylogenetic profiles, presence/
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PhyloProfile/inst/doc/PhyloProfile-vignette.R
// Upstream  : dplyr
// Downstream: none
//
// Install: BiocManager::install("PhyloProfile")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHYLOPROFILE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phyloprofile"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phyloprofile:1.20.4--r44_0' :
        'quay.io/biocontainers/bioconductor-phyloprofile:1.20.4--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phyloprofile_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phyloprofile_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phyloprofile_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PhyloProfile)
    library(jsonlite)

    # --- Phylogenetic Profile Construction [fromInputToProfile] ---
    # Key functions: fromInputToProfile
    rawInput <- system.file(
        "extdata", "test.main.long", package = "PhyloProfile", mustWork = TRUE
    )
    profileData <- fromInputToProfile(
        rawInput,
        rankName = "class",
        refTaxon = "Mammalia",
        taxaTree = NULL,
        sortedTaxonList = NULL,
        var1AggregateBy = "max",
        var2AggregateBy = "mean",
        percentCutoff = c(0.0, 1.0),
        coorthologCutoffMax = 10,
        var1Cutoff = c(0.75, 1.0),
        var2Cutoff = c(0.5, 1.0),
        var1Relation = "protein",
        var2Relation = "species",
        groupByCat = FALSE,
        catDt = NULL
    )

    # --- Profile Clustering [getDataClustering, getDistanceMatrix, clusterDataDend, getDendrogram] ---
    # Key functions: getDataClustering, getDistanceMatrix, clusterDataDend, getDendrogram
    data("finalProcessedProfile", package = "PhyloProfile")
    profiles <- getDataClustering(
        finalProcessedProfile, "binary", "max", "mean"
    )
    distanceMatrix <- getDistanceMatrix(profiles, "mutualInformation")
    dd <- clusterDataDend(distanceMatrix, "complete")
    dendrogramPlot <- getDendrogram(dd)

    # --- Gene Age Estimation [sortInputTaxa, estimateGeneAge] ---
    # Key functions: sortInputTaxa, estimateGeneAge
    data("fullProcessedProfile", package = "PhyloProfile")
    taxonIDs <- levels(as.factor(fullProcessedProfile$ncbiID))
    sortedInputTaxa <- sortInputTaxa(
        taxonIDs, "class", "Mammalia", NULL, NULL, NULL
    )
    taxaCount <- as.data.frame(table(sortedInputTaxa$supertaxon))
    colnames(taxaCount) <- c("supertaxon", "n")
    geneAge <- estimateGeneAge(
        fullProcessedProfile, taxaCount, "class", "Mammalia",
        c(0, 1), c(0, 1), c(0, 1)
    )

    # --- Core Gene Identification [sortInputTaxa, getCoreGene] ---
    # Key functions: sortInputTaxa, getCoreGene
    data("fullProcessedProfile", package = "PhyloProfile")
    taxonIDs <- levels(as.factor(fullProcessedProfile$ncbiID))
    sortedInputTaxa <- sortInputTaxa(
        taxonIDs, "class", "Mammalia", NULL, NULL, NULL
    )
    taxaCount <- as.data.frame(table(sortedInputTaxa$supertaxon))
    colnames(taxaCount) <- c("supertaxon", "n")
    coreGenes <- getCoreGene(
        "class",
        c("Mammalia", "Saccharomycetes", "Insecta"),
        fullProcessedProfile,
        taxaCount,
        c(0.75, 1.0), c(0.75, 1.0),
        c(0.0, 1.0), 1
    )

    # --- Taxon Group Comparison [compareTaxonGroups] ---
    # Key functions: compareTaxonGroups
    data("mainLongRaw", package = "PhyloProfile")
    inGroup <- c("ncbi9606", "ncbi10116")
    variable <- colnames(mainLongRaw)[4]
    comparison <- compareTaxonGroups(
        mainLongRaw, inGroup, TRUE, variable, 0.05
    )

    # --- Variable Distribution Analysis [createVariableDistributionData, createVarDistPlot] ---
    # Key functions: createVariableDistributionData, createVarDistPlot
    data("mainLongRaw", package = "PhyloProfile")
    distData <- createVariableDistributionData(
        mainLongRaw, c(0, 1), c(0.5, 1)
    )
    distPlot <- createVarDistPlot(
        distData, "Variable 1", "var1", c(0, 1), 12
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phyloprofile_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phyloprofile_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phyloprofile_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHYLOPROFILE:", paste0("    phyloprofile: ", packageVersion("PhyloProfile"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phyloprofile_results.csv
    touch ${prefix}_phyloprofile_output.rds
    echo "BIOC_PHYLOPROFILE:" > versions.yml
    echo "    phyloprofile: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHYLOPROFILE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHYLOPROFILE(ch_input)

    emit:
    results  = BIOC_PHYLOPROFILE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHYLOPROFILE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHYLOPROFILE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHYLOPROFILE.out.versions  // channel: path(versions.yml)
}
