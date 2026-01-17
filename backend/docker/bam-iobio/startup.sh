#!/bin/bash
# Galaxy Interactive Tool startup for BAM iobio

# Create symlink to data
mkdir -p /app/public/data
if [ -d "/import" ]; then
    ln -sf /import/* /app/public/data/ 2>/dev/null || true
fi

# Index BAM files if needed
for bam in /app/public/data/*.bam; do
    if [ -f "$bam" ] && [ ! -f "${bam}.bai" ]; then
        echo "Indexing $bam..."
        samtools index "$bam" || true
    fi
done

# Start HTTP server to serve files
cd /app/public
exec http-server -p 8080 --cors
