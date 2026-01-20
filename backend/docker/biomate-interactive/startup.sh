#!/bin/bash
# BioMate Interactive Tools - Comprehensive Startup Script
# Detects data types and enables appropriate tools

echo "=== BioMate Interactive Tools ==="
echo "Starting all services..."

# Create necessary directories
mkdir -p /var/log/supervisor /var/log/nginx /var/www/html/hub
mkdir -p /home/rstudio/shared /import /export /data/openrefine

# Link data directories
ln -sf /import /home/rstudio/data 2>/dev/null || true
ln -sf /export /home/rstudio/output 2>/dev/null || true

# ============================================
# Detect data files for on-demand tools
# ============================================

# CellxGene - h5ad files
H5AD_FILE=$(find /import -name "*.h5ad" -type f 2>/dev/null | head -1)
if [ -n "$H5AD_FILE" ]; then
    echo "Found h5ad file: $H5AD_FILE - enabling CellxGene"
    CELLXGENE_ENABLED=1
    CELLXGENE_FILE="$H5AD_FILE"
fi

# Pavian - Kraken/Bracken reports
KRAKEN_FILES=$(find /import \( -name "*.kreport*" -o -name "*kraken*" -o -name "*bracken*" \) -type f 2>/dev/null | head -1)
if [ -n "$KRAKEN_FILES" ]; then
    echo "Found Kraken reports - enabling Pavian"
    PAVIAN_ENABLED=1
fi

# HiGlass - cooler/mcool files
COOLER_FILE=$(find /import \( -name "*.cool" -o -name "*.mcool" \) -type f 2>/dev/null | head -1)
if [ -n "$COOLER_FILE" ]; then
    echo "Found cooler file: $COOLER_FILE - enabling HiGlass"
    HIGLASS_ENABLED=1
    HIGLASS_FILE="$COOLER_FILE"
fi

# iSEE - RDS files (SummarizedExperiment)
RDS_FILE=$(find /import -name "*.rds" -o -name "*.RDS" -type f 2>/dev/null | head -1)
if [ -n "$RDS_FILE" ]; then
    echo "Found RDS file: $RDS_FILE - enabling iSEE"
    ISEE_ENABLED=1
    ISEE_FILE="$RDS_FILE"
fi

# OpenRefine - CSV/TSV/JSON files
DATA_FILES=$(find /import \( -name "*.csv" -o -name "*.tsv" -o -name "*.json" \) -type f 2>/dev/null | head -1)
if [ -n "$DATA_FILES" ]; then
    echo "Found data files - OpenRefine available"
    OPENREFINE_ENABLED=1
fi

# EtherCalc - always available for spreadsheet work
ETHERCALC_ENABLED=1

# ============================================
# Build supervisor configuration
# ============================================
cat > /etc/supervisor/conf.d/supervisord.conf << 'BASEEOF'
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid
user=root

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
stdout_logfile=/var/log/nginx.log
stderr_logfile=/var/log/nginx.err

[program:jupyter]
command=/usr/local/bin/jupyter lab --config=/root/.jupyter/jupyter_notebook_config.py --allow-root
directory=/home/rstudio
autostart=true
autorestart=true
stdout_logfile=/var/log/jupyter.log
stderr_logfile=/var/log/jupyter.err

[program:rstudio]
command=/usr/lib/rstudio-server/bin/rserver --server-daemonize=0 --server-user=root
autostart=true
autorestart=true
stdout_logfile=/var/log/rstudio.log
stderr_logfile=/var/log/rstudio.err
BASEEOF

# Add CellxGene if h5ad files found
if [ "$CELLXGENE_ENABLED" = "1" ]; then
    cat >> /etc/supervisor/conf.d/supervisord.conf << EOF

[program:cellxgene]
command=/usr/local/bin/cellxgene launch $CELLXGENE_FILE --host 127.0.0.1 --port 5005 --disable-annotations
directory=/import
autostart=true
autorestart=true
stdout_logfile=/var/log/cellxgene.log
stderr_logfile=/var/log/cellxgene.err
EOF
fi

# Add Pavian if kraken reports found
if [ "$PAVIAN_ENABLED" = "1" ]; then
    cat >> /etc/supervisor/conf.d/supervisord.conf << 'EOF'

[program:shiny]
command=/usr/local/bin/R -e "pavian::runApp(host='127.0.0.1', port=3838, server_dir='/import')"
directory=/import
autostart=true
autorestart=true
stdout_logfile=/var/log/pavian.log
stderr_logfile=/var/log/pavian.err
EOF
fi

# Add OpenRefine if data files found
if [ "$OPENREFINE_ENABLED" = "1" ] && [ -f /opt/openrefine/refine ]; then
    cat >> /etc/supervisor/conf.d/supervisord.conf << 'EOF'

