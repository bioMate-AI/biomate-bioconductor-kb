#!/bin/bash
# BioMate Database Restore Script
# SOC 2 CC7.3, HIPAA Disaster Recovery
# Version: 1.0
# Date: 2025-11-11

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESTORE_DIR="${RESTORE_DIR:-/tmp/biomate_restore}"
LOG_FILE="${LOG_FILE:-/var/log/biomate/restore.log}"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env.production" ]; then
    source "$PROJECT_ROOT/.env.production"
fi

# Required environment variables
: "${DATABASE_URL:?DATABASE_URL not set}"
: "${S3_BACKUP_BUCKET:?S3_BACKUP_BUCKET not set}"
: "${ENCRYPTION_KEY:?ENCRYPTION_KEY not set}"
: "${AWS_REGION:=us-west-2}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Parse database URL
parse_db_url() {
    DB_USER=$(echo "$DATABASE_URL" | sed -n 's/.*:\/\/\([^:]*\):.*/\1/p')
    DB_PASS=$(echo "$DATABASE_URL" | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p')
    DB_HOST=$(echo "$DATABASE_URL" | sed -n 's/.*@\([^:]*\):.*/\1/p')
    DB_PORT=$(echo "$DATABASE_URL" | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
    DB_NAME=$(echo "$DATABASE_URL" | sed -n 's/.*\/\([^?]*\).*/\1/p')
}

# List available backups
list_backups() {
    log "Listing available backups from S3..."

    aws s3 ls "s3://${S3_BACKUP_BUCKET}/daily/" \
        --recursive \
        --region "$AWS_REGION" \
        | grep "\.sql\.enc$" \
        | awk '{print $4}' \
        | sort -r \
        | head -20
}

# Download backup from S3
download_backup() {
    local backup_key="$1"
    local local_file="$RESTORE_DIR/$(basename "$backup_key")"

    log "Downloading backup: $backup_key"

    mkdir -p "$RESTORE_DIR"

    aws s3 cp "s3://${S3_BACKUP_BUCKET}/$backup_key" "$local_file" \
        --region "$AWS_REGION" \
        || error_exit "Failed to download backup"

    # Download checksum
    aws s3 cp "s3://${S3_BACKUP_BUCKET}/${backup_key}.sha256" "${local_file}.sha256" \
        --region "$AWS_REGION" \
        || log "Warning: Checksum file not found"

    echo "$local_file"
}

# Verify checksum
verify_checksum() {
    local file="$1"

    if [ ! -f "${file}.sha256" ]; then
        log "Warning: No checksum file found, skipping verification"
        return 0
    fi

    log "Verifying checksum..."

    local expected=$(cat "${file}.sha256")
    local actual=$(sha256sum "$file" | cut -d' ' -f1)

    if [ "$expected" != "$actual" ]; then
        error_exit "Checksum mismatch! Backup may be corrupted."
    fi

    log "Checksum verified successfully"
}

# Decrypt backup
decrypt_backup() {
    local encrypted_file="$1"
    local decrypted_file="${encrypted_file%.enc}"

    log "Decrypting backup..."

    openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 \
        -in "$encrypted_file" \
        -out "$decrypted_file" \
        -pass "pass:$ENCRYPTION_KEY" \
        || error_exit "Decryption failed"

    # Verify decrypted file
    if [ ! -s "$decrypted_file" ]; then
        error_exit "Decrypted file is empty"
    fi

    log "Backup decrypted: $decrypted_file"
    echo "$decrypted_file"
}

# Stop application services
stop_services() {
    log "Stopping application services..."

    # Stop Node.js application
    if systemctl is-active --quiet biomate-frontend; then
        sudo systemctl stop biomate-frontend || log "Warning: Failed to stop frontend"
    fi

    if systemctl is-active --quiet biomate-backend; then
        sudo systemctl stop biomate-backend || log "Warning: Failed to stop backend"
    fi

    log "Services stopped"
}

# Start application services
start_services() {
    log "Starting application services..."

    if systemctl list-unit-files | grep -q biomate-backend; then
        sudo systemctl start biomate-backend || log "Warning: Failed to start backend"
    fi

    if systemctl list-unit-files | grep -q biomate-frontend; then
        sudo systemctl start biomate-frontend || log "Warning: Failed to start frontend"
    fi

    log "Services started"
}

# Create database backup before restore (safety)
backup_current_database() {
    log "Creating safety backup of current database..."

    export PGPASSWORD="$DB_PASS"

    local safety_backup="$RESTORE_DIR/pre_restore_backup_$(date +%Y%m%d_%H%M%S).sql"

    pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        --format=custom \
        --file="$safety_backup" \
        || log "Warning: Safety backup failed"

    unset PGPASSWORD

    log "Safety backup created: $safety_backup"
}

# Restore database
restore_database() {
    local backup_file="$1"
    local restore_mode="${2:-drop_and_restore}"

    log "Restoring database from: $backup_file"
    log "Restore mode: $restore_mode"

    export PGPASSWORD="$DB_PASS"

    case "$restore_mode" in
        drop_and_restore)
            log "Dropping existing database..."

            # Terminate existing connections
            psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c \
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" \
                || log "Warning: Failed to terminate connections"

            # Drop and recreate database
            psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c \
                "DROP DATABASE IF EXISTS $DB_NAME;" \
                || error_exit "Failed to drop database"

            psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c \
                "CREATE DATABASE $DB_NAME OWNER $DB_USER;" \
                || error_exit "Failed to create database"

            log "Database recreated, starting restore..."
            ;;

        clean_restore)
            log "Cleaning database (keeping structure)..."

            psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
                "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" \
                || error_exit "Failed to clean database"
            ;;

        *)
            error_exit "Unknown restore mode: $restore_mode"
            ;;
    esac

    # Restore database using pg_restore
    pg_restore -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        --jobs=4 \
        --verbose \
        "$backup_file" \
        2>&1 | tee -a "$LOG_FILE" || error_exit "Database restore failed"

    unset PGPASSWORD

    log "Database restore completed"
}

