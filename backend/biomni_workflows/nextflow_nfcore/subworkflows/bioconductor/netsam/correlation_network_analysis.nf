#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NetSAM — correlation_network_analysis
// Construct a correlation or consensus network from an expression matrix, identify hierarchical correlation modules, and calculate associations with sample featur
// Input: exampleExpressionData.cct, sampleAnnotation.tsi
// Container: quay.io/biocontainers/bioconductor-netsam:1.50.0--r45hdfd78af_0
// Requires: NetSAM
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Test and standardize input file formats using testFileFormat. 2. Construct a correlation network using MatNet or a robust consensu

nextflow.enable.dsl = 2

process BIOC_NETSAM_CORRELATION_NETWORK_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("NetSAM")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load the NetSAM library
    library("NetSAM")
    
    # Define input file paths in the working directory
    inputMatDir <- "exampleExpressionData.cct"
    sampleAnnDir <- "sampleAnnotation.tsi"
    
    # Verify that the required user input files exist
    if (!file.exists(inputMatDir)) {
      stop(paste("Required input file missing:", inputMatDir))
    }
    if (!file.exists(sampleAnnDir)) {
      stop(paste("Required input file missing:", sampleAnnDir))
    }
    
    # 1. Test and standardize input file formats
    message("Testing and standardizing input file formats...")
    formatedData <- testFileFormat(inputMat=inputMatDir, sampleAnn=sampleAnnDir, collapse_mode="maxSD")
    
    # 2. Construct a correlation network using MatNet
    message("Constructing correlation network using MatNet...")
    matNetwork <- MatNet(inputMat=inputMatDir, collapse_mode="maxSD", naPer=0.7, meanPer=0.8, varPer=0.8,
                         corrType="spearman", matNetMethod="rank", valueThr=0.6, rankBest=0.003, networkType="signed",
                         netFDRMethod="BH", netFDRThr=0.05, idNumThr=(-1), nThreads=3)
    
    # Save MatNet output
    write.table(matNetwork, file="matNetwork_output.txt", sep="\t", row.names=FALSE, col.names=TRUE, quote=FALSE)
    
    # 3. Construct a consensus network using consensusNet
    message("Constructing consensus network using consensusNet...")
    data <- read.table(inputMatDir, header=TRUE, row.names=1, stringsAsFactors=FALSE)
    net <- consensusNet(data=data, organism="hsapiens", bootstrapNum=10, naPer=0.5, meanPer=0.8, varPer=0.8,
                        method="rank_unsig", value=3/1000, pth=1e-6, nMatNet=2, nThreads=4)
    
    # Save consensusNet output
    write.table(net, file="consensusNet_output.txt", sep="\t", row.names=FALSE, col.names=TRUE, quote=FALSE)
    
    # 4. Identify hierarchical correlation modules using MatSAM
    message("Identifying hierarchical correlation modules using MatSAM...")
    outputFileName <- paste(getwd(), "/MatSAM", sep="")
    matModule <- MatSAM(inputMat=inputMatDir, sampleAnn=sampleAnnDir,
                        outputFileName = outputFileName, outputFormat="msm",
                        organism="hsapiens", map_to_symbol=FALSE, idType="auto", collapse_mode="maxSD", naPer=0.7, meanPer=0.8, varPer=0.8,
                        corrType="spearman", matNetMethod="rank",
                        valueThr=0.6, rankBest=0.003, networkType="signed", netFDRMethod="BH",
                        netFDRThr=0.05, minModule=0.003, stepIte=FALSE,
                        maxStep=4, moduleSigMethod="cutoff", modularityThr=0.2, ZRanNum=10, PerRanNum=100, ranSig=0.05, idNumThr=(-1), nThreads=3)
    
    # Save MatSAM output object
    saveRDS(matModule, file="matModule_output.rds")
    
    # 5. Calculate associations between sample features and modules using featureAssociation
    message("Calculating associations between sample features and modules...")
    outputHtmlFile <- paste(getwd(), "/featureAsso_HTML", sep="")
    featureAsso <- featureAssociation(inputMat=inputMatDir, sampleAnn=sampleAnnDir, NetSAMOutput=matModule, 
                                      outputHtmlFile=outputHtmlFile, CONMethod="spearman", CATMethod="kruskal", 
                                      BINMethod="ranktest", fdrmethod="BH", pth=0.05, collapse_mode="maxSD")
    
    # Save feature association results
    write.csv(featureAsso, file="featureAssociation_results.csv", row.names=TRUE)
    
    # 6. Identify associated GO terms for the modules using GOAssociation
    message("Identifying associated GO terms for the modules...")
    outputHtmlFile <- paste(getwd(), "/GOAsso_HTML", sep="")
    GOAsso <- GOAssociation(NetSAMOutput=matModule, outputHtmlFile=outputHtmlFile, 
                            organism="hsapiens", fdrmethod="BH", fdrth=0.05, topNum=5)
    
    # Save GO association results
    write.csv(GOAsso, file="GOAssociation_results.csv", row.names=TRUE)
    
    message("NetSAM pipeline completed successfully!")

    writeLines(c(
        '"BIOC_NETSAM_CORRELATION_NETWORK_ANALYSIS":',
        paste0('    NetSAM: ', as.character(packageVersion('NetSAM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_correlation_network_analysis.csv versions.yml
    """
}

workflow BIOC_NETSAM_CORRELATION_NETWORK_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exampleExpressionData.cct, sampleAnnotation.tsi ] ]

    main:
    BIOC_NETSAM_CORRELATION_NETWORK_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_NETSAM_CORRELATION_NETWORK_ANALYSIS.out.tables
    plots    = BIOC_NETSAM_CORRELATION_NETWORK_ANALYSIS.out.plots
    objects  = BIOC_NETSAM_CORRELATION_NETWORK_ANALYSIS.out.objects
    versions = BIOC_NETSAM_CORRELATION_NETWORK_ANALYSIS.out.versions
}
