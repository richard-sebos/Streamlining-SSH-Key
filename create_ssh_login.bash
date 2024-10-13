#!/bin/bash
###############################################################################
# Script Name:    ssh_key_setup.sh
# Description:    Automates SSH key pair generation and configuration for 
#                 passwordless SSH access to a remote server.
#
# Usage:          ./ssh_key_setup.sh <host_name> <ip_address> <username>
#
# Arguments:
#   <host_name>   - Name of the remote server.
#   <ip_address>  - IP address of the remote server.
#   <username>    - Username for SSH access on the remote server.
#
# Exit Codes:
#   0 - Success
#   1 - Invalid arguments or parameter validation failed
#   2 - Directory or file creation failed
#   3 - SSH key generation failed
#   4 - Failed to copy SSH key to remote server
#
# Notes: 
#   - Assumes `ssh-copy-id` is available on the system.
#   - SSH key is generated without a passphrase for automation.
###############################################################################

# Function to validate an IP address
valid_ip() {
    local ip=$1
    local stat=1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        if [[ ${octets[0]} -le 255 && ${octets[1]} -le 255 && \
              ${octets[2]} -le 255 && ${octets[3]} -le 255 ]]; then
            stat=0
        fi
    fi
    return $stat
}

# Ensure the script is run with the correct number of parameters
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <host_name> <ip_address> <username>"
    exit 1
fi

# Assign parameters to variables
host_name=$1
ip_address=$2
user=$3
local_user=$USER

# Validate the IP address
if ! valid_ip "$ip_address"; then
    echo "Error: Invalid IP address format: $ip_address"
    exit 1
fi

# Define and create the SSH config directory if it doesn't exist
config_directory="/home/${local_user}/.ssh/include.d/${host_name}"
if [ ! -d "$config_directory" ]; then
    echo "Creating SSH config directory: $config_directory..."
    mkdir -p "$config_directory" || { echo "Error: Failed to create directory"; exit 2; }
fi

# Set ACL permissions on the directory
setfacl -d -m u::rw,g::-,o::- "$config_directory" || { 
    echo "Error: Failed to set ACL on $config_directory"; exit 2; 
}

# Generate SSH key pair
ssh-keygen -t ed25519 -f "${config_directory}/${host_name}" -N "" || {
    echo "Error: SSH key generation failed"; exit 3;
}

# Copy the SSH key to the remote server
echo "Copying SSH public key to ${user}@${ip_address}..."
ssh-copy-id -i "${config_directory}/${host_name}.pub" "${user}@${ip_address}" || {
    echo "Error: Failed to copy SSH key"; exit 4;
}

# Create SSH config file
cat <<EOL > "${config_directory}/config"
Host ${host_name}
    HostName ${ip_address}
    User ${user}
    IdentityFile ${config_directory}/${host_name}
EOL

# Append Include directive to ~/.ssh/config if not already present
ssh_config_file="/home/${local_user}/.ssh/config"
touch "$ssh_config_file"
chmod 600 "$ssh_config_file"

if ! grep -Fxq "Include ${config_directory}/config" "$ssh_config_file"; then
    echo "Adding 'Include ${config_directory}/config' to $ssh_config_file..."
    echo "Include ${config_directory}/config" | cat - "$ssh_config_file" > temp_file && mv temp_file "$ssh_config_file" || {
        echo "Error: Failed to update SSH config"; exit 2;
    }
fi

# Test SSH connection
echo "Testing SSH connection to ${host_name}..."
ssh "${host_name}" || {
    echo "Error: Failed to connect to ${host_name}"; exit 1;
}

echo "SSH setup complete: Key created, config updated, and connection tested."
