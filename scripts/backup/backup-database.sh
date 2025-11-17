#!/bin/bash
# BioMate Database Backup Script
# SOC 2 CC7.3, HIPAA §164.308(a)(7)(ii)(A)
# Version: 1.0
# Date: 2025-11-11

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_DIR:-/tmp/biomate_backups}"
LOG_FILE="${LOG_FILE:-/var/log/biomate/backup.log}"

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
    send_alert "Backup Failed" "$1"
    exit 1
}

# Send alert notification
send_alert() {
    local subject="$1"
    local message="$2"

    # Send to monitoring endpoint
    if [ -n "${ALERT_WEBHOOK_URL:-}" ]; then
        curl -X POST "$ALERT_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"subject\":\"$subject\",\"message\":\"$message\",\"timestamp\":\"$(date -Iseconds)\"}" \
            || log "Failed to send alert"
    fi
}

# Parse database URL
parse_db_url() {
    # Extract components from postgresql://user:pass@host:port/dbname
    DB_USER=$(echo "$DATABASE_URL" | sed -n 's/.*:\/\/\([^:]*\):.*/\1/p')
    DB_PASS=$(echo "$DATABASE_URL" | sed -n 's/.*:\/\/[^:]*:\([^@]*\)@.*/\1/p')
    DB_HOST=$(echo "$DATABASE_URL" | sed -n 's/.*@\([^:]*\):.*/\1/p')
    DB_PORT=$(echo "$DATABASE_URL" | sed -n 's/.*:\([0-9]*\)\/.*/\1/p')
    DB_NAME=$(echo "$DATABASE_URL" | sed -n 's/.*\/\([^?]*\).*/\1/p')
}

# Create backup directory
create_backup_dir() {
    log "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR" || error_exit "Failed to create backup directory"
}

# Backup PostgreSQL database
backup_database() {
    log "Starting database backup for: $DB_NAME"

    local backup_file="$BACKUP_DIR/database_${BACKUP_DATE}.sql"

    # Set password for pg_dump
    export PGPASSWORD="$DB_PASS"

    # Create compressed backup
    pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        --format=custom \
        --compress=9 \
        --verbose \
        --file="$backup_file" \
        2>&1 | tee -a "$LOG_FILE" || error_exit "pg_dump failed"

    unset PGPASSWORD

    # Verify backup file exists and is not empty
    if [ ! -s "$backup_file" ]; then
        error_exit "Backup file is empty or does not exist"
    fi

    local backup_size=$(du -h "$backup_file" | cut -f1)
    log "Database backup completed: $backup_file ($backup_size)"

    echo "$backup_file"
}

# Encrypt backup file
encrypt_backup() {
    local input_file="$1"
    local output_file="${input_file}.enc"

    log "Encrypting backup file..."

    # AES-256-CBC encryption with PBKDF2 key derivation
    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
        -in "$input_file" \
        -out "$output_file" \
        -pass "pass:$ENCRYPTION_KEY" \
        || error_exit "Encryption failed"

    # Verify encrypted file
    if [ ! -s "$output_file" ]; then
        error_exit "Encrypted file is empty or does not exist"
    fi

    # Remove unencrypted backup
    rm -f "$input_file"

    log "Backup encrypted: $output_file"
    echo "$output_file"
}

# Calculate checksum
calculate_checksum() {
    local file="$1"
    local checksum=$(sha256sum "$file" | cut -d' ' -f1)
    echo "$checksum" > "${file}.sha256"
    log "Checksum calculated: $checksum"
    echo "$checksum"
}

# Upload to S3
upload_to_s3() {
    local file="$1"
    local filename=$(basename "$file")
    local s3_path="s3://${S3_BACKUP_BUCKET}/daily/$(date +%Y/%m/%d)/$filename"

    log "Uploading to S3: $s3_path"

    # Upload with server-side encryption
    aws s3 cp "$file" "$s3_path" \
        --region "$AWS_REGION" \
        --server-side-encryption AES256 \
        --storage-class STANDARD_IA \
        --metadata "backup-date=$BACKUP_DATE,retention=30days" \
        || error_exit "S3 upload failed"

    # Upload checksum file
    aws s3 cp "${file}.sha256" "${s3_path}.sha256" \
        --region "$AWS_REGION" \
        --server-side-encryption AES256 \
        || log "Warning: Checksum upload failed"

    log "Upload completed: $s3_path"
}

# Verify backup in S3
verify_s3_backup() {
    local filename="$1"
    local s3_key="daily/$(date +%Y/%m/%d)/$filename"

    log "Verifying S3 backup..."

    # Check if object exists
    aws s3api head-object \
        --bucket "$S3_BACKUP_BUCKET" \
        --key "$s3_key" \
        --region "$AWS_REGION" \
        > /dev/null || error_exit "S3 verification failed"

    log "S3 backup verified successfully"
}

# Cleanup old local backups
cleanup_local() {
    log "Cleaning up local backups..."

    # Remove files older than 1 day
    find "$BACKUP_DIR" -type f -mtime +1 -delete || log "Warning: Cleanup failed"

    log "Local cleanup completed"
}

# Record backup metadata
record_metadata() {
    local backup_file="$1"
    local checksum="$2"

    local metadata_file="$BACKUP_DIR/backup_${BACKUP_DATE}.metadata.json"

    cat > "$metadata_file" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "backup_date": "$BACKUP_DATE",
  "database": "$DB_NAME",
  "backup_file": "$(basename "$backup_file")",
  "checksum": "$checksum",
  "size_bytes": $(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file"),
  "retention_days": 30,
  "s3_path": "s3://${S3_BACKUP_BUCKET}/daily/$(date +%Y/%m/%d)/$(basename "$backup_file")",
  "encryption": "AES-256-CBC",
  "compliance": ["SOC2", "HIPAA"]
}
EOF

    # Upload metadata
    aws s3 cp "$metadata_file" \
        "s3://${S3_BACKUP_BUCKET}/metadata/$(basename "$metadata_file")" \
        --region "$AWS_REGION" \
        --server-side-encryption AES256 \
        || log "Warning: Metadata upload failed"
}

# Send success notification
send_success_notification() {
    local backup_file="$1"
    local size=$(du -h "$backup_file" | cut -f1)

    log "Backup completed successfully"
    send_alert "Backup Success" "Database backup completed: $(basename "$backup_file") ($size)"
}

# Main execution
main() {
    log "=== BioMate Database Backup Started ==="
    log "Backup ID: $BACKUP_DATE"

    # Parse database configuration
    parse_db_url

    # Create backup directory
    create_backup_dir

    # Backup database
    local backup_file=$(backup_database)

    # Encrypt backup
    local encrypted_file=$(encrypt_backup "$backup_file")

    # Calculate checksum
    local checksum=$(calculate_checksum "$encrypted_file")

    # Upload to S3
    upload_to_s3 "$encrypted_file"

    # Verify upload
    verify_s3_backup "$(basename "$encrypted_file")"

    # Record metadata
    record_metadata "$encrypted_file" "$checksum"

    # Cleanup old local backups
    cleanup_local

    # Send success notification
    send_success_notification "$encrypted_file"

    log "=== Backup Completed Successfully ==="
    exit 0
}

# Run main function
main "$@"
