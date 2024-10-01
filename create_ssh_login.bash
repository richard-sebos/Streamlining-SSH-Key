#!/bin/bash

###############################################################################
# Script Name:    ssh_key_setup.sh
# Description:    This script automates the process of generating an SSH key pair 
#                 and configuring SSH access to a remote server. It performs the 
#                 following tasks:
#                 - Validates input parameters (host name, IP address, username)
#                 - Ensures the user exists on the local system
#                 - Creates the necessary directory to store the SSH key and configuration
#                 - Generates a new SSH key pair using the ed25519 algorithm
#                 - Copies the SSH public key to the remote server for passwordless login
#                 - Updates the user's SSH config file to include the generated key
#
# Usage:          ./ssh_key_setup.sh <host_name> <ip_address> <username>
#
# Arguments:
#   <host_name>   - The name of the server for which the SSH key is being generated.
#   <ip_address>  - The IP address of the remote server.
#   <username>    - The username on the local system for which the SSH key is being created.
#
# Exit Codes:
#   0  - Success
#   1  - Invalid number of arguments or parameter validation failed
#   2  - Failed to create necessary directories or files
#   3  - SSH key generation failed
#   4  - Failed to copy SSH public key to the remote server
#
# Notes:          - The script assumes that `ssh-copy-id` is available on the system.
#                 - The SSH key is generated without a passphrase for automation purposes.
#                 - The script appends the necessary configuration to the user's 
#                   ~/.ssh/config file if it's not already present.
#
###############################################################################


# Function to validate an IP address (IPv4 format)
function valid_ip() {
    local ip=$1
    local stat=1

    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        if [ ${ip[0]} -le 255 ] && [ ${ip[1]} -le 255 ] && [ ${ip[2]} -le 255 ] && [ ${ip[3]} -le 255 ]; then
            stat=0
        fi
    fi
    return $stat
}

# Check if the script is being run with the necessary number of parameters
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <host_name> <ip_address> <username>"
  exit 1
fi

# Assign parameters to variables
host_name=$1
ip_address=$2
user=$3
local_user=$USER
# Validate the IP address format
if ! valid_ip $ip_address; then
  echo "Error: Invalid IP address format for $ip_address."
  exit 1
fi


# Define directories
config_directory=/home/${local_user}/.ssh/include.d/${host_name}
echo "${config_directory}"
# Check if the SSH config directory exists, create it if not
if [ ! -d "${config_directory}" ]; then
  echo "Creating SSH config directory at ${config_directory}..."
  mkdir -p ${config_directory}
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create config directory at ${config_directory}"
    exit 1
  fi
fi

# Set default ACL permissions on the login directory
setfacl -d -m u::rw,g::-,o::- ${config_directory}
if [ $? -ne 0 ]; then
  echo "Error: Failed to set ACL on ${config_directory}"
  exit 1
fi

# Generate a new SSH key pair using ed25519 algorithm, with no passphrase (-N "")
ssh-keygen -t ed25519 -f ${config_directory}/${host_name} -N ""  # Empty passphrase
if [ $? -ne 0 ]; then
  echo "Error: SSH key generation failed for ${host_name}"
  exit 1
fi

# Copy the SSH key to the remote host
echo "Copying SSH public key to ${user}@${ip_address}..."
ssh-copy-id -i ${config_directory}/${host_name}.pub ${user}@${ip_address}
if [ $? -ne 0 ]; then
  echo "Error: Failed to copy SSH public key to ${user}@${ip_address}"
  exit 1
fi

# Create the config file inside the config_directory and write the necessary SSH config lines
echo "Creating SSH config file at ${config_directory}/config..."
cat <<EOL > ${config_directory}/config
Host ${host_name}
     HostName ${ip_address}
     User ${user}
     IdentityFile ${config_directory}/${host_name}
EOL

# Append the Include line to ~/.ssh/config if it's not already present
ssh_config_file=/home/${local_user}/.ssh/config
# Ensure the ~/.ssh/config file exists
if [ ! -f "${ssh_config_file}" ]; then
  touch "${ssh_config_file}"
  chmod 600 "${ssh_config_file}"
fi

# Check if the Include line is already in the file
if ! grep -Fxq "Include ${config_directory}/config" "${ssh_config_file}"; then
  echo "Adding 'Include ${config_directory}/config' to ${ssh_config_file}..."
  #echo "Include ${config_directory}/config" >> "${ssh_config_file}"
  echo "Include ${config_directory}/config" | cat - "${ssh_config_file}" > temp_file && mv temp_file ${ssh_config_file}
  if [ $? -ne 0 ]; then
    echo "Error: Failed to append the Include line to ${ssh_config_file}"
    exit 1
  fi
fi

# Try to SSH into the server using the newly created key
ssh ${host_name}
if [ $? -ne 0 ]; then
  echo "Error: Failed to connect to ${host_name}"
  exit 1
fi

echo "SSH key successfully created, user logged into the server, and config files updated."
