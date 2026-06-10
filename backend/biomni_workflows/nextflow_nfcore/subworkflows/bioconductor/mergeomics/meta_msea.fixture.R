library(Mergeomics)

env <- new.env()
try(data("msea_job1", package="Mergeomics", envir=env), silent=TRUE)
try(data("msea_job2", package="Mergeomics", envir=env), silent=TRUE)
try(data("msea_job3", package="Mergeomics", envir=env), silent=TRUE)

# Save job.msea1
if ("msea_job1" %in% ls(env)) {
    saveRDS(env$msea_job1, "job.msea1")
} else if ("job.msea1" %in% ls(env)) {
    saveRDS(env$job.msea1, "job.msea1")
} else {
    job.msea <- list()
    job.msea$label <- "hdlc"
    job.msea$folder <- "Results"
    job.msea$genfile <- system.file("extdata", "genes.hdlc_040kb_ld70.human_eliminated.txt", package="Mergeomics")
    job.msea$marfile <- system.file("extdata", "marker.hdlc_040kb_ld70.human_eliminated.txt", package="Mergeomics")
    job.msea$modfile <- system.file("extdata", "modules.mousecoexpr.liver.human.txt", package="Mergeomics")
    job.msea$inffile <- system.file("extdata", "coexpr.info.txt", package="Mergeomics")
    job.msea$nperm <- 10
    
    job.msea <- ssea.start(job.msea)
    job.msea <- ssea.prepare(job.msea)
    job.msea <- ssea.control(job.msea)
    job.msea <- ssea.analyze(job.msea)
    job.msea <- ssea.finish(job.msea)
    
    saveRDS(job.msea, "job.msea1")
}

# Save job.msea2
if ("msea_job2" %in% ls(env)) {
    saveRDS(env$msea_job2, "job.msea2")
} else if ("job.msea2" %in% ls(env)) {
    saveRDS(env$job.msea2, "job.msea2")
} else {
    saveRDS(readRDS("job.msea1"), "job.msea2")
}

# Save job.msea3
if ("msea_job3" %in% ls(env)) {
    saveRDS(env$msea_job3, "job.msea3")
} else if ("job.msea3" %in% ls(env)) {
    saveRDS(env$job.msea3, "job.msea3")
} else {
    saveRDS(readRDS("job.msea1"), "job.msea3")
}