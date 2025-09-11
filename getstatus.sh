#!/bin/bash

# Extract the base_domain from terraform.tfvars
base_domain=$(grep 'base_domain' terraform.tfvars | cut -d'"' -f2)

# Check if the base_domain variable was found
if [ -z "$base_domain" ]; then
    echo "Error: 'base_domain' variable not found in terraform.tfvars"
    exit 1
fi

# Remove k3s- entries from known_hosts
sed -i "/^k3s-/d" ~/.ssh/known_hosts

# SSH into the server and run the command
ssh -i ./id_rsa -o StrictHostKeyChecking=false "clouduser@k3s-server-0.${base_domain}" << 'EOF'
sudo /usr/local/bin/aiopsctl status
EOF