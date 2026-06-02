#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GladiaTOX
// GladiaTOX R package is an open-source, flexible solution to high-content screening data processing a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GladiaTOX/inst/doc/GladiaTOX.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GladiaTOX")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GLADIATOX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gladiatox"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gladiatox:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gladiatox:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gladiatox_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gladiatox_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gladiatox_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GladiaTOX)
    library(jsonlite)


    # --- Eval=true [] ---
    # Key functions: getwd, glPlotPieLogo, sql, gladiatoxdb.sqlite, gtoxConf
    # Load GladiaTOX package and setup an output directory
    # Change outdir accordingly to the folder path you want the reports to be saved
    library(GladiaTOX)
    outdir <- getwd()
    glPlotPieLogo()
    sqlite_src <- file.path(system.file(package="GladiaTOX"), "sql",
                            "gladiatoxdb.sqlite")
    # sqlite database location
    gtoxConf(   drvr = "SQLite",
                host = NA,
                user = NA,
                pass = NULL,
                db = sqlite_src)

    # --- Eval=true [] ---
    # Key functions: gtoxLoadAsid, load, extdata, data_for_vignette.rda
    # List available studies
    gtoxLoadAsid()
    load(system.file("extdata", "data_for_vignette.rda", package="GladiaTOX"))
    print(head(plate), row.names = FALSE)
    print(head(chnmap, 7), row.names = FALSE)

    # --- Eval=true [] ---
    # Key functions: gtoxRun, gtoxLoadAeid, function, tryCatch, gtoxCalcVmad, asid
    print(head(dat), row.names = FALSE)
    ## Set study parameters
    std.nm <- "SampleStudy" # study name
    phs.nm <- "PhaseII" # study phase
    # Run level 1 to level 3 functions
    res <- gtoxRun(asid = asid, slvl = 1, elvl = 3, mc.cores = 2)
    # Extract assay endpoints ids of the study
    aeids <- gtoxLoadAeid(fld = "asid", val = asid)$aeid
    # Compute Vehicle Median Absolute deviation
    tmp <- mapply(function(xx){
        tryCatch(gtoxCalcVmad(inputs = xx, aeid = xx, 
        notes = "computed within study"), 
        error = function(e) NULL)},
        as.integer(aeids))

    # --- Include=true [] ---
    # Key functions: gtoxRun, gtoxReport, damage, gtoxLoadAcid, gtoxLoadApid, gtoxLoadData, asid, acnm
    # Apply all functions from level 1 to level 6
    res <- gtoxRun(asid = asid, slvl = 1, elvl = 6, mc.cores = 2)
    ## QC report
    gtoxReport(type = "qc", asid = asid, report_author = "report author",
    report_title = "Vignette QC report", odir = outdir)
    # Define assay component and extract assay component ID
    acnm <- "DNA damage (pH2AX)_DNA damage (pH2AX)_4h"
    acid <- gtoxLoadAcid(fld=c("asid", "acnm"), val=list(asid,acnm))[, acid]
    # Extract assay plate ID corresponding to plate name S-000031351
    apid <- gtoxLoadApid()[u_boxtrack == "S-000031351", apid]
    # Load level 2 data (Raw data before normalization)
    l2 <- gtoxLoadData(lvl = 2L, fld = "acid", val = acid)
    gtoxPlotPlate(dat = l2, apid = apid, id = acid)

    # --- Eval=true [] ---
    # Key functions: gtoxLoadAeid, gtoxLoadWaid, gtoxLoadData, acid, analysis_direction, apid, wllt, spid
    # Extract assay endpoint ID
    aeid <- gtoxLoadAeid(fld = c("acid", "analysis_direction"), 
                            val = list(acid, "up"))[, aeid]
    # Extract sample ID
    spid <- gtoxLoadWaid(fld = c("apid", "wllt"), 
                            val = list(apid, "c"))[,unique(spid)]
    # Collect level 4 data (normalized data)
    m4id <- gtoxLoadData(lvl = 4L, fld = c("spid", "aeid"), 
                            val = list(spid, aeid))[, m4id]
    gtoxPlotM4ID(m4id = m4id, lvl = 6, bline = "coff")
    apid <- gtoxLoadApid()[u_boxtrack%in%"S-000030318", apid] # plate id
    waids <- gtoxLoadWaid(fld="apid", val=apid)$waid #well ids
    m0ids <- gtoxLoadData(lvl = 0, fld = "waid", val = waids)$m0id # raw data ids
    gtoxSetWllq(ids = m0ids, wllq = 0, type = "mc") # set well quality to zero
    ## Processing report
    gtoxReport(type = "all", asid = asid, report_author = "report author",
    report_title = "Vignette Processing report", odir = outdir)

    # --- Eval=true [] ---
    # Key functions: gtoxLoadAeid, damage, gtoxLoadData, asid, aenm, chromium, gtoxPlotM4ID, coff
    ## Endpoint to plot
    aeids <- gtoxLoadAeid(fld=c("asid", "aenm"),
    val=list(asid, "DNA damage (pH2AX)_DNA damage (pH2AX)_24h_up"),
    add.fld="asid")$aeid
    ## level 4 id to plot
    m4id <- gtoxLoadData(lvl=4L)[(aeid==aeids & grepl("chromium", spid))]$m4id[1]
    gtoxPlotM4ID(m4id = m4id, lvl = 6, bline = "coff")
    chnms <- c("mercury", "o-cresol", "p-cresol")
    glPlotPie(asid, chnms = chnms)
    glPlotToxInd(asid)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gladiatox_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gladiatox_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gladiatox_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GLADIATOX:", paste0("    gladiatox: ", packageVersion("GladiaTOX"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gladiatox_results.csv
    touch ${prefix}_gladiatox_output.rds
    echo "BIOC_GLADIATOX:" > versions.yml
    echo "    gladiatox: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GLADIATOX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GLADIATOX(ch_input)

    emit:
    results  = BIOC_GLADIATOX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GLADIATOX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GLADIATOX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GLADIATOX.out.versions  // channel: path(versions.yml)
}
