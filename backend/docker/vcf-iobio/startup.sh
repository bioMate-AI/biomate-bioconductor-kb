#!/bin/bash
# Galaxy Interactive Tool startup for VCF iobio

mkdir -p /app/public/data

if [ -d "/import" ]; then
    ln -sf /import/* /app/public/data/ 2>/dev/null || true
fi

# Index and generate stats for VCF files
for vcf in /app/public/data/*.vcf /app/public/data/*.vcf.gz; do
    if [ -f "$vcf" ]; then
        # Compress if not already
        if [[ "$vcf" != *.gz ]]; then
            bgzip -c "$vcf" > "${vcf}.gz" 2>/dev/null || true
            vcf="${vcf}.gz"
        fi

        # Index
        if [ ! -f "${vcf}.tbi" ]; then
            echo "Indexing $vcf..."
            tabix -p vcf "$vcf" 2>/dev/null || true
        fi

        # Generate stats
        echo "=== $(basename $vcf) ===" >> /app/public/stats.txt
        bcftools stats "$vcf" 2>/dev/null | grep -E "^SN|^TSTV" >> /app/public/stats.txt || true
        echo "" >> /app/public/stats.txt
    fi
done

cd /app/public
exec http-server -p 8080 --cors
