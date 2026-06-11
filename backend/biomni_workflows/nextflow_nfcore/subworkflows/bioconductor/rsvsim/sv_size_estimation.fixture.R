library(RSVSim)

svSizes <- c(10, 20, 30, 40, 60, 80, 100, 150, 200, 250, 300, 400, 500, 750, 1000)
write.table(svSizes, file = "real_sv_sizes.txt", row.names = FALSE, col.names = FALSE, quote = FALSE)