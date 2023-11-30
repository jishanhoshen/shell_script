#!/bin/bash

if [ $# -ne 2 ]; then
    echo "Usage: $0 <username> <directory>"
    exit 1
fi

USERNAME=$1
DIRECTORY=$2

# Create user
sudo adduser $USERNAME

# Set password (you can modify this as needed)
sudo passwd $USERNAME

# Create the specified directory
sudo mkdir -p $DIRECTORY

# Set ownership and permissions for the directory
sudo chown $USERNAME:$USERNAME $DIRECTORY
sudo chmod 755 $DIRECTORY

# Add the user to the www-data group (assuming it exists)
sudo usermod -aG www-data $USERNAME

# Add the user to the ssh group for SSH access
sudo usermod -aG ssh $USERNAME

# Set the user's home directory to the specified directory
sudo usermod --home $DIRECTORY $USERNAME

# Create an authorized_keys file for SSH key-based authentication
sudo mkdir -p $DIRECTORY/.ssh
sudo touch $DIRECTORY/.ssh/authorized_keys
sudo chown -R $USERNAME:$USERNAME $DIRECTORY/.ssh
sudo chmod 700 $DIRECTORY/.ssh
sudo chmod 600 $DIRECTORY/.ssh/authorized_keys

echo "User $USERNAME has been created with access to $DIRECTORY"
