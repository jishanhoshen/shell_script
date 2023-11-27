#!/bin/bash

if [ $# -lt 1 ]; then
    echo "Usage: $0 <domain> [php_version] [db_user] [db_password]"
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
    echo "Available PHP versions:"
    PHP_VERSIONS=($(ls /etc/php | grep -E '^[0-9]+\.[0-9]+$' | sort -r))
    
    for i in "${!PHP_VERSIONS[@]}"; do
        echo "$((i+1))) ${PHP_VERSIONS[i]}"
    done
    
    read -rp "Enter PHP version number (press Enter for the default v$DEFAULT_PHP_VERSION): " php_choice

    if [ -z "$php_choice" ]; then
        PHP_VERSION="$DEFAULT_PHP_VERSION"
    else
        # Set PHP_VERSION based on user input
        PHP_VERSION="${PHP_VERSIONS[php_choice-1]}"
    fi
    echo "Selected PHP version: $PHP_VERSION"
fi


# Prompt for database name
read -p "Enter database name (press Enter for a random name): " USER_DB_NAME

# Set a default random database name if the user doesn't enter one
if [ -z "$USER_DB_NAME" ]; then
    RANDOM_STRING=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8)  # Generate a random string
    USER_DB_NAME="OCloud_${RANDOM_STRING}"  # Prefix + random string
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
    read -s -p "Enter database password (press Enter for a random password): " DB_PASSWORD
    echo

    # Set a default random password if the user doesn't enter one
    if [ -z "$DB_PASSWORD" ]; then
        RANDOM_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 12)  # Generate a random password
        DB_PASSWORD=$RANDOM_PASSWORD
    fi
else
    DB_PASSWORD=$4
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
echo "Creating database $USER_DB_NAME and user $DB_USER..."
sudo mysql -u root_user_for_Nginx_block -e "CREATE DATABASE $USER_DB_NAME;"
sudo mysql -u root_user_for_Nginx_block -e "CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';"
sudo mysql -u root_user_for_Nginx_block -e "GRANT ALL PRIVILEGES ON $USER_DB_NAME.* TO '$DB_USER'@'%';"
sudo mysql -u root_user_for_Nginx_block -e "FLUSH PRIVILEGES;"
echo "Database and user created successfully."

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

# Create the web directory
sudo mkdir -p "$WWW_DIR"

# Create the index.php file
echo "<?php echo '<h1 style=\"text-align: center; margin-top: 40vh\">Congratulations! Welcome to Ongsho Cloud</h1>'; echo '<h2 style=\"text-align: center; margin-top: 10vh\">For more info, visit <a href=\"https://ongsho.com\">ongsho.com</a></h2>'; ?>" | sudo tee -a "$WWW_DIR/index.php" > /dev/null

# Create the directory for logs
sudo mkdir -p "/var/log/nginx/$DOMAIN/"

# Create the Nginx configuration file
echo "$NGINX_CONFIG" | sudo tee "$NGINX_AVAILABLE" > /dev/null

# Create a symbolic link to enable the site
sudo ln -s "$NGINX_AVAILABLE" "$NGINX_ENABLED"

# Test Nginx configuration
sudo nginx -t

# Restart Nginx if the configuration is okay
if [ $? -eq 0 ]; then
    sudo systemctl restart nginx
    echo "Nginx restarted successfully."
else
    echo "Error: Nginx configuration test failed. Please check the configuration and restart Nginx manually."
fi

echo "Loading Information.."
# Insert database information into ongsho_cloud.users table
sudo mysql -u root_user_for_Nginx_block ongsho_cloud -e "INSERT INTO users (domain, username, password, dbname) VALUES ('$DOMAIN','$DB_USER', '$DB_PASSWORD', '$USER_DB_NAME');"
# echo "Database information inserted into ongsho_cloud.users table."

echo "+-------------------------------------------+"
echo "|                INFORMATION                |"
echo "+-------------------------------------------+"
echo "| DOMAIN       : http://$DOMAIN"
echo "| SSS          : https://$DOMAIN"
echo "| PHP VERSION  : $PHP_VERSION"
echo "| PHP MY ADMIN : http://192.168.0.111:8080"
echo "| DATABASE     : $USER_DB_NAME"
echo "| DB USERNAME  : $DB_USER"
echo "| DB PASSWORD  : $DB_PASSWORD"
echo "+-------------------------------------------+"

# Schedule daily backups every 5 minutes
(crontab -l ; echo "*/5 * * * * /home/ongsho_dev/script/backup.sh $DOMAIN /home/ongsho_dev/backup") | crontab -

# ./backup.sh $DOMAIN '/home/ongsho_dev/backup'

# ./delete_block.sh $DOMAIN