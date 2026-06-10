#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metagene2 — metagene_heatmap
// Plot individual genomic regions as a heatmap, optionally ordered by signal intensity.
// Input: mg
// Container: quay.io/biocontainers/bioconductor-metagene2:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: metagene2
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Generate heatmap; 2. Generate heatmap with custom coverage ordering

nextflow.enable.dsl = 2

process BIOC_METAGENE2_METAGENE_HEATMAP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    library(metagene2)
    
    # Read the pre-calculated metagene2 object from the working directory
    if (file.exists("mg")) {
      mg <- readRDS("mg")
    } else if (file.exists("mg.rds")) {
      mg <- readRDS("mg.rds")
    } else {
      stop("Error: User input file 'mg' (RDS format) not found in the working directory.")
    }
    
    # Stage 1: Generate heatmap
    message("Generating default heatmap...")
    p1 <- metagene2_heatmap(mg)
    pdf("heatmap_default.pdf")
    print(p1)
    dev.off()
    message("Saved default heatmap to 'heatmap_default.pdf'")
    
    # Stage 2: Generate heatmap with custom coverage ordering
    message("Generating ordered heatmap...")
    tryCatch({
      p2 <- metagene2_heatmap(mg, coverage_order(mg, "align1_rep1"))
      pdf("heatmap_ordered.pdf")
      print(p2)
      dev.off()
      message("Saved ordered heatmap to 'heatmap_ordered.pdf'")
    }, error = function(e) {
      warning("Failed to generate ordered heatmap using 'align1_rep1'. Attempting fallback with available design groups...")
      
      # Fallback to the first available design group if 'align1_rep1' is not present in the user's object
      design_groups <- tryCatch(mg\$get_design_group_names(), error = function(err) NULL)
      if (!is.null(design_groups) && length(design_groups) > 0) {
        fallback_group <- design_groups[1]
        message("Using fallback design group: ", fallback_group)
        p2 <- metagene2_heatmap(mg, coverage_order(mg, fallback_group))
        pdf("heatmap_ordered.pdf")
        print(p2)
        dev.off()
        message("Saved ordered heatmap (fallback) to 'heatmap_ordered.pdf'")
      } else {
        stop("No design groups available to order the heatmap: ", e\$message)
      }
    })

    writeLines(c(
        '"BIOC_METAGENE2_METAGENE_HEATMAP":',
        paste0('    metagene2: ', as.character(packageVersion('metagene2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metagene_heatmap.csv versions.yml
    """
}

workflow BIOC_METAGENE2_METAGENE_HEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mg ] ]

    main:
    BIOC_METAGENE2_METAGENE_HEATMAP(ch_input)

    emit:
    tables   = BIOC_METAGENE2_METAGENE_HEATMAP.out.tables
    plots    = BIOC_METAGENE2_METAGENE_HEATMAP.out.plots
    objects  = BIOC_METAGENE2_METAGENE_HEATMAP.out.objects
    versions = BIOC_METAGENE2_METAGENE_HEATMAP.out.versions
}
