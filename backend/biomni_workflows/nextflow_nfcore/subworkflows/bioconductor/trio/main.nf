#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: trio — standard_tdt_association_testing
// Test individual SNPs, two-way SNP interactions, and gene-environment interactions using genotypic TDT, allelic TDT, or score tests.
// Input: pedigree_data.ped, environmental_covariates.txt
// Container: quay.io/biocontainers/bioconductor-trio:3.48.0--r45hdfd78af_0
// R packages: trio
// Bioconductor: 3.20 | R: 4.4
// Requires: trio
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Format pedigree IDs and convert pedigree data to a genotype matrix using ped2geno
//  * 2. [Core Analysis] Run single SNP gTDT under additive, dominant, or recessive models using tdt
//  * 3. [Core Analysis] Perform high-throughput single SNP testing using colTDT
//  * 4. [Core Analysis] Run MAX tests to find the best genetic model using colTDTmaxStat and colTDTmaxTest
//  * 5. [Core Analysis] Test two-way SNP interactions using tdtGxG or colGxG
//  * 6. [Core Analysis] Test gene-environment interactions using colGxE and extract statistics using getGxEstats
//  * 7. [Core Analysis] Run allelic TDT using allelicTDT or score tests using scoreTDT

nextflow.enable.dsl = 2

process BIOC_TRIO_STANDARD_TDT_ASSOCIATION_TESTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("trio")
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
        
    library(trio)
    
    # 1. Read pedigree data and convert to a genotype matrix using read.pedfile
    geno <- read.pedfile("pedigree_data.ped", p2g=TRUE)
    
    # Define mat.test using all available SNPs dynamically
    mat.test <- geno
    
    # 2. Run single SNP gTDT under additive, dominant, or recessive models using tdt
    tdt(mat.test[,1])
    tdt(mat.test[,1], model="dominant")
    tdt(mat.test[,1], model="recessive")
    
    # 3. Perform high-throughput single SNP testing using colTDT
    tdtGxG(mat.test[,1], mat.test[,2])
    tdtGxG(mat.test[,1], mat.test[,2], test="screen")
    tdt.out <- colTDT(mat.test)
    print(tdt.out, 3)
    
    # 4. Run MAX tests to find the best genetic model using colTDTmaxStat and colTDTmaxTest
    max.stat <- colTDTmaxStat(mat.test)
    max.out <- colTDTmaxTest(mat.test, perm=1000)
    
    # 5. Test two-way SNP interactions using tdtGxG or colGxG
    n_snps <- ncol(mat.test)
    n1 <- floor(n_snps / 2)
    n2 <- n_snps - n1
    genes <- paste("G", rep(1:2, c(n1, n2)), sep="")
    tdt2.out <- colGxG(mat.test, genes=genes)
    
    # 6. Test gene-environment interactions using colGxE and extract statistics using getGxEstats
    sex <- scan("environmental_covariates.txt", quiet=TRUE)
    gxe.out <- colGxE(mat.test, sex)
    dat.top3 <- getGxEstats(gxe.out, top=3, sortBy="lrt2df")
    
    # 7. Run allelic TDT using allelicTDT or score tests using scoreTDT
    a.out <- allelicTDT(mat.test)
    a.out2 <- allelicTDT(mat.test, correct=TRUE)
    s.out <- scoreTDT(mat.test)
    
    # Save outputs
    saveRDS(tdt.out, "tdt_out.rds")
    saveRDS(max.stat, "max_stat.rds")
    saveRDS(max.out, "max_out.rds")
    saveRDS(tdt2.out, "tdt2_out.rds")
    saveRDS(gxe.out, "gxe_out.rds")
    saveRDS(a.out, "a_out.rds")
    saveRDS(a.out2, "a_out2.rds")
    saveRDS(s.out, "s_out.rds")
    write.csv(dat.top3, "gxe_top3_stats.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_TRIO_STANDARD_TDT_ASSOCIATION_TESTING":',
        paste0('    trio: ', as.character(packageVersion('trio')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_tdt_association_testing.csv versions.yml
    """
}

workflow BIOC_TRIO_STANDARD_TDT_ASSOCIATION_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pedigree_data.ped, environmental_covariates.txt ] ]

    main:
    BIOC_TRIO_STANDARD_TDT_ASSOCIATION_TESTING(ch_input)

    emit:
    tables   = BIOC_TRIO_STANDARD_TDT_ASSOCIATION_TESTING.out.tables
    plots    = BIOC_TRIO_STANDARD_TDT_ASSOCIATION_TESTING.out.plots
    objects  = BIOC_TRIO_STANDARD_TDT_ASSOCIATION_TESTING.out.objects
    versions = BIOC_TRIO_STANDARD_TDT_ASSOCIATION_TESTING.out.versions
}
