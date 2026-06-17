#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNEr — pairwise_whole_genome_alignment
// Generate pairwise whole-genome alignments (net.axt) from raw 2bit or fasta files using LASTZ or LAST.
// Input: single_sequences.2bit, single_sequences.2bit, danRer10.fa, hg38.fa
// Container: quay.io/biocontainers/bioconductor-cner:1.46.0--r45h01b2380_0
// R packages: CNEr, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: CNEr, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run lastz to generate lav files (or lastal to generate maf files)
//  * 2. [Core Analysis] Convert alignments to psl format (lavToPsl or maf-convert)
//  * 3. [Core Analysis] Chain close alignments (axtChain)
//  * 4. [Core Analysis] Sort and merge chains (chainMergeSort)
//  * 5. [Core Analysis] Filter chains and add synteny information (chainPreNet and chainNetSyntenic)
//  * 6. [Core Analysis] Convert net and chain files to net.axt format (netToAxt)

nextflow.enable.dsl = 2

process BIOC_CNER_PAIRWISE_WHOLE_GENOME_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("CNEr", "rtracklayer")
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
            library(rtracklayer)
            
            # Define directories
            assemblyDir <- "."
            axtDir <- "./axt"
            if (!dir.exists(axtDir)) {
              dir.create(axtDir, recursive = TRUE)
            }
            
            # Define user input files from the working directory
            assemblyTarget <- "danRer10_single_sequences.2bit"
            assemblyQuery <- "hg38_single_sequences.2bit"
            targetFasta <- "danRer10.fa"
            queryFasta <- "hg38.fa"
            
            # Verify that the required input files exist before proceeding
            if (!file.exists(assemblyTarget)) {
              stop("Required target 2bit file '", assemblyTarget, "' is missing.")
            }
            if (!file.exists(assemblyQuery)) {
              stop("Required query 2bit file '", assemblyQuery, "' is missing.")
            }
            if (!file.exists(targetFasta)) {
              stop("Required target FASTA file '", targetFasta, "' is missing from the working directory.")
            }
            if (!file.exists(queryFasta)) {
              stop("Required query FASTA file '", queryFasta, "' is missing from the working directory.")
            }
            
            # Extract chromosome names from the 2bit files
            chrsTarget <- seqlevels(seqinfo(TwoBitFile(assemblyTarget)))
            chrsQuery <- seqlevels(seqinfo(TwoBitFile(assemblyQuery)))
            
            # -----------------------------------------------------------------------------
            # Stage 1 & 2: Run LASTZ to generate lav files and convert to psl format
            # -----------------------------------------------------------------------------
            message("Stage 1 & 2: Running LASTZ alignment and converting to PSL...")
            lavs <- tryCatch({
              lastz(assemblyTarget, assemblyQuery, outputDir=axtDir, 
                    chrsTarget=chrsTarget, 
                    chrsQuery=chrsQuery, 
                    distance="far", mc.cores=4)
            }, error = function(e) {
              warning("LASTZ alignment failed or binary not available: ", e\$message)
              character(0)
            })
            
            psls <- tryCatch({
              if (length(lavs) > 0) {
                lavToPsl(lavs, removeLav=FALSE, binary="lavToPsl")
              } else {
                character(0)
              }
            }, error = function(e) {
              warning("lavToPsl conversion failed: ", e\$message)
              character(0)
            })
            
            # -----------------------------------------------------------------------------
            # Stage 1 & 2 (Alternative): Run LAST to generate maf files and convert to psl
            # -----------------------------------------------------------------------------
            if (length(psls) == 0) {
              message("Stage 1 & 2 (Alternative): Running LAST alignment and converting to PSL...")
              targetDb <- file.path(assemblyDir, sub("\\\\.fa\$", "", basename(targetFasta), ignore.case=TRUE))
              mafFile <- file.path(axtDir, paste0(sub("\\\\.fa\$", "", basename(targetFasta), ignore.case=TRUE), ".", sub("\\\\.fa\$", "", basename(queryFasta), ignore.case=TRUE), ".maf"))
              psls_out <- file.path(axtDir, paste0(sub("\\\\.fa\$", "", basename(targetFasta), ignore.case=TRUE), ".", sub("\\\\.fa\$", "", basename(queryFasta), ignore.case=TRUE), ".psl"))
              
              status_lastdb <- system2(command="lastdb", args=c("-c", targetDb, file.path(assemblyDir, targetFasta)))
              if (status_lastdb != 0) {
                stop("lastdb failed with exit status ", status_lastdb)
              }
              
              lastal(db=targetDb, queryFn=file.path(assemblyDir, queryFasta), 
                     outputFn=mafFile, distance="far", binary="lastal", mc.cores=4L)
              
              status_maf <- system2(command="maf-convert", args=c("psl", mafFile), stdout=psls_out)
              if (status_maf != 0) {
                stop("maf-convert failed with exit status ", status_maf)
              }
              
              psls <- psls_out
            }
            
            # -----------------------------------------------------------------------------
            # Stage 3: Chain close alignments (axtChain)
            # -----------------------------------------------------------------------------
            message("Stage 3: Chaining close alignments...")
            chains <- axtChain(psls, assemblyTarget=assemblyTarget, assemblyQuery=assemblyQuery, 
                               distance="far", removePsl=FALSE, binary="axtChain")
            
            # -----------------------------------------------------------------------------
            # Stage 4: Sort and merge chains (chainMergeSort)
            # -----------------------------------------------------------------------------
            message("Stage 4: Sorting and merging chains...")
            allChain <- chainMergeSort(chains, assemblyTarget, assemblyQuery, 
                                       allChain=file.path(axtDir, paste0(sub("\\\\.2bit\$", "", basename(assemblyTarget), ignore.case=TRUE), ".", sub("\\\\.2bit\$", "", basename(assemblyQuery), ignore.case=TRUE), ".all.chain")), 
                                       removeChains=FALSE, binary="chainMergeSort")
            
            # -----------------------------------------------------------------------------
            # Stage 5: Filter chains and add synteny information (chainPreNet & chainNetSyntenic)
            # -----------------------------------------------------------------------------
            message("Stage 5: Filtering chains and adding synteny information...")
            allPreChain <- chainPreNet(allChain, assemblyTarget, assemblyQuery, 
                                       allPreChain=file.path(axtDir, paste0(sub("\\\\.2bit\$", "", basename(assemblyTarget), ignore.case = TRUE), ".", sub("\\\\.2bit\$", "", basename(assemblyQuery), ignore.case = TRUE), ".all.pre.chain")), 
                                       removeAllChain=FALSE, binary="chainPreNet")
            
            netSyntenicFile <- chainNetSyntenic(allPreChain, assemblyTarget, assemblyQuery, 
                                                netSyntenicFile=file.path(axtDir, paste0(sub("\\\\.2bit\$", "", basename(assemblyTarget), ignore.case = TRUE), ".", sub("\\\\.2bit\$", "", basename(assemblyQuery), ignore.case = TRUE), ".noClass.net")), 
                                                binaryChainNet="chainNet", binaryNetSyntenic="netSyntenic")
            
            # -----------------------------------------------------------------------------
            # Stage 6: Convert net and chain files to net.axt format (netToAxt)
            # -----------------------------------------------------------------------------
            message("Stage 6: Converting net and chain files to net.axt format...")
            finalAxtFile <- file.path(axtDir, paste0(sub("\\\\.2bit\$", "", basename(assemblyTarget), ignore.case = TRUE), ".", sub("\\\\.2bit\$", "", basename(assemblyQuery), ignore.case = TRUE), ".net.axt"))
            
            netToAxt(netSyntenicFile, allPreChain, assemblyTarget, assemblyQuery, 
                     axtFile=finalAxtFile, removeFiles=FALSE, 
                     binaryNetToAxt="netToAxt", binaryAxtSort="axtSort")
            
            # Save pipeline metadata and file paths as an RDS object for downstream analysis
            pipelineSummary <- list(
              assemblyTarget = assemblyTarget,
              assemblyQuery = assemblyQuery,
              allChainFile = allChain,
              allPreChainFile = allPreChain,
              netSyntenicFile = netSyntenicFile,
              finalAxtFile = finalAxtFile
            )
            saveRDS(pipelineSummary, file = file.path(axtDir, "pipeline_summary.rds"))
            
            message("Pipeline execution completed. Summary saved to: ", file.path(axtDir, "pipeline_summary.rds"))

    writeLines(c(
        '"BIOC_CNER_PAIRWISE_WHOLE_GENOME_ALIGNMENT":',
        paste0('    CNEr: ', as.character(packageVersion('CNEr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_whole_genome_alignment.csv versions.yml
    """
}

workflow BIOC_CNER_PAIRWISE_WHOLE_GENOME_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ single_sequences.2bit, single_sequences.2bit, danRer10.fa, hg38.fa ] ]

    main:
    BIOC_CNER_PAIRWISE_WHOLE_GENOME_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_CNER_PAIRWISE_WHOLE_GENOME_ALIGNMENT.out.tables
    plots    = BIOC_CNER_PAIRWISE_WHOLE_GENOME_ALIGNMENT.out.plots
    objects  = BIOC_CNER_PAIRWISE_WHOLE_GENOME_ALIGNMENT.out.objects
    versions = BIOC_CNER_PAIRWISE_WHOLE_GENOME_ALIGNMENT.out.versions
}
