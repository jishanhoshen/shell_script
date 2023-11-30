#!/bin/bash

# Define colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

if [ $# -lt 1 ]; then
    echo "Usage: $0 <domain> [php_version] [db_user] [db_password] [backup]"
    exit 1
fi


DOMAIN=$1

WWW_DIR="/var/www/$DOMAIN"
NGINX_AVAILABLE="/etc/nginx/sites-available/$DOMAIN"
NGINX_ENABLED="/etc/nginx/sites-enabled/$DOMAIN"

# Check if the domain directory already exists
if [ -d "$WWW_DIR" ]; then
    echo "Error: The directory for domain $DOMAIN already exists. Please choose a different domain name."
    exit 1
fi

# Check if the Nginx configuration files already exist
if [ -e "$NGINX_AVAILABLE" ] || [ -e "$NGINX_ENABLED" ]; then
    echo "Error: Nginx configuration files for domain $DOMAIN already exist. Please choose a different domain name."
    exit 1
fi

# Set default PHP version
DEFAULT_PHP_VERSION="7.4"

# Prompt for PHP version if not provided
if [ -z "$2" ]; then
    echo "+-------------------------------------------+"
    echo -e "|         ${BLUE}Available PHP versions${NC}            |"
    echo "+-------------------------------------------+"

    PHP_VERSIONS=($(ls /etc/php | grep -E '^[0-9]+\.[0-9]+$' | sort -r))
    
    for i in "${!PHP_VERSIONS[@]}"; do
        echo -e "${GREEN}$((i+1))) ${NC}PHP v${PHP_VERSIONS[i]}"
    done
    echo ""

    while true; do
        echo -e "Enter PHP version number (press Enter for the default ${GREEN}PHP v$DEFAULT_PHP_VERSION${NC})"
        read -rp "$ " php_choice

        if [ -z "$php_choice" ]; then
            PHP_VERSION="$DEFAULT_PHP_VERSION"
            break
        elif ! [[ "$php_choice" =~ ^[0-9]+$ ]] || [ "$php_choice" -lt 1 ] || [ "$php_choice" -gt "${#PHP_VERSIONS[@]}" ]; then
            # Set PHP_VERSION based on user input
            PHP_VERSION="${PHP_VERSIONS[php_choice-1]}"
            break
        else
            echo "Invalid input. Please enter a valid number."
        fi
    done

    echo -e "Selected PHP version: ${GREEN}$PHP_VERSION${NC}"
fi


# Prompt for database name
echo ""
echo "Enter database name (press Enter for a random name): "
read -p "$ " USER_DB_NAME

# Set a default random database name if the user doesn't enter one
if [ -z "$USER_DB_NAME" ]; then
    RANDOM_STRING=$(LC_ALL=C tr -dc 'a-z' < /dev/urandom | head -c 8)  # Generate a random string
    USER_DB_NAME="OCloud_${RANDOM_STRING}"  # Prefix + random string
    SSH_USER="ongsho_${RANDOM_STRING}"  # Prefix + random string
fi

# Prompt for database user if not provided
if [ -z "$3" ]; then
    # If the user skips providing a username, set a default username based on the database name
    DB_USER=${USER_DB_NAME}
else
    DB_USER=$3
fi

# Prompt for database password if not provided
if [ -z "$4" ]; then
    echo ""
    echo "Enter database password (press Enter for a random password): "
    read -s -p "$ " DB_PASSWORD

    # Set a default random password if the user doesn't enter one
    if [ -z "$DB_PASSWORD" ]; then
        RANDOM_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 12)  # Generate a random password
        DB_PASSWORD=$RANDOM_PASSWORD
    fi
else
    DB_PASSWORD=$4
fi

# Default backup schedule
SCHEDULE="0 0 * * 0"

# Prompt for backup schedule if not provided
if [ -z "$5" ]; then
    Schedules=("Daily" "Weekly" "Monthly")
    echo ""
    echo ""
    echo "Available backup schedules:"
    for i in "${!Schedules[@]}"; do
        echo -e "${GREEN}$((i+1))) ${NC}${Schedules[i]}"
    done

    echo ""
    echo "Enter backup schedule (press Enter for the default schedule): "
    read -p "$ " Schedule

    if [ -z "$Schedule" ]; then
        echo "Selected default backup schedule: ${Schedules[1]}."
    else
        if [ "$Schedule" -eq 1 ]; then
            SCHEDULE="0 0 * * *"
        elif [ "$Schedule" -eq 2 ]; then
            SCHEDULE="0 0 * * 0"
        elif [ "$Schedule" -eq 3 ]; then
            SCHEDULE="0 0 1 * *"
        fi 
    fi
