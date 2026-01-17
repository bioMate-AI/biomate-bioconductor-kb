#!/bin/bash
# Galaxy Interactive Tool startup script for RStudio

# Set up data directory symlinks
if [ -d "/import" ]; then
    ln -sf /import /home/rstudio/galaxy_data 2>/dev/null || true
    chown -R rstudio:rstudio /home/rstudio/galaxy_data 2>/dev/null || true
fi

if [ -d "/galaxy/data" ]; then
    ln -sf /galaxy/data /home/rstudio/galaxy_data 2>/dev/null || true
fi

# Galaxy environment for R
cat >> /home/rstudio/.Renviron << EOF
GALAXY_URL=${GALAXY_URL:-}
HISTORY_ID=${HISTORY_ID:-}
API_KEY=${API_KEY:-}
EOF

# Configure RStudio for proxy
if [ -n "$PROXY_PREFIX" ]; then
    echo "www-root-path=$PROXY_PREFIX" >> /etc/rstudio/rserver.conf
fi

# Start RStudio Server
exec /init
