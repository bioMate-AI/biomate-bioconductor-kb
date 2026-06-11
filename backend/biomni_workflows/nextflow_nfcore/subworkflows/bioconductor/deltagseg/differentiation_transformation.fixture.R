library(deltaGseg)

# Load package data which may contain the pre-computed objects from the vignette
data("deltaGseg", package = "deltaGseg", envir = environment())

# Reconstruct the object if it wasn't loaded by data()
if (!exists("simtraj.tr")) {
    if (!exists("traj1.tr")) {
        if (!exists("traj1")) {
            dir <- system.file("extdata", package="deltaGseg")
            traj1 <- parseTraj(path=dir, files=c("D_GBTOT1", "D_GBTOT2", "D_GBTOT3"))
        }
        traj1.tr <- transformSeries(object=traj1, method='splitting', breakpoints=1)
    }
    
    x <- getTraj(traj1.tr)[['D_GBTOT3_1']]
    y <- x[,2] - 35
    y1 <- y[1:2000]
    y2 <- y[2001:length(y)] + 17
    ss <- c(seq(50, length(y2), 100), length(y2))
    
    for(i in 1:(length(ss)-1)) {
        y2[ss[i]:ss[(i+1)]] <- y2[ss[i]:ss[(i+1)]] + i^1.85
    }
    
    y <- cbind(x[,1], c(y1, y2))
    simtraj <- parseTraj(files=list(y), fromfile=FALSE)
    simtraj.tr <- transformSeries(object=simtraj, method='splitting', breakpoints=1)
}

# Serialize the object to the expected input file
saveRDS(simtraj.tr, "simtraj.tr")