fi


# Check if MySQL/MariaDB client is available
MYSQL_COMMAND=$(command -v mysql)

if [ -z "$MYSQL_COMMAND" ]; then
    echo "Error: MySQL/MariaDB client not found. Please install it and try again."
    exit 1
fi

# Check if the user-provided or generated database name already exists
EXISTING_DB=$(sudo $MYSQL_COMMAND -sN -e "SHOW DATABASES LIKE '$USER_DB_NAME';")

if [ -n "$EXISTING_DB" ]; then
    echo "Error: Database $USER_DB_NAME already exists. Please choose a different name."
    exit 1
fi

# Create MySQL/MariaDB database and user using root without prompting for password
echo "+-------------------------------------------+"
echo -e "|                  ${BLUE}DATABASE${NC}                 |"
echo "+-------------------------------------------+"
sudo mysql -u root_user_for_Nginx_block -e "CREATE DATABASE $USER_DB_NAME;"
sudo mysql -u root_user_for_Nginx_block -e "CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';"
sudo mysql -u root_user_for_Nginx_block -e "GRANT ALL PRIVILEGES ON $USER_DB_NAME.* TO '$DB_USER'@'%';"
sudo mysql -u root_user_for_Nginx_block -e "FLUSH PRIVILEGES;"
echo "Database and user created successfully."


echo "+-------------------------------------------+"
echo -e "|                    ${BLUE}NGINX${NC}                  |"
echo "+-------------------------------------------+"
# Nginx block configuration
NGINX_CONFIG="server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    root $WWW_DIR;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    access_log /var/log/nginx/$DOMAIN/access.log;
    error_log /var/log/nginx/$DOMAIN/error.log;
}"

NGINX_CONFIG_WITH_SSL="server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN www.$DOMAIN;

    # Redirect HTTP to HTTPS
    location ~ /.well-known {
        allow all;
    }

    # Redirect all other HTTP traffic to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name $DOMAIN www.$DOMAIN;

    root $WWW_DIR;
    index index.php index.html index.htm;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$PHP_VERSION-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    access_log /var/log/nginx/$DOMAIN/ssl-access.log;
    error_log /var/log/nginx/$DOMAIN/ssl-error.log;
}"

# # Create SSH user
# sudo adduser --disabled-password --gecos "" $SSH_USER

# # Set password for the SSH user (using the same password as the database)
# sudo usermod --password $(echo $DB_PASSWORD | openssl passwd -1 -stdin) $SSH_USER

# # Add the SSH user to the web server's group (e.g., www-data for Nginx)
# sudo usermod -aG www-data $SSH_USER

# # Create the web directory
# sudo mkdir -p "$WWW_DIR"

# # Set specific directory permissions for the SSH user within the existing web directory
# USER_WEB_FOLDER="$WWW_DIR"
# sudo usermod --home "$USER_WEB_FOLDER" $SSH_USER

# # Set specific directory permissions for the SSH user and the web server
# sudo chown $SSH_USER:www-data $USER_WEB_FOLDER
# sudo chmod 750 $USER_WEB_FOLDER

# # Add the user to the ssh group for SSH access
# sudo usermod -aG ssh $SSH_USER

# # Add SSH user restriction in SSH daemon configuration
# echo "Match User $SSH_USER" | sudo tee -a /etc/ssh/sshd_config
# echo "ChrootDirectory %h" | sudo tee -a /etc/ssh/sshd_config
# echo "ForceCommand internal-sftp" | sudo tee -a /etc/ssh/sshd_config
# sudo systemctl restart ssh

# Create the index.php file
echo "<?php echo '<h1 style=\"text-align: center; margin-top: 40vh\">Congratulations! Welcome to Ongsho Cloud</h1>'; echo '<h2 style=\"text-align: center; margin-top: 10vh\">For more info, visit <a href=\"https://ongsho.com\">ongsho.com</a></h2>'; ?>" | sudo tee -a "$WWW_DIR/index.php" > /dev/null

