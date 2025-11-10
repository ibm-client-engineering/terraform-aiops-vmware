locals {
  install_script_content = templatefile("${path.module}/cloudinit/k3s-install-server.sh.tftpl", {
    vsphere_hostname               = var.vsphere_hostname,
    vsphere_username               = var.vsphere_username,
    vsphere_password               = var.vsphere_password,
    vsphere_datacenter             = var.vsphere_datacenter,
    vsphere_folder                 = var.vsphere_folder,
    k3s_token                      = random_password.k3s_token.result,
    install_k3s                    = var.install_k3s,
    install_aiops                  = var.install_aiops,
    k3s_url                        = "${var.common_prefix}-haproxy.${var.base_domain}",
    accept_license                 = var.accept_license,
    ibm_entitlement_key            = var.ibm_entitlement_key,
    aiops_version                  = var.aiops_version
    num_nodes                      = var.k3s_agent_count + var.k3s_server_count,
    ignore_prereqs                 = var.ignore_prereqs ? true : false,
    use_private_registry           = var.use_private_registry ? true : false,
    private_registry               = local.private_registry,
    private_registry_user          = var.private_registry_user,
    private_registry_user_password = var.private_registry_user_password,
    private_registry_skip_tls      = var.private_registry_skip_tls ? "true" : "false",
    base_domain                    = var.base_domain,
    mode                           = var.mode,
    rhsm_username                  = var.rhsm_username,
    rhsm_password                  = var.rhsm_password,
    common_prefix                  = var.common_prefix,
    subnet_cidr                    = var.subnet_cidr,
    haproxy_ip                     = var.haproxy_ip,
    run_observers                  = var.run_observers
  })
  k8s_observer_script_content = templatefile("${path.module}/cloudinit/init_server/01_k8s_observer.sh.tftpl", {
    k3s_url = "${var.common_prefix}-haproxy.${var.base_domain}"
  })
  vcenter_observer_script_content = templatefile("${path.module}/cloudinit/init_server/02_vcenter_observer.sh.tftpl", {
    vsphere_hostname   = var.vsphere_hostname,
    vsphere_username   = var.vsphere_username,
    vsphere_password   = var.vsphere_password,
    vsphere_datacenter = var.vsphere_datacenter
  })
  merge_rules_script_content       = templatefile("${path.module}/cloudinit/init_server/03_merge_rules.sh.tftpl", {})
  prometheus_config_script_content = templatefile("${path.module}/cloudinit/init_server/04_prometheus_config.sh.tftpl", {})
  prometheus_rules_script_content = templatefile("${path.module}/cloudinit/init_server/05_prometheus_rules.sh.tftpl", {})
  k3s_registries_script_content    = templatefile("${path.module}/cloudinit/init_common/01_k3s_registries.sh.tftpl", {})
  restart_k3s_script_content       = templatefile("${path.module}/cloudinit/init_common/02_restart_k3s.sh.tftpl", {})
}

data "cloudinit_config" "k3s_server_userdata" {
  count = var.k3s_server_count

  gzip          = false
  base64_encode = true

  # cloud-config userdata 
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloudinit/server-userdata.yaml", {
      index         = "${count.index}",
      base_domain   = "${var.base_domain}"
      public_key    = tls_private_key.deployer.public_key_openssh
      common_prefix = "${var.common_prefix}"
    })
  }

  part {
    filename     = "k3s-install-server.yaml"
    content_type = "text/cloud-config"

    # Pass the resulting script content to the simplified YAML template.
    content = templatefile("${path.module}/cloudinit/k3s-install-server.yaml.tftpl", {
      install_script           = indent(6, local.install_script_content),
      k3s_observer_script      = indent(6, local.k8s_observer_script_content),
      vcenter_observer_script  = indent(6, local.vcenter_observer_script_content)
      merge_rules_script       = indent(6, local.merge_rules_script_content),
      prometheus_config_script = indent(6, local.prometheus_config_script_content),
      k3s_registries_script    = indent(6, local.k3s_registries_script_content),
      restart_k3s_script       = indent(6, local.restart_k3s_script_content),
      prometheus_rules_script  = indent(6, local.prometheus_rules_script_content)
    })
  }
}

locals {
  server_metadata = [
    for i in range(var.k3s_server_count) : templatefile("${path.module}/cloudinit/server-metadata.yaml", {
      index         = i,
      base_domain   = var.base_domain,
      common_prefix = var.common_prefix,
      subnet_cidr   = var.subnet_cidr,
      k3s_server_ip = "${var.k3s_server_ips[i]}"
    })
  ]
}

