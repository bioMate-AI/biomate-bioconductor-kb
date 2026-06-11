#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cner — pairwise_genome_alignment
// Generate pairwise whole-genome net alignments (.net.axt files) from 2bit or fasta files using LASTZ and Kent utilities.
// Input: assemblyTarget.2bit, assemblyQuery.2bit
// Container: quay.io/biocontainers/bioconductor-cner:1.46.0--r45h01b2380_0
// R packages: biomaRt, CNEr, GenomeInfoDb, Gviz, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNER_PAIRWISE_GENOME_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cner:1.46.0--r45h01b2380_0"

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
    .bm_deps <- c("biomaRt", "CNEr", "GenomeInfoDb", "Gviz", "rtracklayer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(CNEr)
    
    # Verify that the required user input files exist in the working directory
    target_file <- "assemblyTarget.2bit"
    query_file <- "assemblyQuery.2bit"
    
    if (!file.exists(target_file)) {
      stop(paste("Error: Target assembly file missing:", target_file))
    }
    if (!file.exists(query_file)) {
      stop(paste("Error: Query assembly file missing:", query_file))
    }
    
    # Define input paths and output directory
    assemblyTarget <- target_file
    assemblyQuery <- query_file
    axtDir <- "axt_output"
    dir.create(axtDir, showWarnings = FALSE, recursive = TRUE)
    
    # 1. Run LASTZ alignment to generate LAV files
    lavs <- lastz(assemblyTarget, assemblyQuery, outputDir=axtDir, chrsTarget=c("chr1", "chr2", "chr3"), chrsQuery=c("chr1", "chr2", "chr3"), distance="far", mc.cores=4)
    saveRDS(lavs, file=file.path(axtDir, "lavs.rds"))
    
    # 2. Convert LAV files to PSL files
    psls <- lavToPsl(lavs, removeLav=FALSE, binary="lavToPsl")
    saveRDS(psls, file=file.path(axtDir, "psls.rds"))
    
    # 3. Join close alignments into chains
    chains <- axtChain(psls, assemblyTarget=assemblyTarget, assemblyQuery=assemblyQuery, distance="far", removePsl=FALSE, binary="axtChain")
    saveRDS(chains, file=file.path(axtDir, "chains.rds"))
    
    # 4. Sort and combine chains
    allChain <- chainMergeSort(chains, assemblyTarget, assemblyQuery, allChain=file.path(axtDir, paste0(sub("\\\\.2bit\$", "", basename(assemblyTarget), ignore.case=TRUE), ".", sub("\\\\.2bit\$", "", basename(assemblyQuery), ignore.case=TRUE), ".all.chain")), removeChains=FALSE, binary="chainMergeSort")
    saveRDS(allChain, file=file.path(axtDir, "allChain.rds"))
    
    # 5. Filter chains
    allPreChain <- chainPreNet(allChain, assemblyTarget, assemblyQuery, allPreChain=file.path(axtDir, paste0(sub("\\\\.2bit\$", "", basename(assemblyTarget), ignore.case = TRUE), ".", sub("\\\\.2bit\$", "", basename(assemblyQuery), ignore.case = TRUE), ".all.pre.chain")), removeAllChain=FALSE, binary="chainPreNet")
    saveRDS(allPreChain, file=file.path(axtDir, "allPreChain.rds"))
    
    # 6. Net chains and add synteny information
    netSyntenicFile <- chainNetSyntenic(allPreChain, assemblyTarget, assemblyQuery, netSyntenicFile=file.path(axtDir, paste0(sub("\\\\.2bit\$", "", basename(assemblyTarget), ignore.case = TRUE), ".", sub("\\\\.2bit\$", "", basename(assemblyQuery), ignore.case = TRUE), ".noClass.net")), binaryChainNet="chainNet", binaryNetSyntenic="netSyntenic")
    saveRDS(netSyntenicFile, file=file.path(axtDir, "netSyntenicFile.rds"))
    
    # 7. Create net.axt files
    netToAxt(netSyntenicFile, allPreChain, assemblyTarget, assemblyQuery, axtFile=file.path(axtDir, paste0(sub("\\\\.2bit\$", "", basename(assemblyTarget), ignore.case = TRUE), ".", sub("\\\\.2bit\$", "", basename(assemblyQuery), ignore.case = TRUE), ".net.axt")), removeFiles=FALSE, binaryNetToAxt="netToAxt", binaryAxtSort="axtSort")

    writeLines(c(
        '"BIOC_CNER_PAIRWISE_GENOME_ALIGNMENT":',
        paste0('        cner: ', as.character(packageVersion("cner")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_genome_alignment.csv versions.yml
    """
}

workflow BIOC_CNER_PAIRWISE_GENOME_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ assemblyTarget.2bit, assemblyQuery.2bit ] ]

    main:
    BIOC_CNER_PAIRWISE_GENOME_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_CNER_PAIRWISE_GENOME_ALIGNMENT.out.tables
    plots    = BIOC_CNER_PAIRWISE_GENOME_ALIGNMENT.out.plots
    objects  = BIOC_CNER_PAIRWISE_GENOME_ALIGNMENT.out.objects
    versions = BIOC_CNER_PAIRWISE_GENOME_ALIGNMENT.out.versions
}
