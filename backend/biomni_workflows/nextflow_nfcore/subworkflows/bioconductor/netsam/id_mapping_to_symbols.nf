#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NetSAM — id_mapping_to_symbols
// Transform non-symbol gene identifiers from various input formats (gene lists, networks, matrices, sbt, or sct files) into standard gene symbols.
// Input: exampleGeneList.txt, exampleNetwork_nonsymbol.net, exampleExpressionData_nonsymbol.cct, exampleSBT.sbt, exampleSCT.sct
// Container: quay.io/biocontainers/bioconductor-netsam:1.50.0--r45hdfd78af_0
// Requires: NetSAM
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run mapToSymbol specifying the appropriate inputType, idType, and organism to perform the ID conversion

nextflow.enable.dsl = 2

process BIOC_NETSAM_ID_MAPPING_TO_SYMBOLS {
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
    
    library("NetSAM")
    
    # 1. Transform ids from a gene list to gene symbols
    print("transform ids from a gene list to gene symbols...")
    geneListDir <- "exampleGeneList.txt"
    geneList <- read.table(geneListDir, header=FALSE, sep="\t", stringsAsFactors=FALSE)
    geneList <- as.vector(as.matrix(geneList))
    geneList_symbol <- mapToSymbol(inputData=geneList, organism="hsapiens", inputType="genelist", idType="affy_hg_u133_plus_2")
    
    # 2. Transform ids in the input network to gene symbols
    print("transform ids in the input network to gene symbols...")
    inputNetwork <- "exampleNetwork_nonsymbol.net"
    network_symbol <- mapToSymbol(inputData=inputNetwork, organism="hsapiens", inputType="network", idType="entrezgene", edgeType="unweighted")
    
    # 3. Transform ids in the input matrix to gene symbols
    print("transform ids in the input matrix to gene symbols...")
    inputMatDir <- "exampleExpressionData_nonsymbol.cct"
    matrix_symbol <- mapToSymbol(inputData=inputMatDir, organism="hsapiens", inputType="matrix", idType="affy_hg_u133_plus_2", collapse_mode="maxSD")
    
    # 4. Transform ids in the sbt file to gene symbols
    print("transform ids in the sbt file to gene symbols...")
    inputSBTDir <- "exampleSBT.sbt"
    sbt_symbol <- mapToSymbol(inputData=inputSBTDir, organism="hsapiens", inputType="sbt", idType="affy_hg_u133_plus_2")
    
    # 5. Transform ids in the sct file to gene symbols
    print("transform ids in the sct file to gene symbols...")
    inputSCTDir <- "exampleSCT.sct"
    sct_symbol <- mapToSymbol(inputData=inputSCTDir, organism="hsapiens", inputType="sct", idType="affy_hg_u133_plus_2", collapse_mode="min")
    
    # Save the results to RDS files
    print("Saving results...")
    saveRDS(geneList_symbol, file="geneList_symbol.rds")
    saveRDS(network_symbol, file="network_symbol.rds")
    saveRDS(matrix_symbol, file="matrix_symbol.rds")
    saveRDS(sbt_symbol, file="sbt_symbol.rds")
    saveRDS(sct_symbol, file="sct_symbol.rds")
    
    print("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_NETSAM_ID_MAPPING_TO_SYMBOLS":',
        paste0('    NetSAM: ', as.character(packageVersion('NetSAM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_id_mapping_to_symbols.csv versions.yml
    """
}

workflow BIOC_NETSAM_ID_MAPPING_TO_SYMBOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exampleGeneList.txt, exampleNetwork_nonsymbol.net, exampleExpressionData_nonsymbol.cct, exampleSBT.sbt, exampleSCT.sct ] ]

    main:
    BIOC_NETSAM_ID_MAPPING_TO_SYMBOLS(ch_input)

    emit:
    tables   = BIOC_NETSAM_ID_MAPPING_TO_SYMBOLS.out.tables
    plots    = BIOC_NETSAM_ID_MAPPING_TO_SYMBOLS.out.plots
    objects  = BIOC_NETSAM_ID_MAPPING_TO_SYMBOLS.out.objects
    versions = BIOC_NETSAM_ID_MAPPING_TO_SYMBOLS.out.versions
}
