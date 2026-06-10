library(deltaGseg)

# Locate the package extdata directory
dir <- system.file("extdata", package="deltaGseg")

# Parse the trajectories as shown in the vignette
traj1 <- parseTraj(path=dir, files=c("D_GBTOT1", "D_GBTOT2", "D_GBTOT3"))

# Transform the series
traj1.tr <- transformSeries(object=traj1, method='splitting', breakpoints=1)

# Extract and manipulate the specific trajectory to create 'y'
x <- getTraj(traj1.tr)[['D_GBTOT3_1']]
y_temp <- x[,2] - 35
y1 <- y_temp[1:2000]
y2 <- y_temp[2001:length(y_temp)] + 17
ss <- c(seq(50, length(y2), 100), length(y2))

for(i in 1:(length(ss)-1)) {
    y2[ss[i]:ss[(i+1)]] <- y2[ss[i]:ss[(i+1)]] + i^1.85
}

y <- cbind(x[,1], c(y1, y2))

# Serialize the matrix object 'y' to the declared input file
saveRDS(y, "y")