# QUICK REFERENCE - VISIBLE Blocked Calls System

## Essential Commands

### Import Data

```bash
# All files
/opt/blocked_calls/import_wrapper.sh

# Single file
python3 /opt/blocked_calls/import_blocked_calls.py --file data.json

# With default destination
python3 /opt/blocked_calls/import_blocked_calls.py --file data.json --called-tn 1-555-123-4567

# Test (dry run)
python3 /opt/blocked_calls/import_blocked_calls.py --file data.json --dry-run
```

---

## Query Data

### Count Records

```bash
# Total records
mysql -u blocked_calls_user -p blocked_calls -e "SELECT COUNT(*) FROM blocked_calls;"

# Unique callers
mysql -u blocked_calls_user -p blocked_calls -e "SELECT COUNT(DISTINCT calling_tn) FROM blocked_calls;"

# Import status
mysql -u blocked_calls_user -p blocked_calls -e "SELECT COUNT(*), import_status FROM import_history GROUP BY import_status;"
```

### View Records

```bash
# Recent calls (last 10)
mysql -u blocked_calls_user -p blocked_calls -e \
  "SELECT calling_tn, called_time FROM blocked_calls ORDER BY called_time DESC LIMIT 10;"

# Top callers (top 10)
mysql -u blocked_calls_user -p blocked_calls -e \
  "SELECT calling_tn, COUNT(*) as count FROM blocked_calls GROUP BY calling_tn ORDER BY count DESC LIMIT 10;"

# By date
mysql -u blocked_calls_user -p blocked_calls -e \
  "SELECT DATE(called_time), COUNT(*) as count FROM blocked_calls GROUP BY DATE(called_time);"

# By hour
mysql -u blocked_calls_user -p blocked_calls -e \
  "SELECT HOUR(called_time), COUNT(*) as count FROM blocked_calls GROUP BY HOUR(called_time);"
```

---

## Check Logs

```bash
# Latest import log
tail -50 /var/log/blocked_calls/import_*.log

# Follow log
tail -f /var/log/blocked_calls/import_*.log

# Cron log
tail -20 /var/log/blocked_calls/cron.log

# Search for errors
grep ERROR /var/log/blocked_calls/import_*.log
```

---

## Configuration

### Edit Configuration

```bash
# Edit .env
sudo nano /opt/blocked_calls/.env

# View .env (without password)
grep -v PASSWORD /opt/blocked_calls/.env

# Set default destination
echo "DEFAULT_CALLED_TN=1-555-123-4567" >> /opt/blocked_calls/.env
```

### Key Settings

```
DB_HOST=localhost
DB_USER=blocked_calls_user
DB_PASSWORD=your_password
DEFAULT_CALLED_TN=1-555-123-4567    # Optional
BATCH_SIZE=1000
LOG_LEVEL=INFO
```

---

## File Management

### View Imports

```bash
# Pending imports
ls -la /opt/blocked_calls/imports/

# Processed files
ls -la /opt/blocked_calls/archives/

# Move file
mv /opt/blocked_calls/imports/file.json /opt/blocked_calls/imports/file.json.backup
```

---

## Database

### Check Connection

```bash
# Test connection
mysql -u blocked_calls_user -p -e "SELECT 1;"

# List tables
mysql -u blocked_calls_user -p blocked_calls -e "SHOW TABLES;"

# Check table size
mysql -u blocked_calls_user -p blocked_calls -e \
  "SELECT table_name, ROUND((data_length + index_length) / 1024 / 1024, 2) as size_mb FROM information_schema.TABLES WHERE table_schema = 'blocked_calls';"
```

### Backup/Restore

```bash
# Backup
mysqldump -u blocked_calls_user -p blocked_calls | gzip > backup_$(date +%Y%m%d).sql.gz

# Restore
gunzip < backup_20251223.sql.gz | mysql -u blocked_calls_user -p blocked_calls

# List backups
ls -lh /backup/blocked_calls/
```

---

## Cron Jobs

### Setup Daily Import (2:00 AM)

