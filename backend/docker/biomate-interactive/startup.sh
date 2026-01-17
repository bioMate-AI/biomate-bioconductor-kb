#!/bin/bash
# BioMate Interactive Tools - Unified Startup Script

set -e

echo "=== BioMate Interactive Tools ==="
echo "Starting all services..."

# Create necessary directories
mkdir -p /var/log/supervisor /var/log/nginx /var/www/html/hub
mkdir -p /home/jovyan/shared /import /export

# Set permissions
chown -R jovyan:users /home/jovyan 2>/dev/null || true

# Create hub landing page
cat > /var/www/html/hub/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>BioMate Interactive Tools</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            padding: 40px 20px;
            color: white;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 {
            text-align: center;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .subtitle {
            text-align: center;
            color: #888;
            margin-bottom: 40px;
        }
        .tools {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
        }
        .tool {
            background: rgba(255,255,255,0.1);
            border-radius: 12px;
            padding: 25px;
            text-decoration: none;
            color: white;
            transition: transform 0.2s, background 0.2s;
        }
        .tool:hover {
            transform: translateY(-5px);
            background: rgba(255,255,255,0.15);
        }
        .tool h2 { font-size: 1.4em; margin-bottom: 10px; }
        .tool p { color: #aaa; font-size: 0.9em; line-height: 1.5; }
        .tool .icon { font-size: 2em; margin-bottom: 15px; }
        .jupyter { border-left: 4px solid #F37626; }
        .rstudio { border-left: 4px solid #75AADB; }
        .cellxgene { border-left: 4px solid #2ECC71; }
        .shiny { border-left: 4px solid #E74C3C; }
        .data { border-left: 4px solid #9B59B6; }
        .status {
            margin-top: 40px;
            padding: 20px;
            background: rgba(0,0,0,0.3);
            border-radius: 8px;
        }
        .status h3 { margin-bottom: 15px; }
        .status-item {
            display: flex;
            justify-content: space-between;
            padding: 8px 0;
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }
        .badge {
            padding: 3px 10px;
            border-radius: 12px;
            font-size: 0.8em;
        }
        .badge.running { background: #27ae60; }
        .badge.stopped { background: #7f8c8d; }
    </style>
</head>
<body>
    <div class="container">
        <h1>BioMate Interactive Tools</h1>
        <p class="subtitle">All-in-one bioinformatics analysis environment</p>

        <div class="tools">
            <a href="/jupyter" class="tool jupyter">
                <div class="icon">📓</div>
                <h2>Jupyter Lab</h2>
                <p>Python & R notebooks with scanpy, DESeq2, visualization libraries pre-installed.</p>
            </a>

            <a href="/rstudio/" class="tool rstudio">
                <div class="icon">📊</div>
                <h2>RStudio</h2>
                <p>Full RStudio Server with Bioconductor, ggplot2, tidyverse for R-based analysis.</p>
            </a>

            <a href="/cellxgene" class="tool cellxgene">
                <div class="icon">🔬</div>
                <h2>CellxGene</h2>
                <p>Interactive single-cell data exploration. Load your .h5ad files for visualization.</p>
            </a>

            <a href="/shiny/" class="tool shiny">
                <div class="icon">🦠</div>
                <h2>Pavian</h2>
                <p>Metagenomics visualization. Explore Kraken/Bracken taxonomic results interactively.</p>
            </a>

            <a href="/data/" class="tool data">
                <div class="icon">📁</div>
                <h2>Data Files</h2>
                <p>Browse input files. Use URLs here for external visualization tools like iobio.</p>
            </a>
        </div>

        <div class="status">
            <h3>Service Status</h3>
            <div class="status-item">
                <span>Jupyter Lab</span>
                <span class="badge running">Running on :8888</span>
            </div>
            <div class="status-item">
                <span>RStudio</span>
                <span class="badge running">Running on :8787</span>
            </div>
            <div class="status-item">
                <span>CellxGene</span>
                <span class="badge stopped">On-demand :5005</span>
            </div>
            <div class="status-item">
                <span>Shiny/Pavian</span>
                <span class="badge stopped">On-demand :3838</span>
            </div>
        </div>
    </div>
</body>
</html>
EOF

# Link data directories
if [ -d "/galaxy/data" ]; then
    ln -sf /galaxy/data/* /import/ 2>/dev/null || true
fi

ln -sf /import /home/jovyan/data 2>/dev/null || true
ln -sf /export /home/jovyan/output 2>/dev/null || true

# Check for h5ad files and start CellxGene if found
H5AD_FILE=$(find /import -name "*.h5ad" -type f 2>/dev/null | head -1)
if [ -n "$H5AD_FILE" ]; then
    echo "Found h5ad file: $H5AD_FILE"
    # Update supervisor config with actual file
    sed -i "s|/import/data.h5ad|$H5AD_FILE|g" /etc/supervisor/conf.d/supervisord.conf
    # Enable CellxGene autostart
    sed -i 's/autostart=false/autostart=true/' /etc/supervisor/conf.d/supervisord.conf
fi

# Check for Kraken/Bracken reports and start Pavian
if find /import -name "*.kreport*" -o -name "*kraken*" -o -name "*bracken*" 2>/dev/null | grep -q .; then
    echo "Found metagenomics reports, enabling Pavian"
    # Enable Shiny autostart
    sed -i 's/\[program:shiny\]/[program:shiny]\nautostart=true/' /etc/supervisor/conf.d/supervisord.conf
fi

echo ""
echo "Access the tools at:"
echo "  Hub:       http://localhost:80/"
echo "  Jupyter:   http://localhost:80/jupyter"
echo "  RStudio:   http://localhost:80/rstudio/"
echo "  CellxGene: http://localhost:80/cellxgene"
echo "  Pavian:    http://localhost:80/shiny/"
echo "  Data:      http://localhost:80/data/"
echo ""

# Start supervisor (manages all services)
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
