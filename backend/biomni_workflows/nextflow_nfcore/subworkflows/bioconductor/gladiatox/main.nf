#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GladiaTOX — hcs_data_processing_and_reporting
// Process raw high-content screening (HCS) data and metadata through database loading, quality control, dose-response fitting, and comprehensive reporting.
// Input: plate_metadata.csv, channel_mapping.csv, raw_instrument_data.csv
// Container: quay.io/biocontainers/bioconductor-gladiatox:1.26.0--r45hdfd78af_0
// R packages: data.table, GladiaTOX
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GLADIATOX_HCS_DATA_PROCESSING_AND_REPORTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-gladiatox:1.26.0--r45hdfd78af_0"

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
    .bm_deps <- c("data.table", "GladiaTOX")
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
    
    library(GladiaTOX)
    library(data.table)
    
    # 1. Configure database connection
    # Copy the package's template sqlite database to the working directory to avoid modifying package files
    sqlite_template <- file.path(find.package("GladiaTOX"), "sql", "gladiatoxdb.sqlite")
    sqlite_src <- file.path(getwd(), "gladiatoxdb.sqlite")
    file.copy(sqlite_template, sqlite_src, overwrite = TRUE)
    
    gtoxConf(   drvr = "SQLite",
                host = NA,
                user = NA,
                pass = NULL,
                db = sqlite_src)
    
    gtoxLoadAsid()
    
    # 2. Build assay table from plate and channel mapping metadata
    # Read user inputs from the working directory
    plate <- fread("plate_metadata.csv")
    chnmap <- fread("channel_mapping.csv")
    dat <- fread("raw_instrument_data.csv")
    
    assay <- buildAssayTab(plate, chnmap)
    
    # 3. Register study info and load annotations into the database
    std.nm <- "SampleStudy" # study name
    phs.nm <- "PhaseII" # study phase
    loadAnnot(plate, assay, NULL)
    
    asid = gtoxLoadAsid(fld = c("asnm", "asph"), val = list(std.nm, phs.nm))\$asid
    
    # 4. Prepare and write raw data to the database
    dat <- prepareDatForDB(asid, dat)
    gtoxWriteData(dat[ , list(acid, waid, wllq, rval)], lvl = 0, type = "mc")
    
    # 5. Assign default processing methods
    assignDefaultMthds(asid = asid)
    
    # 6. Run initial processing (levels 1-3) and compute the noise band (VMAD)
    res <- gtoxRun(asid = asid, slvl = 1, elvl = 3, mc.cores = 2)
    aeids <- gtoxLoadAeid(fld = "asid", val = asid)\$aeid
    tmp <- mapply(function(xx){
        tryCatch(gtoxCalcVmad(inputs = xx, aeid = xx, 
        notes = "computed within study"), 
        error = function(e) NULL)},
        as.integer(aeids))
    
    # 7. Run full processing (levels 1-6)
    res <- gtoxRun(asid = asid, slvl = 1, elvl = 6, mc.cores = 2)
    
    # 8. Generate QC reports and mask low-quality plates
    outdir <- getwd()
    gtoxReport(type = "qc", asid = asid, report_author = "report author",
    report_title = "Vignette QC report", odir = outdir)
    
    acnm <- "DNA damage (pH2AX)_DNA damage (pH2AX)_4h"
    acid <- gtoxLoadAcid(fld=c("asid", "acnm"), val=list(asid,acnm))[, acid]
    apid <- gtoxLoadApid()[u_boxtrack == "S-000031351", apid]
    l2 <- gtoxLoadData(lvl = 2L, fld = "acid", val = acid)
    
    # Save plate plot
    pdf("gtox_plate_plot.pdf", width = 12, height = 8)
    gtoxPlotPlate(dat = l2, apid = apid, id = acid)
    dev.off()
    
    aeid <- gtoxLoadAeid(fld = c("acid", "analysis_direction"), 
                            val = list(acid, "up"))[, aeid]
    spid <- gtoxLoadWaid(fld = c("apid", "wllt"), 
                            val = list(apid, "c"))[,unique(spid)]
    m4id <- gtoxLoadData(lvl = 4L, fld = c("spid", "aeid"), 
                            val = list(spid, aeid))[, m4id]
    
    # Save positive control plot
    pdf("gtox_pos_control_plot.pdf", width = 14, height = 8)
    gtoxPlotM4ID(m4id = m4id, lvl = 6, bline = "coff")
    dev.off()
    
    apid <- gtoxLoadApid()[u_boxtrack%in%"S-000030318", apid] # plate id
    waids <- gtoxLoadWaid(fld="apid", val=apid)\$waid #well ids
    m0ids <- gtoxLoadData(lvl = 0, fld = "waid", val = waids)\$m0id # raw data ids
    gtoxSetWllq(ids = m0ids, wllq = 0, type = "mc") # set well quality to zero
    
    res <- gtoxRun(asid = asid, slvl = 1, elvl = 6, mc.cores = 2)
    
    gtoxReport(type = "all", asid = asid, report_author = "report author",
    report_title = "Vignette Processing report", odir = outdir)
    
    aeids <- gtoxLoadAeid(fld=c("asid", "aenm"),
    val=list(asid, "DNA damage (pH2AX)_DNA damage (pH2AX)_24h_up"),
    add.fld="asid")\$aeid
    m4id <- gtoxLoadData(lvl=4L)[(aeid==aeids & grepl("chromium", spid))]\$m4id[1]
    
    # Save best fit plot
    pdf("gtox_best_fit_plot.pdf", width = 14, height = 8)
    gtoxPlotM4ID(m4id = m4id, lvl = 6, bline = "coff")
    dev.off()
    
    chid <- gtoxLoadChem(field = "chnm", val = "chromium",
    include.spid = FALSE)\$chid
    
    # Save dose-response curves plot
    pdf("gtox_dose_response_curves.pdf", width = 8, height = 5)
    gtoxPlotWin(chid = chid, aeid = aeids, bline = "bmad", collapse = TRUE)
    dev.off()
    
    fname <- paste0(format(Sys.Date(), format="%y%m%d"), "_ASID", asid,"_MEC.pdf")
    fname <- file.path(outdir, fname)
    pdf(fname, width = 11, height = 7)
    glPlotStat(asid)
    dev.off()
    
    chnms <- c("mercury", "o-cresol", "p-cresol")
    
    # Save pie plot
    pdf("gtox_pie_plot.pdf", width = 10, height = 6)
    glPlotPie(asid, chnms = chnms)
    dev.off()
    
    # Save severity score plot
    pdf("gtox_severity_score_plot.pdf", width = 10, height = 6)
    glPlotToxInd(asid)
    dev.off()
    
    # Save final outputs
    fwrite(assay, "assay_table.csv")
    saveRDS(res, "gtox_run_results.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GLADIATOX_HCS_DATA_PROCESSING_AND_REPORTING":
        GladiaTOX: \$(Rscript -e 'cat(as.character(packageVersion("GladiaTOX")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hcs_data_processing_and_reporting.csv versions.yml
    """
}

workflow BIOC_GLADIATOX_HCS_DATA_PROCESSING_AND_REPORTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ plate_metadata.csv, channel_mapping.csv, raw_instrument_data.csv ] ]

    main:
    BIOC_GLADIATOX_HCS_DATA_PROCESSING_AND_REPORTING(ch_input)

    emit:
    tables   = BIOC_GLADIATOX_HCS_DATA_PROCESSING_AND_REPORTING.out.tables
    plots    = BIOC_GLADIATOX_HCS_DATA_PROCESSING_AND_REPORTING.out.plots
    objects  = BIOC_GLADIATOX_HCS_DATA_PROCESSING_AND_REPORTING.out.objects
    versions = BIOC_GLADIATOX_HCS_DATA_PROCESSING_AND_REPORTING.out.versions
}
