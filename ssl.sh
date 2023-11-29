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

input(){
    read -p "Enter your input: " DOMAIN
}

output(){
    local msg=$1
    echo ${msg}
}

close() {
    echo "press ctrl+x to exit"
    # wait and check for ctrl+x and don't exit if press ctrl+c
    trap 'echo -e "\n"' SIGINT

    while true; do
        read -t 1 -n 1 key
        if [[ $key == $'\x18' ]]; then
            clear
            break
        fi
    done
}

get_ip_address(){
    local domain=$1
    local server_ip=$2
    local days=$3

    ip_address=$(dig +short $DOMAIN)
    if [ -n "$ip_address" ] && [ $ip_address = $server_ip ]; then

        output "DNS record found for $domain"

        output "Creating Self-Signed SSL certificate for $domain"

        # ----------------- OPENSSL --------------------
        # openssl req -x509 -nodes -days $days -newkey rsa:2048 -keyout "$domain.key" -out "$domain.crt" -subj "/CN=$domain"

        # Configure your web server to use the SSL certificate
        # For example, for Apache:
        # sudo cp "$domain.crt" /etc/ssl/certs/
        # sudo cp "$domain.key" /etc/ssl/private/
        # Update Apache virtual host configuration to include SSL settings

        # For Nginx:
        # sudo mkdir /etc/nginx/ssl/$domain
        # sudo cp "$domain.crt" /etc/nginx/ssl/$domain
        # sudo cp "$domain.key" /etc/nginx/ssl/$domain
        # copy then delete the key and certificate files
        # sudo rm "$domain.key"
        # sudo rm "$domain.crt"
        # Update Nginx server block configuration to include SSL settings

        # ----------------- Let's Encrypt --------------------

        sudo certbot certonly --nginx -d "$domain" -d "www.$domain" --agree-tos --register-unsafely-without-email

        if [ $? -eq 0 ]; then
            echo "Let's Encrypt certificate obtained successfully for $domain."
        else
            echo "Error: Let's Encrypt certificate not obtained for $domain."
        fi

    else
        output "DNS record not found for $domain"
    fi
}

#check Check if a command-line argument is provided
if [ $# -lt 1 ]; then
    input
else
    DOMAIN=$1
fi

server_ip="116.206.62.214"
days="90"
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "+-------------------------------------------+"
echo -e "|              ${BLUE}SSL Configuring${NC}              |"
echo "+-------------------------------------------+"

get_ip_address $DOMAIN $server_ip $days

# close