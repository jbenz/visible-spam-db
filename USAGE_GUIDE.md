# USAGE GUIDE - VISIBLE Blocked Calls System

## Overview

The VISIBLE Blocked Calls System imports call blocking data from Visible JSON files into MariaDB for analysis and reporting.

---

## Installation Locations

```
Main directory:        /opt/blocked_calls/
Configuration:         /opt/blocked_calls/.env
Import script:         /opt/blocked_calls/import_blocked_calls.py
Wrapper script:        /opt/blocked_calls/import_wrapper.sh
Data staging:          /opt/blocked_calls/imports/
Processed files:       /opt/blocked_calls/archives/
Application logs:      /var/log/blocked_calls/
Database backups:      /backup/blocked_calls/
```

---

## Basic Usage

### 1. Prepare Your Data

Place Visible JSON files in the imports directory:

```bash
# Copy your JSON file
cp 122325.json /opt/blocked_calls/imports/

# Verify
ls -la /opt/blocked_calls/imports/
```

### 2. Run Import (Simplest)

```bash
# Process all files in imports/
/opt/blocked_calls/import_wrapper.sh

# Check logs
tail -20 /var/log/blocked_calls/import_*.log
```

### 3. Query Results

```bash
# See how many records imported
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT COUNT(*) as total_records FROM blocked_calls;
SQL

# See recent calls
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT calling_tn, called_time, call_type 
FROM blocked_calls 
ORDER BY called_time DESC 
LIMIT 10;
SQL
```

---

## Advanced Usage

### Import with Default Destination

If all calls in your file were to the same number:

```bash
# Using command-line flag
python3 /opt/blocked_calls/import_blocked_calls.py \
  --file /opt/blocked_calls/imports/122325.json \
  --called-tn 1-555-123-4567

# Or set in .env and run wrapper
# Edit: /opt/blocked_calls/.env
# Add: DEFAULT_CALLED_TN=1-555-123-4567
# Then: /opt/blocked_calls/import_wrapper.sh
```

### Test Before Importing (Dry Run)

```bash
# Test without database changes
python3 /opt/blocked_calls/import_blocked_calls.py \
  --file /opt/blocked_calls/imports/122325.json \
  --dry-run

# Check what would be imported
tail -50 /var/log/blocked_calls/import_*.log
```

### Process Multiple Files

```bash
# All files in imports/ directory (recommended)
/opt/blocked_calls/import_wrapper.sh

# Specific file
python3 /opt/blocked_calls/import_blocked_calls.py \
  --file /opt/blocked_calls/imports/file1.json

# Multiple files with different destinations
python3 /opt/blocked_calls/import_blocked_calls.py \
  --file /opt/blocked_calls/imports/calls_to_123.json \
  --called-tn 1-555-123-0123

python3 /opt/blocked_calls/import_blocked_calls.py \
  --file /opt/blocked_calls/imports/calls_to_456.json \
  --called-tn 1-555-123-0456
```

---

## Reporting Queries

### Total and Unique Callers

```bash
# Total records
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT COUNT(*) as total_records FROM blocked_calls;
SQL

# Unique calling numbers
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT COUNT(DISTINCT calling_tn) as unique_callers FROM blocked_calls;
SQL

# Date range
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT 
  MIN(called_time) as first_call,
  MAX(called_time) as latest_call,
  DATEDIFF(MAX(called_time), MIN(called_time)) as days_spanned
FROM blocked_calls;
SQL
```

### Top Offenders

```bash
# Top 20 calling numbers by frequency
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT 
  calling_tn,
  COUNT(*) as call_count,
  MIN(called_time) as first_call,
  MAX(called_time) as latest_call
FROM blocked_calls
GROUP BY calling_tn
ORDER BY call_count DESC
LIMIT 20;
SQL
```

### Time-Based Analysis

```bash
# Calls by hour of day
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT 
  HOUR(called_time) as hour,
  COUNT(*) as call_count
FROM blocked_calls
GROUP BY HOUR(called_time)
ORDER BY hour;
SQL

# Calls by day
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT 
  DATE(called_time) as call_date,
  COUNT(*) as call_count
FROM blocked_calls
GROUP BY DATE(called_time)
ORDER BY call_date DESC;
SQL

# Calls by week
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT 
  YEARWEEK(called_time) as week,
  COUNT(*) as call_count
FROM blocked_calls
GROUP BY YEARWEEK(called_time)
ORDER BY week DESC;
SQL
```

### Import History

```bash
# Recent imports
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT 
  filename,
  records_imported,
  records_failed,
  import_status,
  import_duration,
  completed_at
FROM import_history
ORDER BY completed_at DESC
LIMIT 10;
SQL

# Import statistics
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT 
  COUNT(*) as total_imports,
  SUM(records_imported) as total_records,
  SUM(records_failed) as total_failed,
  AVG(import_duration) as avg_duration
FROM import_history
WHERE import_status = 'SUCCESS';
SQL

# Failed imports
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT 
  filename,
  records_failed,
  error_message,
  completed_at
FROM import_history
WHERE import_status != 'SUCCESS'
ORDER BY completed_at DESC;
SQL
```

---

## Configuration

### .env File Settings

```bash
# Database connection
DB_HOST=localhost              # MySQL server
DB_PORT=3306                  # MySQL port
DB_USER=blocked_calls_user    # Database user
DB_PASSWORD=your_password     # Database password
DB_NAME=blocked_calls         # Database name

# Paths
IMPORT_DIR=/opt/blocked_calls/imports      # Where JSON files go
ARCHIVE_DIR=/opt/blocked_calls/archives    # Where processed files go
LOG_DIR=/var/log/blocked_calls             # Where logs go

# Import settings
BATCH_SIZE=1000               # Records per commit
LOG_LEVEL=INFO               # DEBUG, INFO, WARN, ERROR

# Optional
DEFAULT_CALLED_TN=1-555-123-4567   # Default destination number
DRY_RUN=false                       # Enable to test without changes
```

