#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TRONCO — data_manipulation_and_oncoprint_visualization
// Prepare a TRONCO genomic alteration dataset by renaming, joining, filtering events, annotating clinical stages, and visualizing the cohort using oncoprints.
// Input: dataset.RData
// Container: quay.io/biocontainers/bioconductor-tronco:2.42.0--r45hdfd78af_0
// R packages: rWikiPathways, TRONCO
// Bioconductor: 3.20 | R: 4.4
// Requires: TRONCO
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Rename genes and event types
//  * 2. [Core Analysis] Join events or types
//  * 3. [Core Analysis] Delete unwanted genes, events, samples, or types
//  * 4. [Core Analysis] Subset samples and filter events by frequency/names
//  * 5. [Core Analysis] Annotate clinical stages
//  * 6. [Core Analysis] Generate sorted or clustered oncoprints

nextflow.enable.dsl = 2

process BIOC_TRONCO_DATA_MANIPULATION_AND_ONCOPRINT_VISUALIZATION {
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
    .bm_deps <- c("rWikiPathways", "TRONCO")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(TRONCO)
    
    # Load user input
    if (!file.exists("dataset.RData")) {
      stop("Input file 'dataset.RData' not found in the working directory.")
    }
    
    # Load the RData file into a temporary environment to extract the TRONCO object
    temp_env = new.env()
    load("dataset.RData", envir = temp_env)
    obj_names = ls(temp_env)
    if (length(obj_names) == 0) {
      stop("The loaded 'dataset.RData' is empty.")
    }
    
    # Assign the loaded TRONCO object to 'aCML' to match the documented code variable name
    aCML = temp_env[[obj_names[1]]]
    
    # 1. Rename genes and event types
    dataset = aCML
    
    curr_genes = as.genes(dataset)
    if (length(curr_genes) > 0) {
      dataset = rename.gene(dataset, curr_genes[1], 'new name')
    }
    
    curr_types = as.types(dataset)
    if (length(curr_types) > 0) {
      dataset = rename.type(dataset, curr_types[1], 'new type')
    }
    
    # 2. Join events or types
    events_df = as.events(dataset)
    event_ids = rownames(events_df)
    if (length(event_ids) >= 2) {
      dataset = join.events(dataset, event_ids[1], event_ids[2], new.event='test', new.type='banana', event.color='yellow')
    }
    
    curr_types = as.types(dataset)
    if (length(curr_types) >= 2) {
      dataset = join.types(dataset, curr_types[1], curr_types[2])
    }
    
    # 3. Delete unwanted genes, events, samples, or types
    curr_genes = as.genes(dataset)
    if (length(curr_genes) > 0) {
      dataset = delete.gene(dataset, gene = curr_genes[1])
    }
    
    events_df = as.events(dataset)
    if (nrow(events_df) > 0) {
      dataset = delete.event(dataset, gene = as.character(events_df[1, 'event']), type = as.character(events_df[1, 'type']))
    }
    
    curr_samples = as.samples(dataset)
    if (length(curr_samples) >= 2) {
      dataset = delete.samples(dataset, samples = curr_samples[1:2])
    }
    
    curr_types = as.types(dataset)
    if (length(curr_types) > 0) {
      dataset = delete.type(dataset, type = curr_types[1])
    }
    
    # 4. Subset samples and filter events by frequency/names
    curr_samples = as.samples(dataset)
    if (length(curr_samples) >= 3) {
      dataset = samples.selection(dataset, samples = curr_samples[1:3])
    }
    
    curr_genes = as.genes(dataset)
    if (length(curr_genes) >= 3) {
      dataset = events.selection(dataset, filter.freq = .05, filter.in.names = curr_genes[1:2], filter.out.names = curr_genes[3])
    } else {
      dataset = events.selection(dataset, filter.freq = .05)
    }
    
    # 5. Annotate clinical stages
    # Dynamically determine the number of samples to avoid dimension mismatch
    num_samples = length(as.samples(dataset))
    if (num_samples > 0) {
      half_samples = floor(num_samples / 2)
      other_half = num_samples - half_samples
      stages = c(rep('stage 1', half_samples), rep('stage 2', other_half))
      stages = as.matrix(stages)
      rownames(stages) = as.samples(dataset)
      dataset = annotate.stages(dataset, stages = stages)
    }
    
    # 6. Generate sorted or clustered oncoprints and save to PDF files
    pdf("oncoprint_aCML_default.pdf", width = 10, height = 8)
    tryCatch({
      oncoprint(aCML)
    }, error = function(e) {
      message("Error plotting oncoprint(aCML): ", e\$message)
    })
    dev.off()
    
    pdf("oncoprint_aCML_clustered.pdf", width = 10, height = 8)
    tryCatch({
      genes_aCML = as.genes(aCML)
      annot_genes = list()
      if (length(genes_aCML) >= 2) {
        annot_genes\$one = as.list(genes_aCML[1:2])
      }
      if (length(genes_aCML) >= 4) {
        annot_genes\$two = as.list(genes_aCML[3:4])
      }
      
      if (length(annot_genes) > 0) {
        oncoprint(aCML, legend = FALSE, samples.cluster = TRUE, gene.annot = annot_genes, gene.annot.color = 'Set2', genes.cluster = TRUE)
      } else {
        oncoprint(aCML, legend = FALSE, samples.cluster = TRUE, genes.cluster = TRUE)
      }
    }, error = function(e) {
      message("Error plotting clustered oncoprint(aCML): ", e\$message)
    })
    dev.off()
    
    pdf("oncoprint_dataset_default.pdf", width = 10, height = 8)
    tryCatch({
      oncoprint(dataset, legend = FALSE)
    }, error = function(e) {
      message("Error plotting oncoprint(dataset): ", e\$message)
    })
    dev.off()
    
    pdf("oncoprint_dataset_grouped.pdf", width = 10, height = 8)
    tryCatch({
      if (has.stages(dataset)) {
        oncoprint(dataset, group.samples = as.stages(dataset))
      } else {
        oncoprint(dataset)
      }
    }, error = function(e) {
      message("Error plotting grouped oncoprint(dataset): ", e\$message)
    })
    dev.off()
    
    # Save the final processed dataset object
    saveRDS(dataset, "processed_dataset.rds")

    writeLines(c(
        '"BIOC_TRONCO_DATA_MANIPULATION_AND_ONCOPRINT_VISUALIZATION":',
        paste0('    TRONCO: ', as.character(packageVersion('TRONCO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_data_manipulation_and_oncoprint_visualization.csv versions.yml
    """
}

workflow BIOC_TRONCO_DATA_MANIPULATION_AND_ONCOPRINT_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataset.RData ] ]

    main:
    BIOC_TRONCO_DATA_MANIPULATION_AND_ONCOPRINT_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_TRONCO_DATA_MANIPULATION_AND_ONCOPRINT_VISUALIZATION.out.tables
    plots    = BIOC_TRONCO_DATA_MANIPULATION_AND_ONCOPRINT_VISUALIZATION.out.plots
    objects  = BIOC_TRONCO_DATA_MANIPULATION_AND_ONCOPRINT_VISUALIZATION.out.objects
    versions = BIOC_TRONCO_DATA_MANIPULATION_AND_ONCOPRINT_VISUALIZATION.out.versions
}
