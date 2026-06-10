#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: r453plus1toolbox — gs_mapper_analysis
// Import, filter, annotate, and report variants from a GS Reference Mapper project.
// Input: mapping/454HCDiffs.txt, mapping/454NewblerMetrics.txt
// Container: quay.io/biocontainers/bioconductor-r453plus1toolbox:1.56.0--r44h3df3fcb_0
// R packages: Biobase, R453Plus1Toolbox
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_R453PLUS1TOOLBOX_GS_MAPPER_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-r453plus1toolbox:1.56.0--r44h3df3fcb_0"

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
    .bm_deps <- c("Biobase", "R453Plus1Toolbox")
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
    library(R453Plus1Toolbox)
    library(Biobase)
    
    # Verify input files exist
    file1 <- "mapping/454HCDiffs.txt"
    file2 <- "mapping/454NewblerMetrics.txt"
    
    if (!file.exists(file1) || !file.exists(file2)) {
      stop(paste("Required input files missing. Please ensure both", file1, "and", file2, "exist in the working directory."))
    }
    
    # 1. Import GS Reference Mapper directories into a MapperSet object
    # Since the files are in 'mapping/', the parent directory is the current directory '.'
    dirs = "."
    mapperSet = MapperSet(dirs=dirs, samplenames="Sample1")
    
    # Save the imported MapperSet object
    saveRDS(mapperSet, "mapperSet.rds")
    
    # Export variant data to CSV
    variants_df = fData(mapperSet)
    write.csv(variants_df, "detected_variants.csv", row.names = TRUE)
    
    # 2. Annotate variants using Ensembl and 3. Generate HTML report
    # Wrapping in tryCatch as annotateVariants relies on external Ensembl biomaRt queries
    tryCatch({
      message("Annotating variants via Ensembl (biomaRt)...")
      mapperAnnot = annotateVariants(mapperSet)
      saveRDS(mapperAnnot, "mapperAnnot.rds")
      
      message("Generating HTML report...")
      htmlReport(mapperSet, annot=mapperAnnot, dir="htmlReportExampleMapper", title="htmlReport Example", minMut=3)
      message("Pipeline completed successfully. Outputs written to 'mapperSet.rds', 'detected_variants.csv', 'mapperAnnot.rds', and 'htmlReportExampleMapper/'.")
    }, error = function(e) {
      warning("Annotation or HTML report generation failed (possibly due to network/biomaRt issues): ", e\$message)
      message("Pipeline completed with warnings. 'mapperSet.rds' and 'detected_variants.csv' were successfully written.")
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_R453PLUS1TOOLBOX_GS_MAPPER_ANALYSIS":
        r453plus1toolbox: \$(Rscript -e 'cat(as.character(packageVersion("r453plus1toolbox")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gs_mapper_analysis.csv versions.yml
    """
}

workflow BIOC_R453PLUS1TOOLBOX_GS_MAPPER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mapping/454HCDiffs.txt, mapping/454NewblerMetrics.txt ] ]

    main:
    BIOC_R453PLUS1TOOLBOX_GS_MAPPER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_R453PLUS1TOOLBOX_GS_MAPPER_ANALYSIS.out.tables
    plots    = BIOC_R453PLUS1TOOLBOX_GS_MAPPER_ANALYSIS.out.plots
    objects  = BIOC_R453PLUS1TOOLBOX_GS_MAPPER_ANALYSIS.out.objects
    versions = BIOC_R453PLUS1TOOLBOX_GS_MAPPER_ANALYSIS.out.versions
}
