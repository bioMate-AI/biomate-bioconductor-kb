#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ramwas — custom_cpg_set_and_qc
// Construct a custom CpG set from a reference genome, inject common SNPs, and filter out problematic alignment regions using an in silico alignment experiment.
// Input: BSgenome, count_ALL_chr22.txt, chr1.fastq.gz, chr1.bam
// Container: quay.io/biocontainers/bioconductor-ramwas:1.34.0--r45h01b2380_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, filematrix, ramwas, bsg_pkgs
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, filematrix, ramwas
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Inject common SNPs into reference genome using injectSNPsMAF
//  * 2. [Core Analysis] Find CpGs using getCpGsetALL
//  * 3. [Core Analysis] Generate artificial FASTQ reads using insilicoFASTQ
//  * 4. [Core Analysis] Scan BAMs of aligned artificial reads using ramwas1scanBams
//  * 5. [Core Analysis] Calculate normalized coverage of artificial reads using ramwas3normalizedCoverage
//  * 6. [Core Analysis] Filter CpGs by in silico coverage
//  * 7. [Visualization & Output] Save the QC-filtered CpG set using saveRDS

nextflow.enable.dsl = 2

process BIOC_RAMWAS_CUSTOM_CPG_SET_AND_QC {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "filematrix", "ramwas", "bsg_pkgs")
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
    library(ramwas)
    library(filematrix)
    
    # Dynamically detect and load an installed BSgenome package
    installed_pkgs <- installed.packages()[, "Package"]
    bsg_pkgs <- installed_pkgs[grep("^BSgenome\\\\.", installed_pkgs)]
    if (length(bsg_pkgs) > 0) {
      library(bsg_pkgs[1], character.only = TRUE)
      obj_name <- sub("^BSgenome\\\\.", "", bsg_pkgs[1])
      # Handle common naming variations (e.g., UCSC names like Hsapiens)
      obj_name_parts <- strsplit(obj_name, "\\\\.")[[1]]
      if (exists(obj_name_parts[1])) {
        BSGenome <- get(obj_name_parts[1])
      } else {
        BSGenome <- get(obj_name)
      }
    } else {
      # Fallback default
      library(BSgenome.Hsapiens.UCSC.hg19)
      BSGenome <- Hsapiens
    }
    
    # Verify required input files exist in the working directory
    required_files <- c("count_ALL_chr22.txt", "chr1.bam")
    for (f in required_files) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing from working directory:", f))
      }
    }
    
    # Set up directory structure for BAM scanning
    dir.create("./bams", showWarnings = FALSE, recursive = TRUE)
    file.copy("chr1.bam", "./bams/chr1.bam", overwrite = TRUE)
    
    # Define parameters for the workflow
    chrset <- "chr1"
    targetcov <- 75
    covtolerance <- 10
    filecpgset <- "My_cpgset.rds"
    
    # 1. Inject common SNPs into reference genome using injectSNPsMAF
    genome <- list()
    genome[["chr1"]] <- BSGenome[["chr1"]] # Ensure chr1 is present for the in silico experiment
    genome[["chr22"]] <- injectSNPsMAF(
      gensequence = BSGenome[["chr22"]],
      frqcount = "count_ALL_chr22.txt",
      MAF = 0.01
    )
    
    # 2. Find CpGs using getCpGsetALL
    cpgset <- getCpGsetALL(genome)
    saveRDS(file = "My_cpgset.rds", object = cpgset)
    
    # 3. Generate artificial FASTQ reads using insilicoFASTQ
    insilicoFASTQ(
      con = "chr1.fastq.gz",
      gensequence = BSGenome[["chr1"]],
      fraglength = 75
    )
    
    # Define RaMWAS parameters
    param <- ramwasParameters(
      dirproject = ".",
      dirbam = "./bams",
      dirfilter = TRUE,
      bamnames = chrset,
      bam2sample = list(all_samples = chrset),
      scoretag = "AS",
      minscore = 100,
      minfragmentsize = targetcov,
      maxfragmentsize = targetcov,
      minavgcpgcoverage = 0,
      minnonzerosamples = 0,
      filecpgset = filecpgset
    )
    
    # Preprocess parameters
    param1 <- parameterPreprocess(param)
    
    # 4. Scan BAMs of aligned artificial reads using ramwas1scanBams
    ramwas1scanBams(param)
    
    # 5. Calculate normalized coverage of artificial reads using ramwas3normalizedCoverage
    ramwas3normalizedCoverage(param)
    
    # 6. Filter CpGs by in silico coverage
    param1 <- parameterPreprocess(param)
    cover <- fm.load(paste0(param1\$dircoveragenorm, "/Coverage"))
    
    fac <- rep(seq_along(cpgset), times = sapply(cpgset, length))
    levels(fac) <- names(cpgset)
    class(fac) <- "factor"
    cover <- split(cover, fac)
    
    cpgsetQC <- cpgset
    for (i in seq_along(cpgset)) {
      keep <- (cover[[i]] >= (targetcov - covtolerance)) & (cover[[i]] <= (targetcov + covtolerance))
      cpgsetQC[[i]] <- cpgset[[i]][keep]
    }
    
    # 7. Save the QC-filtered CpG set using saveRDS
    saveRDS(file = "My_cpgset_QC.rds", object = cpgsetQC)
    
    # Export summary of results
    summary_stats <- data.frame(
      Chromosome = names(cpgset),
      Original_CpGs = sapply(cpgset, length),
      QC_Filtered_CpGs = sapply(cpgsetQC, length)
    )
    write.csv(summary_stats, "cpg_qc_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_RAMWAS_CUSTOM_CPG_SET_AND_QC":',
        paste0('    ramwas: ', as.character(packageVersion('ramwas')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_cpg_set_and_qc.csv versions.yml
    """
}

workflow BIOC_RAMWAS_CUSTOM_CPG_SET_AND_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BSgenome, count_ALL_chr22.txt, chr1.fastq.gz, chr1.bam ] ]

    main:
    BIOC_RAMWAS_CUSTOM_CPG_SET_AND_QC(ch_input)

    emit:
    tables   = BIOC_RAMWAS_CUSTOM_CPG_SET_AND_QC.out.tables
    plots    = BIOC_RAMWAS_CUSTOM_CPG_SET_AND_QC.out.plots
    objects  = BIOC_RAMWAS_CUSTOM_CPG_SET_AND_QC.out.objects
    versions = BIOC_RAMWAS_CUSTOM_CPG_SET_AND_QC.out.versions
}
