#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: prebs — manufacturer_cdf_expression
// Calculate probe set-level expression values from RNA-seq BAM files using a manufacturer's CDF mapping.
// Input: input1.bam, input2.bam, HGU133Plus2_mapping.txt
// Container: quay.io/biocontainers/bioconductor-prebs:1.50.0--r45hdfd78af_0
// R packages: Biobase, prebs, prebsdata
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PREBS_MANUFACTURER_CDF_EXPRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-prebs:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biobase", "prebs", "prebsdata")
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
    
    # 1. Load the prebs and prebsdata libraries
    library(prebs)
    library(prebsdata)
    library(Biobase)
    
    # 2. Define paths to BAM files and the manufacturer's CDF mapping file
    bam_file1 <- "input1.bam"
    bam_file2 <- "input2.bam"
    bam_files <- c(bam_file1, bam_file2)
    manufacturer_cdf_mapping <- "HGU133Plus2_mapping.txt"
    
    # 3. Run calc_prebs specifying the manufacturer's mapping file and the CDF package name
    prebs_values <- calc_prebs(bam_files, manufacturer_cdf_mapping, 
                               cdf_name="hgu133plus2cdf")
    
    # 4. Extract and view the probe set expression matrix using exprs()
    expression_matrix <- exprs(prebs_values)
    print(head(expression_matrix))
    
    # Write named output files for the meaningful results
    write.table(expression_matrix, file="prebs_values.txt", quote=FALSE, sep="\t")
    saveRDS(prebs_values, file="prebs_values.rds")

    writeLines(c(
        '"BIOC_PREBS_MANUFACTURER_CDF_EXPRESSION":',
        paste0('        prebs: ', as.character(packageVersion("prebs")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_manufacturer_cdf_expression.csv versions.yml
    """
}

workflow BIOC_PREBS_MANUFACTURER_CDF_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input1.bam, input2.bam, HGU133Plus2_mapping.txt ] ]

    main:
    BIOC_PREBS_MANUFACTURER_CDF_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_PREBS_MANUFACTURER_CDF_EXPRESSION.out.tables
    plots    = BIOC_PREBS_MANUFACTURER_CDF_EXPRESSION.out.plots
    objects  = BIOC_PREBS_MANUFACTURER_CDF_EXPRESSION.out.objects
    versions = BIOC_PREBS_MANUFACTURER_CDF_EXPRESSION.out.versions
}