# Verify restored database
verify_restore() {
    log "Verifying restored database..."

    export PGPASSWORD="$DB_PASS"

    # Check connection
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" \
        > /dev/null || error_exit "Cannot connect to restored database"

    # Check tables exist
    local table_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")

    log "Tables found: $table_count"

    if [ "$table_count" -lt 1 ]; then
        error_exit "No tables found in restored database"
    fi

    # Check user count (if users table exists)
    local user_count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")

    log "Users found: $user_count"

    unset PGPASSWORD

    log "Database verification completed"
}

# Cleanup restore files
cleanup() {
    log "Cleaning up restore files..."
    rm -rf "$RESTORE_DIR"
    log "Cleanup completed"
}

# Usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Restore BioMate database from S3 backup

OPTIONS:
    -d, --date DATE           Backup date (YYYYMMDD or YYYYMMDD_HHMMSS)
    -l, --list                List available backups
    -k, --key S3_KEY          Restore from specific S3 key
    -m, --mode MODE           Restore mode: drop_and_restore (default) or clean_restore
    -n, --no-services         Don't stop/start services
    -v, --verify-only         Verify backup without restoring
    -h, --help                Show this help

EXAMPLES:
    # List available backups
    $0 --list

    # Restore latest backup
    $0 --date 20251111

    # Restore specific backup by key
    $0 --key daily/2025/11/11/database_20251111_020000.sql.enc

    # Verify backup without restoring
    $0 --date 20251111 --verify-only

EOF
    exit 0
}

# Main execution
main() {
    local backup_key=""
    local backup_date=""
    local list_mode=false
    local verify_only=false
    local manage_services=true
    local restore_mode="drop_and_restore"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--date)
                backup_date="$2"
                shift 2
                ;;
            -k|--key)
                backup_key="$2"
                shift 2
                ;;
            -l|--list)
                list_mode=true
                shift
                ;;
            -m|--mode)
                restore_mode="$2"
                shift 2
                ;;
            -n|--no-services)
                manage_services=false
                shift
                ;;
            -v|--verify-only)
                verify_only=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    log "=== BioMate Database Restore Started ==="

    # List mode
    if [ "$list_mode" = true ]; then
        list_backups
        exit 0
    fi

    # Parse database configuration
    parse_db_url

    # Find backup if not specified by key
    if [ -z "$backup_key" ]; then
        if [ -z "$backup_date" ]; then
            error_exit "Must specify either --date or --key"
        fi

        # Find backup by date
        log "Searching for backup from date: $backup_date"
        backup_key=$(aws s3 ls "s3://${S3_BACKUP_BUCKET}/daily/" --recursive \
            | grep "\.sql\.enc$" \
            | grep "$backup_date" \
            | awk '{print $4}' \
            | head -1)

        if [ -z "$backup_key" ]; then
            error_exit "No backup found for date: $backup_date"
        fi

        log "Found backup: $backup_key"
    fi

    # Download backup
    local encrypted_file=$(download_backup "$backup_key")

    # Verify checksum
    verify_checksum "$encrypted_file"

    # Decrypt backup
    local decrypted_file=$(decrypt_backup "$encrypted_file")

    # Verify-only mode
    if [ "$verify_only" = true ]; then
        log "Backup verification completed successfully"
        cleanup
        exit 0
    fi

    # Confirm restore (interactive)
    if [ -t 0 ]; then
        echo ""
        echo "WARNING: This will restore the database from backup!"
        echo "Database: $DB_NAME"
        echo "Backup: $backup_key"
        echo "Mode: $restore_mode"
        echo ""
        read -p "Continue? (yes/no): " confirm

        if [ "$confirm" != "yes" ]; then
            log "Restore cancelled by user"
            cleanup
            exit 0
        fi
    fi

    # Stop services
    if [ "$manage_services" = true ]; then
        stop_services
    fi

    # Create safety backup
    backup_current_database

    # Restore database
    restore_database "$decrypted_file" "$restore_mode"

    # Verify restore
    verify_restore

    # Start services
    if [ "$manage_services" = true ]; then
        start_services
    fi

    # Cleanup
    cleanup

    log "=== Database Restore Completed Successfully ==="
    exit 0
}

# Run main function
main "$@"
