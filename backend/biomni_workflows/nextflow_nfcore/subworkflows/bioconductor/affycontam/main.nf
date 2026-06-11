#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: affyContam — affybatch_contamination_and_qa
// Introduce structured circular and rectangular defects into AffyBatch microarray data and evaluate their impact on quality control and downstream analysis.
// Input: user_data.affybatch
// Container: quay.io/biocontainers/bioconductor-affycontam:1.68.0--r45hdfd78af_0
// R packages: affy, affyContam, affydata, affymvout, limma, spikein
// Bioconductor: 3.20 | R: 4.4
// Requires: affy, affyContam
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the AffyBatch data and visualize an original chip
//  * 2. [Core Analysis] Apply circular contamination with constant values using setCircRegion
//  * 3. [Input & Preparation] Define and apply variance-inflated circular contamination using getCircRegion and setCircRegion
//  * 4. [Input & Preparation] Define and apply variance-inflated rectangular contamination using getRectRegion and setRectRegion
//  * 5. [Visualization & Output] Visualize the contaminated chip to verify the artifact

nextflow.enable.dsl = 2

process BIOC_AFFYCONTAM_AFFYBATCH_CONTAMINATION_AND_QA {
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
    .bm_deps <- c("affy", "affyContam", "affydata", "affymvout", "limma", "spikein")
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
    library(affy)
    library(affyContam)
    
    # 1. Load the AffyBatch data and visualize an original chip
    # Read the user-provided AffyBatch object from the working directory
    Dilution <- readRDS("user_data.affybatch")
    
    # Visualize the original chip and save to PDF
    pdf("original_chip.pdf")
    image(Dilution[,1])
    dev.off()
    
    # 2. Apply circular contamination with constant values using setCircRegion
    dilc = setCircRegion(Dilution, chip=1)
    
    # Save the intermediate constant circular contaminated object
    saveRDS(dilc, "dilc_constant_circular.rds")
    
    # Visualize the constant circular contamination
    pdf("constant_circular_contamination.pdf")
    image(dilc[,1], main="constant circular contamination")
    dev.off()
    
    # 3. Define and apply variance-inflated circular contamination using getCircRegion and setCircRegion
    incvarCircRegion = function(x, chip=1, center=c(150,500), rad=100, fac=3) {
     tmp = fac*getCircRegion(x, chip, center, rad)
     setCircRegion(x, chip, center, rad, vals=tmp)
    }
    
    tryout = incvarCircRegion(Dilution)
    
    # 4. Define and apply variance-inflated rectangular contamination using getRectRegion and setRectRegion
    incvarRectRegion = function(x, chip=1, xinds=350:700, yinds=1:700, fac=3) {
     tmp = fac*getRectRegion(x, chip, xinds, yinds)
     setRectRegion(x, chip, xinds, yinds, vals=tmp)
    }
    
    fin = incvarRectRegion(tryout)
    
    # 5. Visualize the contaminated chip to verify the artifact and save outputs
    pdf("composite_contamination.pdf")
    image(fin[,1], main="composite contamination")
    dev.off()
    
    # Save the final contaminated AffyBatch object
    saveRDS(fin, "contaminated_affybatch.rds")

    writeLines(c(
        '"BIOC_AFFYCONTAM_AFFYBATCH_CONTAMINATION_AND_QA":',
        paste0('    affyContam: ', as.character(packageVersion('affyContam')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affybatch_contamination_and_qa.csv versions.yml
    """
}

workflow BIOC_AFFYCONTAM_AFFYBATCH_CONTAMINATION_AND_QA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_data.affybatch ] ]

    main:
    BIOC_AFFYCONTAM_AFFYBATCH_CONTAMINATION_AND_QA(ch_input)

    emit:
    tables   = BIOC_AFFYCONTAM_AFFYBATCH_CONTAMINATION_AND_QA.out.tables
    plots    = BIOC_AFFYCONTAM_AFFYBATCH_CONTAMINATION_AND_QA.out.plots
    objects  = BIOC_AFFYCONTAM_AFFYBATCH_CONTAMINATION_AND_QA.out.objects
    versions = BIOC_AFFYCONTAM_AFFYBATCH_CONTAMINATION_AND_QA.out.versions
}