# Create the directory for logs
sudo mkdir -p "/var/log/nginx/$DOMAIN/"

# Create the Nginx configuration file
echo "$NGINX_CONFIG" | sudo tee "$NGINX_AVAILABLE" > /dev/null
echo "Created Nginx configuration file $NGINX_AVAILABLE"

# Create a symbolic link to enable the site
sudo ln -s "$NGINX_AVAILABLE" "$NGINX_ENABLED"
echo "Created symbolic link $NGINX_ENABLED"

# Test Nginx configuration
sudo nginx -t

# Restart Nginx if the configuration is okay
if [ $? -eq 0 ]; then
    sudo systemctl restart nginx
    echo "Nginx restarted successfully."
else
    echo "Error: Nginx configuration test failed. Please check the configuration and restart Nginx manually."
fi

# ./ssl.sh $DOMAIN

# # Check the exit status of the ssl.sh script
# if [ $? -eq 0 ]; then
#     # Create the Nginx configuration file
#     echo "$NGINX_CONFIG_WITH_SSL" | sudo tee "$NGINX_AVAILABLE" > /dev/null

#     sudo rm -f "$NGINX_ENABLED"
#     # Create a symbolic link to enable the site
#     sudo ln -s "$NGINX_AVAILABLE" "$NGINX_ENABLED"
# else
#     echo "SSL certificate acquisition failed."
# fi

# # Test Nginx configuration
# sudo nginx -t

# # Restart Nginx if the configuration is okay
# if [ $? -eq 0 ]; then
#     sudo systemctl restart nginx
#     echo "Nginx restarted successfully."
# else
#     echo "Error: Nginx configuration test failed. Please check the configuration and restart Nginx manually."
# fi

echo "Loading Information.."
# Insert database information into ongsho_cloud.users table
sudo mysql -u root_user_for_Nginx_block ongsho_cloud -e "INSERT INTO users (domain, username, password, dbname) VALUES ('$DOMAIN','$DB_USER', '$DB_PASSWORD', '$USER_DB_NAME');"
# echo "Database information inserted into ongsho_cloud.users table."

# Schedule backup
(crontab -l ; echo "$SCHEDULE /home/ongsho_dev/script/backup.sh $DOMAIN /home/ongsho_dev/backup") | crontab -

echo "+-------------------------------------------+"
echo -e "|                ${BLUE}INFORMATION${NC}                |"
echo "+-------------------------------------------+"
echo "| DOMAIN       : http://$DOMAIN"
echo "| SSL          : https://$DOMAIN"
echo "| PHP VERSION  : $PHP_VERSION"
echo "| PHP MY ADMIN : http://192.168.0.111:8080"
echo "| SSH          : ssh $SSH_USER@192.168.0.111"
echo "| DATABASE     : $USER_DB_NAME"
echo "| DB USERNAME  : $DB_USER"
echo "| Account Pass : $DB_PASSWORD"
echo "+-------------------------------------------+"

# Schedule daily backups every 5 minutes
# (crontab -l ; echo "*/5 * * * * /home/ongsho_dev/script/backup.sh $DOMAIN /home/ongsho_dev/backup") | crontab -

# Schedule block deletion every hour
# (crontab -l ; echo "0 * * * * /home/ongsho_dev/script/backup.sh $DOMAIN /home/ongsho_dev/backup") | crontab -

# Schedule block deletain every day
# (crontab -l ; echo "0 0 * * * /home/ongsho_dev/script/backup.sh $DOMAIN /home/ongsho_dev/backup") | crontab -

# Schedule block deletain every week
# (crontab -l ; echo "0 0 * * 0 /home/ongsho_dev/script/backup.sh $DOMAIN /home/ongsho_dev/backup") | crontab -

# Schedule block deletain every month
# (crontab -l ; echo "0 0 1 * * /home/ongsho_dev/script/backup.sh $DOMAIN /home/ongsho_dev/backup") | crontab -

# ./backup.sh $DOMAIN '/home/ongsho_dev/backup'

# ./delete_block.sh $DOMAIN