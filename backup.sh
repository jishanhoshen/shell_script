#!/bin/bash

if [ $# -lt 2 ]; then
    echo "Usage: $0 <domain> <backup_directory>"
    exit 1
fi

DOMAIN=$1
BACKUP_PATH=$2

NGINX_CONFIG_DIR="/etc/nginx/sites-available/$DOMAIN"
NGINX_LOG_DIR="/var/log/nginx/$DOMAIN"
WWW_DIR="/var/www/$DOMAIN"

# Check if MySQL/MariaDB client is available
MYSQL_COMMAND=$(command -v mysql)

if [ -z "$MYSQL_COMMAND" ]; then
    echo "Error: MySQL/MariaDB client not found. Please install it and try again."
    exit 1
fi

# Retrieve database information from ongsho_cloud
DB_INFO=($(sudo mysql -u root_user_for_Nginx_block ongsho_cloud -se "SELECT dbname, username, password FROM users WHERE domain='$DOMAIN';"))

if [ ${#DB_INFO[@]} -eq 0 ]; then
    echo "Error: Database information not found for domain $DOMAIN"
    exit 1
fi

DB_NAME=${DB_INFO[0]}
DB_USER=${DB_INFO[1]}
DB_PASSWORD=${DB_INFO[2]}

# Create a timestamp for the backup directory
TIMESTAMP=$(date +"%Y.%m.%d_%H.%M.%S")
BACKUP_DIR=$DOMAIN"_"$TIMESTAMP

# Create the backup directory
sudo mkdir -p "$BACKUP_PATH/$BACKUP_DIR"
echo "Step 1: Created backup directory $BACKUP_DIR"

# Copy Nginx configuration files
sudo cp -r "$NGINX_CONFIG_DIR" "$BACKUP_PATH/$BACKUP_DIR/nginx_config"
echo "Step 2: Copied Nginx configuration files to $BACKUP_DIR/nginx_config"

# Copy Nginx log files
sudo cp -r "$NGINX_LOG_DIR" "$BACKUP_PATH/$BACKUP_DIR/nginx_logs"
echo "Step 3: Copied Nginx log files to $BACKUP_DIR/nginx_logs"

# Copy the web directory
sudo cp -r "$WWW_DIR" "$BACKUP_PATH/$BACKUP_DIR/www"
echo "Step 4: Copied the web directory to $BACKUP_DIR/www"

# Copy the MySQL database
sudo mysqldump -u root_user_for_Nginx_block "$DB_NAME" > "$BACKUP_PATH/$BACKUP_DIR/$DB_NAME.sql"
echo "Step 5: Backed up MySQL database to $BACKUP_DIR/$DB_NAME.sql"

# copy SSl certificate
sudo cp /etc/letsencrypt/live/$DOMAIN "$BACKUP_PATH/$BACKUP_DIR/ssl"
echo "Step 6: Copied SSL certificate to $BACKUP_DIR/ssl"

# Zip the backup directory
sudo zip -r "$BACKUP_PATH/$BACKUP_DIR.zip" "$BACKUP_PATH/$BACKUP_DIR"
echo "Step 7: Zipped the backup directory to $BACKUP_DIR.zip"

# # Remove the uncompressed backup directory
rm -r "$BACKUP_PATH/$BACKUP_DIR"
echo "Step 8: Removed the uncompressed backup directory"

echo "Backup completed. The backup files are stored in: $BACKUP_DIR.zip"
