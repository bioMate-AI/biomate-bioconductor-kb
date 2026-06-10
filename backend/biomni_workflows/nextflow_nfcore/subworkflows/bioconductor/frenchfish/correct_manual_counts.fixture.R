library(frenchFISH)
set.seed(366)

manual_counts <- cbind(red = round(runif(20,0,5), 0), 
                       green = round(runif(20,0,5), 0), 
                       blue = round(runif(20,0,5), 0))

write.csv(manual_counts, "manual_counts.csv", row.names = FALSE)