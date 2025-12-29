#!/bin/bash
# VISIBLE Blocked Calls System - Complete Deployment Guide
# Debian 13 Trixie with MariaDB 11.x
# Version: 3.0

set -e

# ============================================================================
# Colors for output
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is not installed"
        return 1
    fi
    return 0
}

# ============================================================================
# Step 1: Prerequisites Check
# ============================================================================

echo ""
echo "=========================================="
log_info "VISIBLE Blocked Calls - Deployment"
echo "=========================================="
echo ""

log_info "Checking prerequisites..."

# Check OS
if [ ! -f /etc/os-release ]; then
    log_error "Cannot detect OS"
    exit 1
fi

# Check required commands
required_commands=("mysql" "python3" "pip" "sudo" "mkdir" "chmod")
for cmd in "${required_commands[@]}"; do
    if ! check_command "$cmd"; then
        exit 1
    fi
done

log_success "All prerequisites met"
echo ""

# ============================================================================
# Step 2: Directory Setup
# ============================================================================

log_info "Setting up directories..."

BLOCKED_CALLS_DIR="/opt/blocked_calls"
IMPORTS_DIR="$BLOCKED_CALLS_DIR/imports"
ARCHIVES_DIR="$BLOCKED_CALLS_DIR/archives"
LOG_DIR="/var/log/blocked_calls"
BACKUP_DIR="/backup/blocked_calls"

# Create directories
sudo mkdir -p "$BLOCKED_CALLS_DIR"
sudo mkdir -p "$IMPORTS_DIR"
sudo mkdir -p "$ARCHIVES_DIR"
sudo mkdir -p "$LOG_DIR"
sudo mkdir -p "$BACKUP_DIR"

# Set permissions
sudo chmod 755 "$BLOCKED_CALLS_DIR"
sudo chmod 750 "$IMPORTS_DIR"
sudo chmod 750 "$ARCHIVES_DIR"
sudo chmod 750 "$LOG_DIR"
sudo chmod 750 "$BACKUP_DIR"

log_success "Directories created"
echo ""

# ============================================================================
# Step 3: Python Virtual Environment
# ============================================================================

log_info "Setting up Python virtual environment..."

cd "$BLOCKED_CALLS_DIR"

# Create venv if not exists
if [ ! -d "venv" ]; then
    python3 -m venv venv
    log_success "Virtual environment created"
else
    log_warning "Virtual environment already exists"
fi

# Activate and install packages
source venv/bin/activate
pip install --upgrade pip setuptools wheel > /dev/null 2>&1
pip install mysql-connector-python python-dotenv > /dev/null 2>&1

log_success "Python environment configured"
echo ""

# ============================================================================
# Step 4: Database Setup
# ============================================================================

log_info "Setting up database..."

# Check if database exists
DB_EXISTS=$(mysql -u root -p -e "SHOW DATABASES LIKE 'blocked_calls';" 2>/dev/null | grep -c blocked_calls || echo 0)

if [ "$DB_EXISTS" -eq 0 ]; then
    log_warning "Database 'blocked_calls' does not exist"
    log_info "Creating database..."
    
    read -p "Enter MySQL root password: " -s ROOT_PASS
    echo ""
    
    mysql -u root -p"$ROOT_PASS" << EOF
CREATE DATABASE blocked_calls CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'blocked_calls_user'@'localhost' IDENTIFIED BY 'change_this_password';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP ON blocked_calls.* TO 'blocked_calls_user'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    log_success "Database and user created"
else
    log_info "Database 'blocked_calls' already exists"
fi

echo ""

# ============================================================================
# Step 5: Configuration
# ============================================================================

log_info "Creating configuration file..."

if [ ! -f "$BLOCKED_CALLS_DIR/.env" ]; then
    echo "Configuring database connection..."
    read -p "Database host [localhost]: " db_host
    db_host=${db_host:-localhost}
    
    read -p "Database port [3306]: " db_port
    db_port=${db_port:-3306}
    
    read -p "Database user [blocked_calls_user]: " db_user
    db_user=${db_user:-blocked_calls_user}
    
    read -sp "Database password: " db_pass
    echo ""
    
    read -p "Default called_tn (your phone number) [leave blank]: " called_tn
    
    # Create .env file
    sudo tee "$BLOCKED_CALLS_DIR/.env" > /dev/null << EOF
# Database Configuration
DB_HOST=$db_host
DB_PORT=$db_port
DB_USER=$db_user
DB_PASSWORD=$db_pass
DB_NAME=blocked_calls

# Import Settings
BATCH_SIZE=1000
IMPORT_DIR=$IMPORTS_DIR
ARCHIVE_DIR=$ARCHIVES_DIR
LOG_DIR=$LOG_DIR
LOG_LEVEL=INFO

# Optional: Default destination number
DEFAULT_CALLED_TN=${called_tn:-}

# Dry Run (testing only)
DRY_RUN=false
EOF
    
    # Protect .env file
    sudo chmod 600 "$BLOCKED_CALLS_DIR/.env"
    log_success "Configuration file created"
else
    log_warning "Configuration file already exists"
    log_info "Review/update: $BLOCKED_CALLS_DIR/.env"
fi

echo ""

# ============================================================================
# Step 6: Database Schema
# ============================================================================

log_info "Creating database schema..."

read -sp "Database password: " db_pass
echo ""

