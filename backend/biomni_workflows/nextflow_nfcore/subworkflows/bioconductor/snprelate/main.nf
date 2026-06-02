#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SNPRelate
// Genome-wide association studies (GWAS) are widely used to investigate the genetic basis of diseases 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SNPRelate/inst/doc/SNPRelate.R
// Upstream  : MASS
// Downstream: RAIDS, SeqSQC
//
// Install: BiocManager::install("SNPRelate")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNPRELATE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-snprelate"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-snprelate:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-snprelate:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_snprelate_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_snprelate_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_snprelate_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SNPs)
    library(jsonlite)

    # --- Snpgdssummary [] ---
    # Key functions: snpgdsSummary, snpgdsExampleFileName
    ---------------------------------------------------------------------
    snpgdsSummary(snpgdsExampleFileName())
    # --- Gdsn [] ---
    # Key functions: gdsn
    ---------------------------------------------------------------------
    # Get the attributes of chromosome coding
    get.attr.gdsn(index.gdsn(genofile, "snp.chromosome"))
    # --- Snps [] ---
    # Key functions: SNPs, gdsn
    ---------------------------------------------------------------------
    # Take out genotype data for the first 3 samples and the first 5 SNPs
    (g <- read.gdsn(index.gdsn(genofile, "genotype"), start=c(1,1), count=c(5,3)))
    # --- Gdsn [] ---
    # Key functions: gdsn
    ---------------------------------------------------------------------
    # Get the attribute of genotype
    get.attr.gdsn(index.gdsn(genofile, "genotype"))
    # --- Head [] ---
    # Key functions: gdsn
    ---------------------------------------------------------------------
    # Take out snp.id
    head(read.gdsn(index.gdsn(genofile, "snp.id")))
    # Take out snp.rs.id
    head(read.gdsn(index.gdsn(genofile, "snp.rs.id")))
    # --- Gdsn [] ---
    # Key functions: gdsn, snpgdsClose
    ---------------------------------------------------------------------
    # Read population information
    pop <- read.gdsn(index.gdsn(genofile, path="sample.annot/pop.group"))
    table(pop)
    # Close the GDS file
    # --- Data [] ---
    # Key functions: snpgdsCreateGeno, snpgdsOpen, snpgdsClose
    ---------------------------------------------------------------------
    # Load data
    data(hapmap_geno)
    # Create a gds file
    snpgdsCreateGeno("test.gds", genmat = hapmap_geno$genotype,
    # --- snpgds B E D2 G D S [] ---
    # Key functions: snpgdsBED2GDS, snpgdsSummary
    ---------------------------------------------------------------------
    # Convert
    snpgdsBED2GDS(bed.fn, fam.fn, bim.fn, "test.gds")
    # Summary
    snpgdsSummary("test.gds")
    # --- snpgds V C F2 G D S [] ---
    # Key functions: snpgdsVCF2GDS, snpgdsSummary
    ---------------------------------------------------------------------
    # Reformat
    snpgdsVCF2GDS(vcf.fn, "test.gds", method="biallelic.only")
    # Summary
    snpgdsSummary("test.gds")
    # --- Snpgdsopen [] ---
    # Key functions: snpgdsOpen, snpgdsExampleFileName
    ---------------------------------------------------------------------
    # Open the GDS file
    genofile <- snpgdsOpen(snpgdsExampleFileName())
    # --- Scan [] ---
    # Key functions: gdsn
    ---------------------------------------------------------------------
    # Get population information
    #   or pop_code <- scan("pop.txt", what=character())
    #   if it is stored in a text file "pop.txt"
    pop_code <- read.gdsn(index.gdsn(genofile, path="sample.annot/pop.group"))
    # --- Snpgdspca [] ---
    # Key functions: snpgdsPCA
    ---------------------------------------------------------------------
    # Run PCA
    pca <- snpgdsPCA(genofile, snp.id=snpset.id, num.thread=2)
    # --- Proportion [] ---
    # Key functions: proportion
    ---------------------------------------------------------------------
    # variance proportion (%)
    pc.percent <- pca$varprop*100
    head(round(pc.percent, 2))
    # --- Gdsn [] ---
    # Key functions: gdsn
    ---------------------------------------------------------------------
    # Get sample id
    sample.id <- read.gdsn(index.gdsn(genofile, "sample.id"))
    # Get population information
    #   or pop_code <- scan("pop.txt", what=character())
    # --- Gdsn [] ---
    # Key functions: gdsn, snpgdsFst, factor
    ---------------------------------------------------------------------
    # Get sample id
    sample.id <- read.gdsn(index.gdsn(genofile, "sample.id"))
    # Get population information
    #   or pop_code <- scan("pop.txt", what=character())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_snprelate_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_snprelate_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_snprelate_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SNPRELATE:", paste0("    snprelate: ", packageVersion("SNPRelate"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snprelate_results.csv
    touch ${prefix}_snprelate_output.rds
    echo "BIOC_SNPRELATE:" > versions.yml
    echo "    snprelate: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SNPRELATE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SNPRELATE(ch_input)

    emit:
    results  = BIOC_SNPRELATE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SNPRELATE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SNPRELATE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SNPRELATE.out.versions  // channel: path(versions.yml)
}
