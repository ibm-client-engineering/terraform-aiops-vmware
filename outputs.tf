output "vm_ip_addresses" {
  description = "The IP address of the vSphere virtual machine"
  value       = module.aiops_linux.vm_ip_addresses
}

output "haproxy_ip_address" {
  description = "The IP address of the haproxy virtual machine"
  value       = module.aiops_linux.haproxy_ip_address
}

output "aiops_etc_hosts" {
  value       = module.aiops_linux.aiops_etc_hosts
  description = "Plug this into your local /etc/hosts file to properly resolve hosts for UI."
}