mysql -u blocked_calls_user -p"$db_pass" blocked_calls << 'SCHEMA'
-- Main blocked calls table
CREATE TABLE IF NOT EXISTS blocked_calls (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    calling_tn VARCHAR(20) NOT NULL,
    called_tn VARCHAR(20),
    called_time DATETIME NOT NULL,
    call_type VARCHAR(50) DEFAULT 'BLOCK',
    duration INT DEFAULT 0,
    recording_available BOOLEAN DEFAULT FALSE,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    KEY idx_calling_tn (calling_tn),
    KEY idx_called_tn (called_tn),
    KEY idx_called_time (called_time),
    KEY idx_call_type (call_type),
    KEY idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Caller information (enrichment)
CREATE TABLE IF NOT EXISTS caller_information (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    calling_tn VARCHAR(20) NOT NULL UNIQUE,
    business_name VARCHAR(255),
    threat_level ENUM('LOW', 'MEDIUM', 'HIGH') DEFAULT 'LOW',
    notes TEXT,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    KEY idx_threat_level (threat_level)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Call notes for tracking incidents
CREATE TABLE IF NOT EXISTS call_notes (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    call_id BIGINT UNSIGNED,
    calling_tn VARCHAR(20),
    note_type ENUM('SCAM', 'SPAM', 'HARASSMENT', 'LEGITIMATE', 'OTHER') DEFAULT 'OTHER',
    note_text TEXT,
    created_by VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    KEY idx_call_id (call_id),
    KEY idx_calling_tn (calling_tn),
    KEY idx_note_type (note_type),
    KEY idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Import history tracking
CREATE TABLE IF NOT EXISTS import_history (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    filename VARCHAR(255) NOT NULL,
    file_size BIGINT,
    records_imported INT DEFAULT 0,
    records_failed INT DEFAULT 0,
    import_status ENUM('SUCCESS', 'PARTIAL', 'FAILED') DEFAULT 'PENDING',
    import_duration INT,
    error_message TEXT,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP NULL,
    
    KEY idx_filename (filename),
    KEY idx_status (import_status),
    KEY idx_completed_at (completed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
SCHEMA

log_success "Database schema created"
echo ""

# ============================================================================
# Step 7: Copy Scripts
# ============================================================================

log_info "Copying scripts..."

if [ -f "import_blocked_calls_v3.py" ]; then
    sudo cp import_blocked_calls_v3.py "$BLOCKED_CALLS_DIR/import_blocked_calls.py"
    sudo chmod +x "$BLOCKED_CALLS_DIR/import_blocked_calls.py"
    log_success "Import script installed"
else
    log_error "import_blocked_calls_v3.py not found in current directory"
fi

if [ -f "import_wrapper.sh" ]; then
    sudo cp import_wrapper.sh "$BLOCKED_CALLS_DIR/"
    sudo chmod +x "$BLOCKED_CALLS_DIR/import_wrapper.sh"
    log_success "Wrapper script installed"
else
    log_error "import_wrapper.sh not found in current directory"
fi

echo ""

# ============================================================================
# Step 8: Testing
# ============================================================================

log_info "Testing configuration..."

cd "$BLOCKED_CALLS_DIR"
source venv/bin/activate

# Test database connection
python3 << PYTEST
import mysql.connector
from dotenv import load_dotenv
import os

load_dotenv()

try:
    conn = mysql.connector.connect(
        host=os.getenv('DB_HOST'),
        user=os.getenv('DB_USER'),
        password=os.getenv('DB_PASSWORD'),
        database=os.getenv('DB_NAME')
    )
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM blocked_calls")
    count = cursor.fetchone()[0]
    print(f"✓ Database connection successful")
    print(f"✓ blocked_calls table has {count} records")
    cursor.close()
    conn.close()
except Exception as e:
    print(f"✗ Database connection failed: {e}")
    exit(1)
PYTEST

log_success "Configuration test passed"
echo ""

# ============================================================================
# Step 9: Cron Setup
# ============================================================================

log_info "Setting up cron job..."

read -p "Schedule daily import at 2:00 AM? (y/n) [y]: " cron_setup
cron_setup=${cron_setup:-y}

if [ "$cron_setup" = "y" ]; then
    cron_job="0 2 * * * $BLOCKED_CALLS_DIR/import_wrapper.sh >> $LOG_DIR/cron.log 2>&1"
    
    # Check if already exists
    if crontab -l 2>/dev/null | grep -q "import_wrapper.sh"; then
        log_warning "Cron job already exists"
    else
        (crontab -l 2>/dev/null || true; echo "$cron_job") | crontab -
        log_success "Cron job scheduled for daily 2:00 AM"
    fi
else
    log_info "Cron job skipped"
fi

echo ""

# ============================================================================
# Step 10: Completion
# ============================================================================

echo "=========================================="
log_success "Deployment Complete!"
echo "=========================================="
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "1. Copy your JSON files to: $IMPORTS_DIR"
echo "2. Run a test import:"
echo "   $BLOCKED_CALLS_DIR/import_wrapper.sh"
echo "3. Check the logs:"
echo "   tail -f $LOG_DIR/import_*.log"
echo "4. Query your data:"
echo "   mysql -u blocked_calls_user -p blocked_calls"
echo "   SELECT COUNT(*) FROM blocked_calls;"
echo ""
echo -e "${YELLOW}Important Files:${NC}"
echo "- Configuration: $BLOCKED_CALLS_DIR/.env"
echo "- Import script: $BLOCKED_CALLS_DIR/import_blocked_calls.py"
echo "- Wrapper script: $BLOCKED_CALLS_DIR/import_wrapper.sh"
echo "- Log directory: $LOG_DIR"
echo ""
echo -e "${YELLOW}Documentation:${NC}"
echo "- Usage guide: see USAGE_GUIDE.md"
echo "- Quick reference: see QUICK_REFERENCE.md"
echo "- Troubleshooting: see TROUBLESHOOTING.md"
echo ""

