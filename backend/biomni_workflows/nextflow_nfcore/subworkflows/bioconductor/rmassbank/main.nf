#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rmassbank — msms_spectral_processing
// Extract, analyze, recalibrate, and filter MS/MS spectra from raw LC-MS data files.
// Input: mysettings.ini, Compoundlist.csv, raw_spectra.mzML
// Container: quay.io/biocontainers/bioconductor-rmassbank:3.20.0--r45ha27e39d_0
// R packages: RMassBank
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING {
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
    
    # Load required libraries
    library(RMassBank)
    
    # 1. Generate and load settings
    # If mysettings.ini exists, we back it up, run the template generator as documented,
    # then restore it to use the user's settings.
    user_settings_exist <- file.exists("mysettings.ini")
    if (user_settings_exist) {
      file.copy("mysettings.ini", "mysettings.ini.bak", overwrite = TRUE)
    }
    
    RmbSettingsTemplate("mysettings.ini")
    
    if (user_settings_exist) {
      file.copy("mysettings.ini.bak", "mysettings.ini", overwrite = TRUE)
      file.remove("mysettings.ini.bak")
    }
    
    loadRmbSettings("mysettings.ini")
    
    # 2. Initialize workspace and load compound list
    w <- newMsmsWorkspace()
    
    # Read the user's raw_spectra.mzML file from the working directory
    files <- list.files(".", "raw_spectra.mzML", full.names = TRUE)
    if (length(files) == 0) {
      files <- "raw_spectra.mzML"
    }
    basename(files)
    
    # Ensure we have at least 2 elements to satisfy files[1:2] without NA
    if (length(files) < 2) {
      files <- rep(files, 2)
    }
    w@files <- files[1:2]
    
    loadList("./Compoundlist.csv")
    
    # 3. Run msmsWorkflow steps 1 to 4
    w <- msmsWorkflow(w, mode="pH", steps=c(1:4), archivename = 
    				"pH_narcotics")
    
    # 4. Plot and inspect the recalibration curve
    pdf("recalibration_curve.pdf")
    plotRecalibration(w)
    dev.off()
    
    # Save the current workspace to act as the stored workspace for the next steps
    save(w, file = "pH_narcotics_RF.RData")
    
    # Load the stored workspace (replacing system.file with local file)
    storedW <- loadMsmsWorkspace("pH_narcotics_RF.RData")
    
    storedW <- msmsWorkflow(storedW, mode="pH", steps=4)
    
    w@rc <- storedW@parent@rc
    w@rc.ms1 <- storedW@parent@rc.ms1
    
    w <- msmsWorkflow(w, mode="pH", steps=4, archivename = 
    	"pH_narcotics", newRecalibration = FALSE)
    
    # 5. Run msmsWorkflow steps 5 to 8
    w <- msmsWorkflow(w, mode="pH", steps=c(5:8), archivename = 
    		"pH_narcotics")
    
    # Save final results
    saveRDS(w, "final_workspace.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING":
        rmassbank: \$(Rscript -e 'cat(as.character(packageVersion("rmassbank")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msms_spectral_processing.csv versions.yml
    """
}

workflow BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mysettings.ini, Compoundlist.csv, raw_spectra.mzML ] ]

    main:
    BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING(ch_input)

    emit:
    tables   = BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING.out.tables
    plots    = BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING.out.plots
    objects  = BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING.out.objects
    versions = BIOC_RMASSBANK_MSMS_SPECTRAL_PROCESSING.out.versions
}
