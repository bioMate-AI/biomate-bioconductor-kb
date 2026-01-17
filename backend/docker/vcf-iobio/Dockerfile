# BioMate VCF iobio Interactive Tool
# Variant file visualization
#
# Serves VCF files for iobio.io visualization

FROM node:18-slim

LABEL maintainer="BioMate Team"
LABEL version="1.0"
LABEL description="VCF iobio for Galaxy Interactive Tools"

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bcftools \
    tabix \
    nginx \
    curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN npm install -g http-server

COPY index.html /app/public/
COPY startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/startup.sh

EXPOSE 8080

CMD ["/usr/local/bin/startup.sh"]
