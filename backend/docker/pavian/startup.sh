#!/bin/bash
# Galaxy Interactive Tool startup for Pavian

# Set data directory
export DATA_DIR="${DATA_DIR:-/import}"
export SHINY_PORT="${SHINY_PORT:-3838}"

# Create symlink for convenience
if [ -d "/import" ]; then
    mkdir -p /home/shiny/data
    ln -sf /import/* /home/shiny/data/ 2>/dev/null || true
fi

# Start Shiny with Pavian
exec R -e "source('/srv/shiny-server/pavian/app.R')"