[program:openrefine]
command=/opt/openrefine/refine -i 127.0.0.1 -p 3333 -d /data/openrefine
directory=/opt/openrefine
autostart=true
autorestart=true
stdout_logfile=/var/log/openrefine.log
stderr_logfile=/var/log/openrefine.err
EOF
fi

# Add EtherCalc if available
if [ "$ETHERCALC_ENABLED" = "1" ] && command -v ethercalc &> /dev/null; then
    cat >> /etc/supervisor/conf.d/supervisord.conf << 'EOF'

[program:ethercalc]
command=/usr/bin/ethercalc --host 127.0.0.1 --port 8000
autostart=true
autorestart=true
stdout_logfile=/var/log/ethercalc.log
stderr_logfile=/var/log/ethercalc.err
EOF
fi

# Add HiGlass if cooler files found
if [ "$HIGLASS_ENABLED" = "1" ]; then
    cat >> /etc/supervisor/conf.d/supervisord.conf << 'EOF'

[program:higlass]
command=/usr/bin/python3 -m higlass.server --host 127.0.0.1 --port 8989
directory=/import
autostart=true
autorestart=true
stdout_logfile=/var/log/higlass.log
stderr_logfile=/var/log/higlass.err
EOF
fi

# Add iSEE if RDS files found
if [ "$ISEE_ENABLED" = "1" ]; then
    cat >> /etc/supervisor/conf.d/supervisord.conf << EOF

[program:isee]
command=/usr/local/bin/R -e "library(iSEE); sce <- readRDS('$ISEE_FILE'); iSEE(sce, appTitle='iSEE', host='127.0.0.1', port=7777)"
directory=/import
autostart=true
autorestart=true
stdout_logfile=/var/log/isee.log
stderr_logfile=/var/log/isee.err
EOF
fi

# ============================================
# Generate Hub Landing Page
# ============================================

# Status indicators
CELLXGENE_STATUS="disabled"
CELLXGENE_CLASS="disabled"
CELLXGENE_DESC="No .h5ad file found"
if [ "$CELLXGENE_ENABLED" = "1" ]; then
    CELLXGENE_STATUS="enabled"
    CELLXGENE_CLASS="enabled"
    CELLXGENE_DESC="Visualizing: $(basename $CELLXGENE_FILE)"
fi

PAVIAN_STATUS="disabled"
PAVIAN_CLASS="disabled"
PAVIAN_DESC="No kraken reports found"
if [ "$PAVIAN_ENABLED" = "1" ]; then
    PAVIAN_STATUS="enabled"
    PAVIAN_CLASS="enabled"
    PAVIAN_DESC="Metagenomics reports ready"
fi

OPENREFINE_STATUS="disabled"
OPENREFINE_CLASS="disabled"
OPENREFINE_DESC="No data files found"
if [ "$OPENREFINE_ENABLED" = "1" ] && [ -f /opt/openrefine/refine ]; then
    OPENREFINE_STATUS="enabled"
    OPENREFINE_CLASS="enabled"
    OPENREFINE_DESC="Data cleaning ready"
fi

ETHERCALC_STATUS="disabled"
ETHERCALC_CLASS="disabled"
ETHERCALC_DESC="Not installed"
if command -v ethercalc &> /dev/null; then
    ETHERCALC_STATUS="enabled"
    ETHERCALC_CLASS="enabled"
    ETHERCALC_DESC="Collaborative spreadsheet"
fi

HIGLASS_STATUS="disabled"
HIGLASS_CLASS="disabled"
HIGLASS_DESC="No .cool/.mcool files found"
if [ "$HIGLASS_ENABLED" = "1" ]; then
    HIGLASS_STATUS="enabled"
    HIGLASS_CLASS="enabled"
    HIGLASS_DESC="Visualizing: $(basename $HIGLASS_FILE)"
fi

ISEE_STATUS="disabled"
ISEE_CLASS="disabled"
ISEE_DESC="No .rds files found"
if [ "$ISEE_ENABLED" = "1" ]; then
    ISEE_STATUS="enabled"
    ISEE_CLASS="enabled"
    ISEE_DESC="Exploring: $(basename $ISEE_FILE)"
fi

