#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gDRimport — pharmacoset_to_gdr
// Convert a PharmacoSet (PSet) object into a data.table format suitable for the gDR processing pipeline.
// Input: Tavor_2020
// Container: quay.io/biocontainers/bioconductor-gdrimport:1.8.1--r45hdfd78af_0
// R packages: data.table, gDRcore, gDRimport
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDRIMPORT_PHARMACOSET_TO_GDR {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-gdrimport:1.8.1--r45hdfd78af_0"

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
    .bm_deps <- c("data.table", "gDRcore", "gDRimport")
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
    
    library(gDRimport)
    library(gDRcore)
    library(data.table)
    
    # Override getPSet to read from local file if available, satisfying the requirement
    # to read the user input file "Tavor_2020" from the working directory.
    original_getPSet <- gDRimport::getPSet
    getPSet <- function(name, ...) {
      if (file.exists(name)) {
        return(readRDS(name))
      } else if (file.exists(paste0(name, ".rds"))) {
        return(readRDS(paste0(name, ".rds")))
      } else {
        return(original_getPSet(name, ...))
      }
    }
    
    pset <- getPSet ( "Tavor_2020" )
    dt <- convert_pset_to_df ( pharmacoset = pset)
    subset_cl <- dt \$ Clid[ 1 ]
    x <- dt[Clid == subset_cl]
    se <- gDRcore :: runDrugResponseProcessingPipeline (x)
    
    fwrite(dt, "converted_pset.csv")
    saveRDS(se, "processed_se.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GDRIMPORT_PHARMACOSET_TO_GDR":
        gDRimport: \$(Rscript -e 'cat(as.character(packageVersion("gDRimport")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pharmacoset_to_gdr.csv versions.yml
    """
}

workflow BIOC_GDRIMPORT_PHARMACOSET_TO_GDR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Tavor_2020 ] ]

    main:
    BIOC_GDRIMPORT_PHARMACOSET_TO_GDR(ch_input)

    emit:
    tables   = BIOC_GDRIMPORT_PHARMACOSET_TO_GDR.out.tables
    plots    = BIOC_GDRIMPORT_PHARMACOSET_TO_GDR.out.plots
    objects  = BIOC_GDRIMPORT_PHARMACOSET_TO_GDR.out.objects
    versions = BIOC_GDRIMPORT_PHARMACOSET_TO_GDR.out.versions
}
