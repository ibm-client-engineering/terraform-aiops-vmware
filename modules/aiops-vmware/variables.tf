variable "rhsm_username" {
  type        = string
  description = "The username for your Red Hat Subscription Management account."
}

variable "rhsm_password" {
  type        = string
  description = "The password for your Red Hat Subscription Management account."
}

// vSphere Credentials

variable "vsphere_hostname" {
  type        = string
  description = "The fully qualified domain name or IP address of the vCenter Server instance."
}

variable "vsphere_username" {
  type        = string
  description = "The username to login to the vCenter Server instance."
  sensitive   = true
}

variable "vsphere_password" {
  type        = string
  description = "The password for the login to the vCenter Server instance."
  sensitive   = true
}

variable "vsphere_datacenter" {
  type        = string
  description = "The name of the vSphere Datacenter into which resources will be created."
}

variable "vsphere_cluster" {
  type        = string
  description = "The vSphere Cluster into which resources will be created."
}

variable "vsphere_datastore" {
  type        = string
  description = "The vSphere Datastore into which resources will be created."
}

variable "vsphere_network" {
  type        = string
  description = "The name of the target vSphere network segment."
}

variable "template_name" {
  type = string
}

variable "secondary_disk_size" {
  type        = number
  default     = 30
  description = "How big we want our disk in case we don't like defaults."
}

variable "nameservers" {
  type    = list(any)
  default = []
}

variable "vsphere_folder" {
  type        = string
  description = "The name of the target vSphere folder."
}

variable "vsphere_resource_pool" {
  type        = string
  description = "The name of the target vSphere resource pool."
}

variable "k3s_server_count" {
  type    = number
  default = 3
}

variable "k3s_agent_count" {
  type    = number
  default = 6
}

variable "install_k3s" {
  type        = string
  description = "Set to 'true' to install K3s. If set to 'true', 'accept_license' must also be 'true'."
  default     = "true"

  validation {
    # Logic: 
    # IF install_k3s is "true" (var.install_k3s == "true"), 
    # THEN the condition must be that accept_license is "true" (var.accept_license == "true").
    # ELSE (if install_k3s is not "true"), the condition is automatically true (true).
    condition     = var.install_k3s == "true" ? var.accept_license == "true" : true

    error_message = "Installation cannot proceed. If 'install_k3s' is set to \"true\", 'accept_license' must also be explicitly set to \"true\"."
  }
}

variable "install_aiops" {
  default     = "true"
  type        = string
  description = "Can be either 'true' or 'false'."
}

variable "common_prefix" {
  type    = string
  default = "aiops"
}

variable "subnet_cidr" {
  type        = string
  default     = "192.168.252.0/24"
  description = "Subnet CIDR for the cluster."
}

variable "haproxy_ip" {
  type        = string
  default     = "192.168.252.9"
  description = "IP address for the AIOps haproxy."
}

variable "k3s_server_ips" {
  type        = list(string)
  default     = ["192.168.252.10", "192.168.252.11", "192.168.252.12"]
  description = "IP addresses for the AIOps k3s server (control plane) nodes."
  validation {
    # The condition checks that the length of the list is exactly
    # equal to the value of the k3s_server_count variable.
    condition = length(var.k3s_server_ips) == var.k3s_server_count
    # The error message includes the expected number of items.
    error_message = "The list must contain exactly ${var.k3s_server_count} values."
  }
}

variable "accept_license" {
  type    = string
  default = "false"
}

variable "ibm_entitlement_key" {
  type    = string
  default = ""

  validation {
    condition     = var.use_private_registry || trimspace(var.ibm_entitlement_key) != ""
    error_message = "ibm_entitlement_key must not be empty when use_private_registry is false."
  }
}

variable "ignore_prereqs" {
  default     = false
  type        = bool
  description = "Ignore prerequisites checks during installation and force installation. WARNING: NON-PRODUCTION ONLY"
}

variable "mode" {
  default     = "base"
  type        = string
  description = "AIOps installation mode, options are base or extended"
  validation {
    condition     = contains(["base", "extended"], var.mode)
    error_message = "Mode must be either 'base' or 'extended'."
  }
}

variable "aiops_version" {
  type        = string
  description = "Version of AIOps to install, only versions 4.9.x has been tested"
}

variable "base_domain" {
  type    = string
  default = "gym.lan"
}

variable "run_observers" {
  type        = bool
  default     = true
  description = "Run VMware vCenter and kubernetes observers post install"
}

// mailcow (demo application) variables

variable "use_mailcow" {
  default     = false
  type        = bool
  description = "Create and use a mailcow instance for email notifications"
}

variable "mailcow_ip" {
  type        = string
  default     = "192.168.252.100"
  description = "IP address for the mailcow instance"
}

variable "pfsense_host" {
  type        = string
  default     = "192.168.252.1"
  description = "The hostname or IP address of the pfSense instance to manage."
}

variable "pfsense_username" {
  type        = string
  default     = "admin"
  description = "Username for pfSense management."
}

variable "pfsense_password" {
  type        = string
  default     = "pfsense"
  description = "Password for pfSense management."
}

// Private registry variables

variable "use_private_registry" {
  default     = false
  type        = bool
  description = "Use a private registry, something other than cp.icr.io"
}

variable "private_registry_host" {
  default     = ""
  type        = string
  description = "DNS or IP of private registry hosting the AIOps container images"

  validation {
    condition     = !(var.use_private_registry && trimspace(var.private_registry_host) == "")
    error_message = "private_registry_host must not be empty when use_private_registry is true."
  }
}

variable "private_registry_repo" {
  default     = ""
  type        = string
  description = "Repository name, to be appended to host:port when building registry URL (e.g. host:port/repo)"
}

variable "private_registry_port" {
  default     = 5000
  type        = number
  description = "Port number for private registry"
}

variable "private_registry_user" {
  default     = "registryuser"
  type        = string
  description = "Login user for private registry"
}

variable "private_registry_user_password" {
  default     = "registryuserpassword"
  type        = string
  description = "Login user password for private registry"
}

variable "private_registry_skip_tls" {
  default     = true
  type        = bool
  description = "Skip TLS verification for private registry"
}