cat > /var/www/html/hub/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BioMate Interactive Tools Hub</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            color: #fff;
            padding: 40px 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 {
            text-align: center;
            font-size: 2.5rem;
            margin-bottom: 10px;
            background: linear-gradient(90deg, #00d9ff, #00ff88);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .subtitle { text-align: center; color: #888; margin-bottom: 40px; }
        .category { margin-bottom: 40px; }
        .category h2 {
            font-size: 1.2rem;
            color: #00d9ff;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 1px solid #333;
        }
        .tools { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 20px; }
        .tool {
            background: rgba(255,255,255,0.05);
            border-radius: 12px;
            padding: 20px;
            text-decoration: none;
            color: #fff;
            transition: all 0.3s ease;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .tool:hover { transform: translateY(-5px); background: rgba(255,255,255,0.1); }
        .tool.disabled { opacity: 0.5; pointer-events: none; }
        .tool h3 { font-size: 1.3rem; margin-bottom: 8px; }
        .tool p { color: #aaa; font-size: 0.9rem; }
        .tool .status {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 20px;
            font-size: 0.75rem;
            margin-top: 10px;
        }
        .tool.enabled .status { background: rgba(0,255,136,0.2); color: #00ff88; }
        .tool.disabled .status { background: rgba(255,100,100,0.2); color: #ff6464; }
        .always-on .status { background: rgba(0,217,255,0.2); color: #00d9ff; }
        .data-link { text-align: center; margin-top: 30px; }
        .data-link a {
            color: #00d9ff;
            text-decoration: none;
            padding: 10px 20px;
            border: 1px solid #00d9ff;
            border-radius: 8px;
            display: inline-block;
            margin: 5px;
        }
        .data-link a:hover { background: rgba(0,217,255,0.1); }
    </style>
</head>
<body>
    <div class="container">
        <h1>BioMate Interactive Tools</h1>
        <p class="subtitle">All-in-one bioinformatics analysis environment</p>

        <div class="category">
            <h2>Notebooks & IDEs (Always Available)</h2>
            <div class="tools">
                <a href="/jupyter" class="tool always-on enabled">
                    <h3>JupyterLab</h3>
                    <p>Python/R notebooks with scanpy, DESeq2, and more</p>
                    <span class="status">Running</span>
                </a>
                <a href="/rstudio/" class="tool always-on enabled">
                    <h3>RStudio Server</h3>
                    <p>R IDE with Bioconductor packages</p>
                    <span class="status">Running</span>
                </a>
            </div>
        </div>

        <div class="category">
            <h2>Single-Cell & Genomics Visualization</h2>
            <div class="tools">
                <a href="/cellxgene/" class="tool $CELLXGENE_CLASS">
                    <h3>CellxGene</h3>
                    <p>$CELLXGENE_DESC</p>
                    <span class="status">$CELLXGENE_STATUS</span>
                </a>
                <a href="/isee/" class="tool $ISEE_CLASS">
                    <h3>iSEE</h3>
                    <p>$ISEE_DESC</p>
                    <span class="status">$ISEE_STATUS</span>
                </a>
                <a href="/higlass/" class="tool $HIGLASS_CLASS">
                    <h3>HiGlass</h3>
                    <p>$HIGLASS_DESC</p>
                    <span class="status">$HIGLASS_STATUS</span>
                </a>
            </div>
        </div>

        <div class="category">
            <h2>Metagenomics</h2>
            <div class="tools">
                <a href="/shiny/" class="tool $PAVIAN_CLASS">
                    <h3>Pavian</h3>
                    <p>$PAVIAN_DESC</p>
                    <span class="status">$PAVIAN_STATUS</span>
                </a>
            </div>
        </div>

        <div class="category">
            <h2>Data Wrangling</h2>
            <div class="tools">
                <a href="/openrefine/" class="tool $OPENREFINE_CLASS">
                    <h3>OpenRefine</h3>
                    <p>$OPENREFINE_DESC</p>
                    <span class="status">$OPENREFINE_STATUS</span>
                </a>
                <a href="/ethercalc/" class="tool $ETHERCALC_CLASS">
                    <h3>EtherCalc</h3>
                    <p>$ETHERCALC_DESC</p>
                    <span class="status">$ETHERCALC_STATUS</span>
                </a>
            </div>
        </div>

        <div class="data-link">
            <a href="/data/">Browse Data Files (/import)</a>
            <a href="/export/">Browse Outputs (/export)</a>
        </div>
    </div>
</body>
</html>
EOF

# ============================================
# Print access information
# ============================================
echo ""
echo "Access the tools at:"
echo "  Hub:         http://localhost:80/"
echo "  Jupyter:     http://localhost:80/jupyter"
echo "  RStudio:     http://localhost:80/rstudio/"
[ "$CELLXGENE_ENABLED" = "1" ] && echo "  CellxGene:   http://localhost:80/cellxgene/"
[ "$PAVIAN_ENABLED" = "1" ] && echo "  Pavian:      http://localhost:80/shiny/"
[ "$OPENREFINE_ENABLED" = "1" ] && [ -f /opt/openrefine/refine ] && echo "  OpenRefine:  http://localhost:80/openrefine/"
command -v ethercalc &> /dev/null && echo "  EtherCalc:   http://localhost:80/ethercalc/"
[ "$HIGLASS_ENABLED" = "1" ] && echo "  HiGlass:     http://localhost:80/higlass/"
[ "$ISEE_ENABLED" = "1" ] && echo "  iSEE:        http://localhost:80/isee/"
echo "  Data:        http://localhost:80/data/"
echo ""

# Start supervisor
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
