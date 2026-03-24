#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneRegionScan
// A package with focus on analysis of discrete regions of the genome. This package is useful for inves
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneRegionScan/inst/doc/GeneRegionScan.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GeneRegionScan")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEREGIONSCAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-generegionscan"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-generegionscan:1.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-generegionscan:1.62.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_generegionscan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_generegionscan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_generegionscan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneRegionScan)
    library(jsonlite)

    # --- Gettingprobesetsnotrunpart [] ---
    # Key functions: getProbesetsFromRegionOfInterest
    ## transcriptClustersFile<-"~/HuEx-1-0-st-v2.na26.hg18.transcript.csv"
    ## mpsToPsFile<-"~/HuEx-1-0-st-v2.r2.dt1.hg18.full.mps"
    ## listOfProbesets<-getProbesetsFromRegionOfInterest("HuEx-1-0-st-v2", "chr2", 215889955,216106710, transcriptClustersFile=transcriptClustersFile, mpsToPsFile=mpsToPsFile)
    # --- Gettingprobeevelset [] ---
    # Key functions: getLocalProbeIntensities
    ## aptCelExtractPath<-"~/apt-bin/apt-cel-extract"
    ## clfPath<-"~/HuEx-1-0-st-v2.r2.clf"
    ## pgfPath<-"~/HuEx-1-0-st-v2.r2.pgf"
    ##
    ## myProbeLevelSet<-getLocalProbeIntensities(listOfProbesets,"~/test-cels", aptCelExtractPath=aptCelExtractPath, pgfPath=pgfPath, clfPath=clfPath)
    # --- Getsequence [] ---
    # Key functions: getSequence
    ## getSequence(myProbeLevelSet,1:5)
    # --- Loaddata [] ---
    # Key functions: pData
    data(exampleProbeLevelSet)
    pData(exampleProbeLevelSet)[1:3,]
    # --- Plot1 [] ---
    # Key functions: plotOnGene
    plotOnGene(exampleProbeLevelSet, mrna)
    # --- Plot2 [] ---
    # Key functions: plotOnGene, exonStructure
    plotOnGene(exampleProbeLevelSet, mrna, summaryType="dots", interval=c(500,1000))
    exonStructure(mrna, genomic)
    # --- Plot3 [] ---
    # Key functions: plotOnGene, exonStructure
    plotOnGene(exampleProbeLevelSet, mrna, label="gender", testType="wilcoxon", verbose=FALSE)
    exonStructure(mrna, genomic)
    # --- Plot4 [] ---
    # Key functions: plotOnGene, exonStructure
    plotOnGene(exampleProbeLevelSet, mrna, label="genotype1", testType="linear model", verbose=FALSE)
    exonStructure(mrna, genomic)
    # --- Plot5 [] ---
    # Key functions: plotCoexpression
    mrna_subset<-mrna[[1]]
    mrna_subset<-mrna_subset[500:1000]
    plotCoexpression(exampleProbeLevelSet, gene=mrna_subset, correlationCutoff=0.5, probeLevelInfo=c("probeid","sequence"), verbose=FALSE)
    # --- Plot6 [] ---
    # Key functions: geneRegionScan
    ## geneRegionScan(exampleProbeLevelSet, gene=mrna, genomicData=genomic, label="genotype3", testType="linear model", correlationCutoff=0.5, probeLevelInfo=c("probeid","sequence"), verbose=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_generegionscan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_generegionscan_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_generegionscan_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENEREGIONSCAN:", paste0("    generegionscan: ", packageVersion("GeneRegionScan"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_generegionscan_results.csv
    touch ${prefix}_generegionscan_output.rds
    echo "BIOC_GENEREGIONSCAN:" > versions.yml
    echo "    generegionscan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENEREGIONSCAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENEREGIONSCAN(ch_input)

    emit:
    results  = BIOC_GENEREGIONSCAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENEREGIONSCAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENEREGIONSCAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENEREGIONSCAN.out.versions  // channel: path(versions.yml)
}
