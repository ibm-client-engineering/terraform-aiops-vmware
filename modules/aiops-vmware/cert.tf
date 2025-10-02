# Define the CA's private key
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create the self-signed CA certificate
resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name = "My AIOps CA"
  }

  is_ca_certificate = true

  validity_period_hours = 8760 # 365 days
  early_renewal_hours   = 24

  # Key usages for a CA
  allowed_uses = [
    "crl_signing",
    "cert_signing",
  ]
}

# Define the server's private key
resource "tls_private_key" "aiops" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create the Certificate Signing Request (CSR)
resource "tls_cert_request" "aiops" {
  private_key_pem = tls_private_key.aiops.private_key_pem

  subject {
    common_name = "aiops-cpd.${var.common_prefix}-haproxy.${var.base_domain}"
  }

  # Add the Subject Alternative Names
  dns_names = [
    "aiops-cpd.${var.common_prefix}-haproxy.${var.base_domain}",
    "cp-console-aiops.${var.common_prefix}-haproxy.${var.base_domain}",
  ]
}

# Sign the CSR with the CA to create the final server certificate
resource "tls_locally_signed_cert" "aiops" {
  cert_request_pem = tls_cert_request.aiops.cert_request_pem

  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760 # 365 days
  early_renewal_hours   = 24

  # This is a server certificate, so it needs these
  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

# Write the full certificate chain to a local file
resource "local_file" "aiops_certificate_chain" {
  content  = "${tls_locally_signed_cert.aiops.cert_pem}${tls_self_signed_cert.ca.cert_pem}"
  filename = "${path.module}/aiops-certificate-chain.pem"
}

# Write the key to a local file
resource "local_file" "aiops_key" {
  content  = tls_private_key.aiops.private_key_pem
  filename = "${path.module}/aiops.key.pem"
}