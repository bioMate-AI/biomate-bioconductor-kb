#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CGEN — gxe_scan_tped
// Run a genome-wide association scan for gene-environment interactions using TPED genotype files and a phenotype file.
// Input: geno_data.tped.gz, geno_data.tfam, pheno.txt
// Container: quay.io/biocontainers/bioconductor-cgen:3.46.0--r45h63f16b7_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CGEN
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the subject list from the TFAM file
//  * 2. [Input & Preparation] Define the snp.list with the genotype file and format
//  * 3. [Input & Preparation] Define the pheno.list with phenotype file details and model variables
//  * 4. [Visualization & Output] Set output options
//  * 5. [Core Analysis] Run the GxE scan using GxE.scan
//  * 6. [Visualization & Output] Read and inspect the output file

nextflow.enable.dsl = 2

process BIOC_CGEN_GXE_SCAN_TPED {
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
    .bm_deps <- c("CGEN")
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
    
    # Load the required library
    library(CGEN)
    
    # Define the input files from the working directory
    geno.file <- "geno_data.tped.gz"
    subject.file <- "geno_data.tfam"
    pheno.file <- "pheno.txt"
    
    # 1. Define the subject list from the TFAM file
    subject.list <- list(file=subject.file, id.var=1:2, header=0, delimiter=" ")
    subject.list <- subject.file
    
    # 2. Define the snp.list with the genotype file and format
    snp.list <- list(file=geno.file, format="tped", subject.list=subject.list)
    
    # 3. Define the pheno.list with phenotype file details and model variables
    pheno.list <- list(file=pheno.file, id.var=c("Family", "Subject"),
                  file.type=3, delimiter="\t",
                  response.var="CaseControl", strata.var="Study",
                  main.vars=c("Gender", "Exposure", "Smoke_CURRENT", "Smoke_FORMER"),
                  int.vars="Exposure")
    
    # 4. Set output options
    out.file <- paste(getwd(), "/GxE.out", sep="")
    op <- list(out.file=out.file)
    
    # 5. Run the GxE scan using GxE.scan
    GxE.scan(snp.list, pheno.list, op=op)
    
    # 6. Read and inspect the output file
    x <- read.table(out.file, header=1, as.is=TRUE, sep="\t")
    print(x[1:5, ])
    
    # Write named output files for the meaningful results
    write.csv(x, "gxe_scan_results.csv", row.names=FALSE)
    saveRDS(x, "gxe_scan_results.rds")

    writeLines(c(
        '"BIOC_CGEN_GXE_SCAN_TPED":',
        paste0('    CGEN: ', as.character(packageVersion('CGEN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gxe_scan_tped.csv versions.yml
    """
}

workflow BIOC_CGEN_GXE_SCAN_TPED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geno_data.tped.gz, geno_data.tfam, pheno.txt ] ]

    main:
    BIOC_CGEN_GXE_SCAN_TPED(ch_input)

    emit:
    tables   = BIOC_CGEN_GXE_SCAN_TPED.out.tables
    plots    = BIOC_CGEN_GXE_SCAN_TPED.out.plots
    objects  = BIOC_CGEN_GXE_SCAN_TPED.out.objects
    versions = BIOC_CGEN_GXE_SCAN_TPED.out.versions
}