```bash
# Add
(crontab -l 2>/dev/null || true; echo "0 2 * * * /opt/blocked_calls/import_wrapper.sh >> /var/log/blocked_calls/cron.log 2>&1") | crontab -

# View
crontab -l | grep import_wrapper

# Remove
crontab -e
# Find and delete the line
```

---

## Troubleshooting

### No Records Found

```bash
# Check file format
python3 -m json.tool /opt/blocked_calls/imports/file.json | head -20

# Check imports directory
ls -la /opt/blocked_calls/imports/

# Check file size
du -h /opt/blocked_calls/imports/file.json
```

### Connection Issues

```bash
# Check MariaDB status
sudo systemctl status mariadb

# Start MariaDB
sudo systemctl start mariadb

# Test connection
mysql -u blocked_calls_user -p blocked_calls -e "SELECT COUNT(*) FROM blocked_calls;"
```

### Permission Issues

```bash
# Fix .env permissions
sudo chmod 600 /opt/blocked_calls/.env

# Fix script permissions
sudo chmod +x /opt/blocked_calls/import_blocked_calls.py
sudo chmod +x /opt/blocked_calls/import_wrapper.sh

# Fix directory permissions
sudo chmod 750 /opt/blocked_calls/imports/
sudo chmod 750 /var/log/blocked_calls/
```

### Low Performance

```bash
# Optimize tables
mysql -u blocked_calls_user -p blocked_calls -e "OPTIMIZE TABLE blocked_calls;"

# Check table
mysql -u blocked_calls_user -p blocked_calls -e "CHECK TABLE blocked_calls;"

# Check disk space
df -h /var/lib/mysql
```

---

## System Health

### Check Status

```bash
# Python environment
source /opt/blocked_calls/venv/bin/activate && python3 --version

# MariaDB
mysql --version

# Disk space
df -h /

# Log directory
du -sh /var/log/blocked_calls/

# Database size
mysql -u blocked_calls_user -p blocked_calls -e \
  "SELECT SUM(data_length + index_length) / 1024 / 1024 as size_mb FROM information_schema.TABLES WHERE table_schema = 'blocked_calls';"
```

### Cleanup

```bash
# Remove old imports (keep last 30 days)
find /opt/blocked_calls/archives -name "*.json" -mtime +30 -delete

# Remove old logs (keep last 60 days)
find /var/log/blocked_calls -name "*.log" -mtime +60 -delete

# Archive old records (keep last 1 year)
mysql -u blocked_calls_user -p blocked_calls << 'SQL'
DELETE FROM blocked_calls WHERE called_time < DATE_SUB(NOW(), INTERVAL 1 YEAR);
SQL
```

---

## Support

### Documentation
- Full guide: `USAGE_GUIDE.md`
- Troubleshooting: `TROUBLESHOOTING.md`
- Deployment: `DEPLOYMENT_GUIDE.md`

### Contact
- Logs: `/var/log/blocked_calls/`
- Config: `/opt/blocked_calls/.env`
- Database: `mysql -u blocked_calls_user -p blocked_calls`

---

## One-Liners

```bash
# Import and report
/opt/blocked_calls/import_wrapper.sh && \
  mysql -u blocked_calls_user -p blocked_calls -e \
  "SELECT COUNT(*) as records, COUNT(DISTINCT calling_tn) as callers FROM blocked_calls;"

# Export top 100 callers to CSV
mysql -u blocked_calls_user -p blocked_calls \
  -e "SELECT calling_tn, COUNT(*) as attempts FROM blocked_calls GROUP BY calling_tn ORDER BY attempts DESC LIMIT 100" \
  --batch > top_callers.csv

# Check disk usage
du -sh /opt/blocked_calls/ /var/log/blocked_calls/ /var/lib/mysql/blocked_calls/

# Find processing errors
grep -i "error\|failed" /var/log/blocked_calls/import_*.log | tail -20

# List last 10 imports
mysql -u blocked_calls_user -p blocked_calls -e \
  "SELECT filename, records_imported, completed_at FROM import_history ORDER BY completed_at DESC LIMIT 10;"
```

---

**For detailed help, see full documentation in USAGE_GUIDE.md or TROUBLESHOOTING.md**

