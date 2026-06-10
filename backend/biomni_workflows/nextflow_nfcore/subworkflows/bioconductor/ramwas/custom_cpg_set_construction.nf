#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ramwas — custom_cpg_set_construction
// Construct a custom CpG set from a reference genome, inject common SNPs filtered by minor allele frequency, and perform an in silico alignment experiment to filt
// Input: count_ALL_chr22.txt, bams/
// Container: quay.io/biocontainers/bioconductor-ramwas:1.34.0--r45h01b2380_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, ramwas
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ramwas:1.34.0--r45h01b2380_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "ramwas")
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
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    # Set reference genome
    BSGenome = Hsapiens
    
    # 1. Inject common SNPs (MAF > 0.01) into the reference genome
    message("Injecting SNPs into chr22...")
    genome = list()
    genome[["chr22"]] = injectSNPsMAF(
      gensequence = BSGenome[["chr22"]],
      frqcount = "count_ALL_chr22.txt",
      MAF = 0.01
    )
    
    # 2. Identify all potential CpG sites in the SNP-injected genome
    message("Identifying potential CpG sites...")
    cpgset = getCpGsetALL(genome)
    
    # Save the initial CpG set to an RDS file as required by ramwasParameters
    filecpgset = "cpgset_initial.rds"
    saveRDS(cpgset, file = filecpgset)
    
    # 3. Generate artificial FASTQ reads from the reference genome for the alignment experiment
    message("Generating in silico FASTQ reads...")
    insilicoFASTQ(
      con = "chr1.fastq.gz",
      gensequence = BSGenome[["chr1"]],
      fraglength = 75
    )
    
    # Define parameters for scanning the simulated BAM files
    targetcov = 75
    covtolerance = 10
    
    # Dynamically detect BAM files in the user-provided bams/ directory
    bam_files = list.files("bams", pattern = "\\\\.bam\$")
    if (length(bam_files) == 0) {
      stop("Error: No BAM files found in the 'bams/' directory.")
    }
    chrset = gsub("\\\\.bam\$", "", bam_files)
    
    # 4. Define parameters for scanning the simulated BAM files
    message("Setting up RaMWAS parameters...")
    param = ramwasParameters(
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
    param1 = parameterPreprocess(param)
    
    # 5. Scan the simulated BAMs and calculate normalized coverage
    message("Scanning BAM files...")
    ramwas1scanBams(param)
    
    message("Calculating normalized coverage...")
    ramwas3normalizedCoverage(param)
    
    # 6. Filter the CpG set by keeping only the sites that fall within the expected coverage tolerance
    message("Filtering CpG set by in silico coverage...")
    # Preprocess parameters to learn the location of coverage matrix
    param1 = parameterPreprocess(param)
    
    # Load the coverage matrix (vector)
    cover = fm.load(paste0(param1\$dircoveragenorm, "/Coverage"))
    
    # Split the coverage by chromosomes
    fac = rep(seq_along(cpgset), times = sapply(cpgset, length))
    levels(fac) = names(cpgset)
    class(fac) = "factor"
    cover = split(cover, fac)
    
    # Filter CpGs on each chromosome by the coverage
    cpgsetQC = cpgset
    for (i in seq_along(cpgset)) {
      keep = (cover[[i]] >= (targetcov - covtolerance)) & (cover[[i]] <= (targetcov + covtolerance))
      cpgsetQC[[i]] = cpgset[[i]][keep]
    }
    
    # Save the final QC-filtered CpG set
    output_rds = "My_cpgset_QC.rds"
    saveRDS(file = output_rds, object = cpgsetQC)
    message("Saved QC-filtered CpG set to: ", output_rds)
    
    # Write a summary of the filtering process
    summary_df = data.frame(
      Chromosome = names(cpgset),
      Original_CpGs = sapply(cpgset, length),
      Filtered_CpGs = sapply(cpgsetQC, length)
    )
    write.csv(summary_df, "cpg_filtering_summary.csv", row.names = FALSE)
    message("Saved filtering summary to: cpg_filtering_summary.csv")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION":
        ramwas: \$(Rscript -e 'cat(as.character(packageVersion("ramwas")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_cpg_set_construction.csv versions.yml
    """
}

workflow BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_ALL_chr22.txt, bams/ ] ]

    main:
    BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION(ch_input)

    emit:
    tables   = BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION.out.tables
    plots    = BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION.out.plots
    objects  = BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION.out.objects
    versions = BIOC_RAMWAS_CUSTOM_CPG_SET_CONSTRUCTION.out.versions
}
