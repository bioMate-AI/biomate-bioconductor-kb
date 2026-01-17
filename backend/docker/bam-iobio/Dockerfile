# BioMate BAM iobio Interactive Tool
# Real-time BAM file visualization
#
# Uses iobio backend services

FROM node:18-slim

LABEL maintainer="BioMate Team"
LABEL version="1.0"
LABEL description="BAM iobio for Galaxy Interactive Tools"

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    samtools \
    nginx \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone bam.iobio (or use pre-built)
RUN npm install -g http-server

# Create simple redirect page to iobio.io with data
COPY index.html /app/public/
COPY startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup.sh

EXPOSE 8080

CMD ["/usr/local/bin/startup.sh"]