resource "vsphere_virtual_machine" "k3s_server" {
  count = var.k3s_server_count

  name             = "${var.common_prefix}-k3s-server-${count.index}"
  resource_pool_id = data.vsphere_resource_pool.target_pool.id
  datastore_id     = data.vsphere_datastore.this.id

  folder = var.vsphere_folder

  num_cpus  = local.per_node_cpus
  memory    = local.per_node_memory_gb
  guest_id  = data.vsphere_virtual_machine.template.guest_id
  scsi_type = data.vsphere_virtual_machine.template.scsi_type

  network_interface {
    network_id = data.vsphere_network.this.id
  }

  wait_for_guest_net_timeout = 30

  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template.disks.0.size
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }


  disk {
    label            = "disk1"
    size             = 25 # Size in GB
    unit_number      = 1
    eagerly_scrub    = false
    thin_provisioned = true
  }

  disk {
    label            = "disk2"
    size             = 120 # Size in GB
    unit_number      = 2
    eagerly_scrub    = false
    thin_provisioned = true
  }

  disk {
    label            = "disk3"
    size             = 120 # Size in GB
    unit_number      = 3
    eagerly_scrub    = false
    thin_provisioned = true
  }

  disk {
    label            = "disk4"
    size             = 120 # Size in GB
    unit_number      = 4
    eagerly_scrub    = false
    thin_provisioned = true
  }

  firmware                = "efi" # Ensure this matches your Packer template's firmware type
  efi_secure_boot_enabled = false # Disable Secure Boot during cloning

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  # Copy the self-signed certificate 
  provisioner "file" {

    connection {
      type        = "ssh"
      user        = "clouduser"
      private_key = tls_private_key.deployer.private_key_pem
      host        = self.default_ip_address
    }

    source      = "${path.module}/aiops-certificate-chain.pem"
    destination = "/tmp/aiops-certificate-chain.pem"
  }

  # Copy the private key 
  provisioner "file" {

    connection {
      type        = "ssh"
      user        = "clouduser"
      private_key = tls_private_key.deployer.private_key_pem
      host        = self.default_ip_address
    }

    source      = "${path.module}/aiops.key.pem"
    destination = "/tmp/aiops.key.pem"
  }

  # Copy utility script
  provisioner "file" {

    connection {
      type        = "ssh"
      user        = "clouduser"
      private_key = tls_private_key.deployer.private_key_pem
      host        = self.default_ip_address
    }

    source      = "${path.module}/util/trigger_disk_alert.sh"
    destination = "/home/clouduser/trigger_disk_alert.sh"
  }

  # Copy the ethtool fix script
  provisioner "file" {

    connection {
      type        = "ssh"
      user        = "clouduser"
      private_key = tls_private_key.deployer.private_key_pem
      host        = self.default_ip_address
    }

    source      = "${path.module}/cloudinit/flannel-ethtool-fix.sh"
    destination = "/tmp/flannel-ethtool-fix.sh"
  }

  # Make the script executable and set ownership to root
  provisioner "remote-exec" {

    connection {
      type        = "ssh"
      user        = "clouduser"
      private_key = tls_private_key.deployer.private_key_pem
      host        = self.default_ip_address
    }

    inline = [
      "sudo mv /tmp/flannel-ethtool-fix.sh /usr/local/bin/flannel-ethtool-fix.sh",
      "sudo chmod +x /usr/local/bin/flannel-ethtool-fix.sh",
      "sudo chown root:root /usr/local/bin/flannel-ethtool-fix.sh",
    ]
  }

  lifecycle {
    # Terraform will ignore any changes to these attributes
    # after the resource has been created.
    ignore_changes = [
      memory,
      num_cpus,
      extra_config
    ]
    precondition {
      # CRITICAL CHECK: Ensure the vsphere_virtual_machine data source successfully 
      # found the template by checking if a reliable attribute (like guest_id) is populated.
      condition     = data.vsphere_virtual_machine.template.guest_id != null
      error_message = "VSphere Template Validation Failed: The VM template '${var.template_name}' was not found in the specified Datacenter. Please verify the spelling and location of the template."
    }    
  }

  extra_config = {
    "guestinfo.metadata"          = base64encode(local.server_metadata[count.index])
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.k3s_server_userdata[count.index].rendered
    "guestinfo.userdata.encoding" = "base64"
  }
}
