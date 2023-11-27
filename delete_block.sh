#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

DOMAIN=$1

/home/ongsho_dev/script/backup.sh $DOMAIN '/home/ongsho_dev/backup'

# Check if the domain directory already exists
WWW_DIR="/var/www/$DOMAIN"
if [ -d "$WWW_DIR" ]; then
    echo "Deleting directory $WWW_DIR..."
    sudo rm -rf "$WWW_DIR"
    echo "Directory deleted successfully."
fi

# Check if the Nginx configuration files exist
NGINX_AVAILABLE="/etc/nginx/sites-available/$DOMAIN"
NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMAIN"
if [ -e "$NGINX_AVAILABLE" ] && [ -e "$NGINX_ENABLED" ]; then
    echo "Deleting Nginx configuration files..."
    sudo rm "$NGINX_AVAILABLE" "$NGINX_ENABLED"
    echo "Nginx configuration files deleted successfully."
fi

# Check if MySQL/MariaDB client is available
MYSQL_COMMAND=$(command -v mysql)

if [ -z "$MYSQL_COMMAND" ]; then
    echo "Error: MySQL/MariaDB client not found. Please install it and try again."
    exit 1
fi

# Fetch database information from ongsho_cloud.users table
DB_INFO=($(sudo mysql -u root_user_for_Nginx_block ongsho_cloud -se "SELECT dbname, username FROM users WHERE domain='$DOMAIN';"))
DB_NAME=${DB_INFO[0]}
DB_USER=${DB_INFO[1]}

# Check if the database exists
EXISTING_DB=$($MYSQL_COMMAND -sN -e "SHOW DATABASES LIKE '$DB_NAME';")
if [ -n "$EXISTING_DB" ]; then
    echo "Deleting database $DB_NAME..."
    sudo mysql -u root_user_for_Nginx_block -e "DROP DATABASE IF EXISTS $DB_NAME;"
    echo "Database deleted successfully."
fi

# Check if the user exists
EXISTING_USER=$($MYSQL_COMMAND -sN -e "SELECT 1 FROM mysql.user WHERE user='$DB_USER';")
if [ -n "$EXISTING_USER" ]; then
    echo "Deleting MySQL user $DB_USER..."
    sudo mysql -u root_user_for_Nginx_block -e "DROP USER IF EXISTS '$DB_USER'@'%';"
    echo "MySQL user deleted successfully."
fi

# Check if the logs directory exists
LOGS_DIR="/var/log/nginx/$DOMAIN"
if [ -d "$LOGS_DIR" ]; then
    echo "Deleting logs directory $LOGS_DIR..."
    sudo rm -rf "$LOGS_DIR"
    echo "Logs directory deleted successfully."
fi

# Update ongsho_cloud status
echo "Updating ongsho_cloud status..."
sudo mysql -u root_user_for_Nginx_block ongsho_cloud -e "UPDATE users SET status=0 WHERE domain='$DOMAIN';"
echo "ongsho_cloud status updated successfully."

# Test Nginx configuration
sudo nginx -t

# Restart Nginx if the configuration is okay
if [ $? -eq 0 ]; then
    sudo systemctl restart nginx
    echo "Nginx restarted successfully."
else
    echo "Error: Nginx configuration test failed. Please check the configuration and restart Nginx manually."
fi

echo "+-------------------------------------------+"
echo "|            DELETION SUCCESSFUL            |"
echo "+-------------------------------------------+"
echo "| DOMAIN       : $DOMAIN"
echo "| STATUS       : Deleted"
echo "| DATABASE     : $DB_NAME"
echo "| DB USERNAME  : $DB_USER"
echo "| LOGS DELETED : $LOGS_DIR"
echo "+-------------------------------------------+"

(sudo crontab -l | grep -v "/home/ongsho_dev/script/backup.sh $DOMAIN /home/ongsho_dev/backup") | sudo crontab -