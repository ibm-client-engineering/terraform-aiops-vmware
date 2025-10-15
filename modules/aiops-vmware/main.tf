terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    vsphere = {
      source  = "vmware/vsphere"
      version = "~> 2.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "vsphere" {
  user           = var.vsphere_username
  password       = var.vsphere_password
  vsphere_server = var.vsphere_hostname

  # If you have a self-signed cert
  allow_unverified_ssl = true
}

resource "random_password" "k3s_token" {
  length  = 55
  special = false
}

locals {
  # build the private registry URL
  private_registry = var.private_registry_repo != "" ? "${var.private_registry_host}:${var.private_registry_port}/${var.private_registry_repo}" : "${var.private_registry_host}:${var.private_registry_port}"

  total_nodes = var.k3s_server_count + var.k3s_agent_count

  # these are the minimums for base and extended deployment
  cpu_pool    = var.mode == "base" ? 136 : 162
  mem_pool_gb = var.mode == "base" ? 322 : 380

  # calculate cpus and memory needed per node
  num_cpus = max(16, ceil(local.cpu_pool / local.total_nodes))
  memory   = max(20480, ceil(local.mem_pool_gb / local.total_nodes) * 1024)
}


########################################
# Persist the per-node memory in state
########################################

# Terraform 1.4+ (preferred over null_resource)
resource "terraform_data" "frozen_node_memory" {
  input = {
    per_node_memory_gb = local.memory
  }

  # Keep the first-calculated value unless we intentionally replace this resource
  lifecycle {
    ignore_changes = [input]
  }
}

resource "terraform_data" "frozen_node_cpu" {
  input = {
    per_node_cpus = local.num_cpus
  }

  # Keep the first-calculated value unless we intentionally replace this resource
  lifecycle {
    ignore_changes = [input]
  }
}

# Frozen values to use for all nodes, both initial and additional
locals {
  per_node_memory_gb = terraform_data.frozen_node_memory.output.per_node_memory_gb
  per_node_cpus = terraform_data.frozen_node_cpu.output.per_node_cpus
}


# provider "pfsense" {
#   url      = "https://${var.pfsense_host}" 
#   username = var.pfsense_username
#   password = var.pfsense_password
#   tls_skip_verify = true
# }