### Update Configuration

```bash
# Edit configuration
sudo nano /opt/blocked_calls/.env

# Changes take effect on next run
# (no restart needed)
```

---

## Automation

### One-Time Cron Setup

```bash
# Add job for daily 2:00 AM import
(crontab -l 2>/dev/null || true; echo "0 2 * * * /opt/blocked_calls/import_wrapper.sh >> /var/log/blocked_calls/cron.log 2>&1") | crontab -

# Verify
crontab -l | grep import_wrapper
```

### Check Cron Execution

```bash
# View cron logs
tail -20 /var/log/blocked_calls/cron.log

# View system cron logs (Linux)
sudo journalctl -u cron -n 20
sudo grep CRON /var/log/syslog | tail -20
```

---

## Monitoring

### Check Import Logs

```bash
# Latest import
tail -50 /var/log/blocked_calls/import_*.log

# Follow log in real-time
tail -f /var/log/blocked_calls/import_*.log

# Search for errors
grep -i error /var/log/blocked_calls/import_*.log
```

### Database Health

```bash
# Check table sizes
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SELECT 
  table_name,
  ROUND(((data_length + index_length) / 1024 / 1024), 2) as size_mb,
  table_rows as row_count
FROM information_schema.TABLES
WHERE table_schema = 'blocked_calls'
ORDER BY size_mb DESC;
SQL

# Check indexes
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
SHOW INDEXES FROM blocked_calls;
SQL

# Check disk space
df -h /var/lib/mysql
```

---

## Troubleshooting

### No Files to Import

```bash
# Check imports directory
ls -la /opt/blocked_calls/imports/

# Verify JSON format
python3 -m json.tool /opt/blocked_calls/imports/file.json | head -20

# Check permissions
ls -la /opt/blocked_calls/imports/ | grep json
```

### Connection Failed

```bash
# Check MySQL is running
sudo systemctl status mariadb

# Test connection
mysql -u blocked_calls_user -p blocked_calls -e "SELECT 1"

# Check .env credentials
cat /opt/blocked_calls/.env | grep DB_
```

### Import Errors

```bash
# Check latest log
tail -100 /var/log/blocked_calls/import_*.log

# Search for errors
grep ERROR /var/log/blocked_calls/import_*.log

# Check import history
mysql -u blocked_calls_user -p blocked_calls -e \
  "SELECT * FROM import_history WHERE import_status != 'SUCCESS' ORDER BY completed_at DESC LIMIT 5\G"
```

### Performance Issues

```bash
# Check query performance
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
EXPLAIN SELECT COUNT(*) FROM blocked_calls;
EXPLAIN SELECT calling_tn, COUNT(*) FROM blocked_calls GROUP BY calling_tn ORDER BY COUNT(*) DESC LIMIT 20;
SQL

# Optimize tables
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
OPTIMIZE TABLE blocked_calls;
OPTIMIZE TABLE import_history;
SQL
```

---

## Backup and Recovery

### Backup Database

```bash
# Single backup
mysqldump -u blocked_calls_user -p blocked_calls | gzip > /backup/blocked_calls/backup_$(date +%Y%m%d_%H%M%S).sql.gz

# Verify backup
gunzip -t /backup/blocked_calls/backup_*.sql.gz

# Keep last 30 days
find /backup/blocked_calls -name "*.sql.gz" -mtime +30 -delete
```

### Restore from Backup

```bash
# List available backups
ls -lh /backup/blocked_calls/

# Restore specific backup
gunzip < /backup/blocked_calls/backup_20251223_120000.sql.gz | \
  mysql -u blocked_calls_user -p blocked_calls

# Verify restore
mysql -u blocked_calls_user -p blocked_calls -e "SELECT COUNT(*) FROM blocked_calls;"
```

---

## Common Tasks

### Export Data to CSV

```bash
# Export all records
mysql -u blocked_calls_user -p blocked_calls \
  -e "SELECT calling_tn, called_tn, called_time, call_type FROM blocked_calls" \
  --batch --skip-column-names > export.csv

# Export top offenders
mysql -u blocked_calls_user -p blocked_calls \
  -e "SELECT calling_tn, COUNT(*) as count FROM blocked_calls GROUP BY calling_tn ORDER BY count DESC" \
  --batch > top_callers.csv
```

### Add Caller Information

```bash
# Add enrichment data
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
INSERT INTO caller_information (calling_tn, business_name, threat_level, notes)
VALUES ('1-631-803-9893', 'Example Scammer Inc', 'HIGH', 'Known robocall operator');

-- Link to calls
SELECT bc.* FROM blocked_calls bc
JOIN caller_information ci ON bc.calling_tn = ci.calling_tn
WHERE ci.threat_level = 'HIGH';
SQL
```

### Delete Old Records

```bash
# Delete records older than 1 year
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
DELETE FROM blocked_calls 
WHERE called_time < DATE_SUB(NOW(), INTERVAL 1 YEAR);
SQL

# Archive to separate table first (safer)
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
CREATE TABLE blocked_calls_archive_2024 LIKE blocked_calls;
INSERT INTO blocked_calls_archive_2024 
SELECT * FROM blocked_calls 
WHERE called_time < '2025-01-01';
DELETE FROM blocked_calls 
WHERE called_time < '2025-01-01';
SQL
```

---

## Support

For issues, check:
1. Logs: `/var/log/blocked_calls/`
2. Database: `mysql -u blocked_calls_user -p blocked_calls`
3. Configuration: `/opt/blocked_calls/.env`
4. Documentation: This guide and TROUBLESHOOTING.md

