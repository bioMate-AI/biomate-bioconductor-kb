#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rmassbank — multiplicity_filtering_workflow
// Combine peak multiplicities from standard and confirmation spectra runs to prevent erroneous deletion of low-occurrence peaks.
// Input: NarcoticsDataset.csv, raw_spectra.mzML
// Container: quay.io/biocontainers/bioconductor-rmassbank:3.20.0--r45ha27e39d_0
// R packages: RMassBank
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RMASSBANK_MULTIPLICITY_FILTERING_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rmassbank:3.20.0--r45ha27e39d_0"

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
    .bm_deps <- c("RMassBank")
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
    
    library(RMassBank)
    
    # --- Initialize default settings and define the spectra list ---
    RmbDefaultSettings()
    getOption("RMassBank")\$multiplicityFilter
    rmbo <- getOption("RMassBank")
    rmbo\$spectraList <- list(
        list(mode="CID", ces = "35%", ce = "35 % (nominal)", res = 7500),
        list(mode="HCD", ces = "15%", ce = "15 % (nominal)", res = 7500),
        list(mode="HCD", ces = "30%", ce = "30 % (nominal)", res = 7500)
    )
    options(RMassBank = rmbo)
    
    # --- Load the compound list and initialize the workspace ---
    loadList("NarcoticsDataset.csv")
    
    w <- newMsmsWorkspace()
    
    # Adapt file reading to use the user-provided raw_spectra.mzML.
    # RMassBank requires file names to contain the compound ID (e.g., _1234_pos.mzML)
    # to match them with the compound list. We copy the input file to match the IDs.
    compounds <- read.csv("NarcoticsDataset.csv", stringsAsFactors = FALSE)
    ids <- compounds\$ID
    target_ids <- ids[1:min(2, length(ids))]
    files <- paste0("raw_spectra_", target_ids, "_pos.mzML")
    for (i in seq_along(files)) {
        file.copy("raw_spectra.mzML", files[i], overwrite = TRUE)
    }
    w@files <- files
    
    # --- Run msmsWorkflow steps 1 to 7 for the primary spectra ---
    w1 <- msmsWorkflow(w, mode="pH", steps=c(1))
    w1@spectra <- as(lapply(w1@spectra, function(s)
        {
    		s@children <- s@children[seq_len(min(3, length(s@children)))]
    		s
        }),"SimpleList")
    w1 <- msmsWorkflow(w1, mode="pH", steps=c(2:7))
    
    # --- Run msmsWorkflow steps 1 to 7 for the confirmation ---
    w2 <- msmsWorkflow(w, mode="pH", steps=c(1), confirmMode = 1)
    w2@spectra <- as(lapply(w2@spectra, function(s)
        {
    		s@children <- s@children[seq_len(min(3, length(s@children)))]
    		s
        }),"SimpleList")
    w2 <- msmsWorkflow(w2, mode="pH", steps=c(2:7))
    
    # --- Combine the workspaces using combineMultiplicities ---
    wTotal <- combineMultiplicities(c(w1, w2))
    
    # --- Run msmsWorkflow step 8 on the combined workspace to ---
    wTotal <- msmsWorkflow(wTotal, steps=8, mode="pH", archivename = "output")
    
    # Save the final workspace object
    saveRDS(wTotal, "wTotal_multiplicity_filtered.rds")

    writeLines(c(
        '"BIOC_RMASSBANK_MULTIPLICITY_FILTERING_WORKFLOW":',
        paste0('        rmassbank: ', as.character(packageVersion("rmassbank")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiplicity_filtering_workflow.csv versions.yml
    """
}

workflow BIOC_RMASSBANK_MULTIPLICITY_FILTERING_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ NarcoticsDataset.csv, raw_spectra.mzML ] ]

    main:
    BIOC_RMASSBANK_MULTIPLICITY_FILTERING_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_RMASSBANK_MULTIPLICITY_FILTERING_WORKFLOW.out.tables
    plots    = BIOC_RMASSBANK_MULTIPLICITY_FILTERING_WORKFLOW.out.plots
    objects  = BIOC_RMASSBANK_MULTIPLICITY_FILTERING_WORKFLOW.out.objects
    versions = BIOC_RMASSBANK_MULTIPLICITY_FILTERING_WORKFLOW.out.versions
}
