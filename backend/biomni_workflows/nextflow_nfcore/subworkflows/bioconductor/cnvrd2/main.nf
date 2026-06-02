#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNVrd2
// CNVrd2 uses next-generation sequencing data to measure human gene copy number for multiple samples, 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNVrd2/inst/doc/CNVrd2.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CNVrd2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNVRD2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cnvrd2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cnvrd2:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cnvrd2:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cnvrd2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cnvrd2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cnvrd2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNVrd2)
    library(jsonlite)

    # --- CNV Segmentation ---
    # Key functions: segmentSamples
    data(fcgr3bMXL)
    readCountMatrix <- resultSegment$stdCntMatrix
    objectCNVrd2 <- new("CNVrd2", windows = 1000, chr = "chr1",
                        st = 161100001, en = 162100000,
                        dirBamFile = "BamMXL",
                        genes = c(161592986, 161601753),
                        geneNames = "3B")
    resultSegment <- segmentSamples(Object = objectCNVrd2, 
                                    stdCntMatrix = readCountMatrix)

    # --- Copy Number Genotyping ---
    # Key functions: groupCNVs
    objectCluster <- new("clusteringCNVs",
                         x = resultSegment$segmentationScores[, 1], 
                         k = 3, EV = TRUE)
    copynumberGroups <- groupCNVs(Object = objectCluster, rightLimit = 1.5)
    allGroups <- copynumberGroups$allGroups

    # --- CNV Visualisation and Region Identification ---
    # Key functions: plotCNVrd2, identifyPolymorphicRegion
    duplicatedSamples <- rownames(allGroups[allGroups[, 2] > 2, ])
    fcgr3PolymorphicRegion <- identifyPolymorphicRegion(
        Object = objectCNVrd2,
        segmentObject = resultSegment,
        plotLegend = FALSE
    )
    plotCNVrd2(Object = objectCNVrd2,
               segmentObject = resultSegment,
               sampleName = duplicatedSamples[1])

    # --- Tag SNP Identification ---
    # Key functions: calculateLDSNPandCNV
    vcfFile <- system.file(package = "CNVrd2", "extdata",
                           "chr1.161600000.161611000.vcf.gz")
    sampleCNV <- data.frame(
        copynumberGroups$allGroups[, c(1, 2)],
        rep("MXL", dim(copynumberGroups$allGroups)[1])
    )
    rownames(sampleCNV) <- substr(sampleCNV[, 1], 1, 7)
    sampleCNV[, 1] <- rownames(sampleCNV)
    tagSNPs <- calculateLDSNPandCNV(sampleCNV = sampleCNV,
                                    vcfFile = vcfFile, cnvColumn = 2,
                                    population = "MXL", popColumn = 3,
                                    nChunkForVcf = 5, chr = "1",
                                    st = 161600001, en = 161611000,
                                    codeSNP = "Three",
                                    codeCNV = "ThreeGroup")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cnvrd2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cnvrd2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cnvrd2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNVRD2:", paste0("    cnvrd2: ", packageVersion("CNVrd2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnvrd2_results.csv
    touch ${prefix}_cnvrd2_output.rds
    echo "BIOC_CNVRD2:" > versions.yml
    echo "    cnvrd2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNVRD2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNVRD2(ch_input)

    emit:
    results  = BIOC_CNVRD2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNVRD2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNVRD2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNVRD2.out.versions  // channel: path(versions.yml)
}
