#!/bin/bash

# Extract the base_domain from terraform.tfvars
base_domain=$(grep 'base_domain' terraform.tfvars | cut -d'"' -f2)
# Extract the common_prefix from terraform.tfvars
common_prefix=$(grep 'common_prefix' terraform.tfvars | cut -d'"' -f2)

# Check if the base_domain variable was found
if [ -z "$base_domain" ]; then
    echo "Error: 'base_domain' variable not found in terraform.tfvars"
    exit 1
fi

# Remove k3s- entries from known_hosts
sed -i "/^${common_prefix}-k3s-server-0/d" ~/.ssh/known_hosts

# SSH into the server
ssh -q -i ./modules/aiops-vmware/id_rsa -o StrictHostKeyChecking=false "clouduser@${common_prefix}-k3s-server-0.${base_domain}"