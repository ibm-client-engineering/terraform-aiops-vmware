#!/bin/bash

set -x

# output in /var/log/cloud-init-output.log

install_k3s=${install_k3s}
install_aiops=${install_aiops}
num_nodes=${num_nodes}

SETUP_DIR="$(dirname "$(readlink -f "$0")")"
MODULES_DIR="$${SETUP_DIR}/server_modules"

# --- Load all module files ---
# Modules are loaded in alphabetical/numeric order based on their filename.
for module in "$${MODULES_DIR}"/*.sh; do
    echo "Sourcing module: $${module}"
    source "$${module}"
done

wait_lb() {
while [ true ]
do
  curl --output /dev/null --silent -k https://${k3s_url}:6443
  if [[ "$?" -eq 0 ]]; then
    break
  fi
  sleep 5
  echo "wait for LB"
done
}

disable_checksum_offload() {
# Disable TX checksum offloading for the flannel.1 interface to prevent packet corruption issues
# in some environments where the underlying network does not support checksum offloading properly.
# This is especially relevant in virtualized or cloud environments using Flannel as the CNI.

cat << 'EOF' >> /etc/systemd/system/flannel-ethtool-fix.service
[Unit]
Description=Flannel Ethtool Fix for vSphere VXLAN Checksum Offload
After=network-online.target
After=k3s.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/flannel-ethtool-fix.sh

[Install]
WantedBy=multi-user.target
EOF

# Reload the systemd configuration to recognize the new unit
systemctl daemon-reload

# Enable the service to run automatically on every boot
systemctl enable flannel-ethtool-fix.service

# Start the service immediately (without rebooting)
systemctl start flannel-ethtool-fix.service
}

# use k3sadmin group to allow clouduser to run commands
nonroot_config() {
groupadd k3sadmin
usermod -aG k3sadmin clouduser

chown root:k3sadmin /usr/local/bin/k3s
chmod 750 /usr/local/bin/k3s

chown root:k3sadmin /etc/rancher/
chmod 750 /etc/rancher/

chown -R root:k3sadmin /etc/rancher/k3s/
chmod 750 /etc/rancher/k3s/

chmod 750 /etc/rancher/k3s/config.yaml
chmod 660 /etc/rancher/k3s/k3s.yaml

# for crictl
chown root:k3sadmin /var/lib/rancher/k3s/agent/etc/
chmod 750 /var/lib/rancher/k3s/agent/etc/
# for crictl
chown root:k3sadmin /var/lib/rancher/k3s/agent/etc/crictl.yaml
chmod 640 /var/lib/rancher/k3s/agent/etc/crictl.yaml

mkdir -p /home/clouduser/.kube
cp /etc/rancher/k3s/k3s.yaml /home/clouduser/.kube/config
chown -R clouduser:clouduser /home/clouduser/.kube

cat << 'EOF' >> /home/clouduser/.bashrc

export KUBECONFIG="/home/clouduser/.kube/config"

# Function to list unhealthy K8s pods by filtering out 'Completed' and 'Ready' states (e.g., '1/1')
kget_unhealthy_pods() {
  kubectl get pods -A | grep -vE "Completed|([0-9]+)/\1"
}

# enable vi on the command line
set -o vi

# kubectl alias
alias k=kubectl
EOF

# Check if kubectl is installed and set up completion
if command -v kubectl &> /dev/null; then
    echo "kubectl is installed. Setting up Bash completion..."
    echo 'source <(kubectl completion bash)' >> /home/clouduser/.bashrc
    echo "   -> Added permanent entry to /home/clouduser/.bashrc"
else
    echo "kubectl is NOT installed."
fi
}

# This script changed the configuration of the k3s audit logging
k3s_audit_config() {

mkdir -p /etc/rancher/k3s/config.yaml.d/

cat << 'EOF' >> /etc/rancher/k3s/config.yaml.d/audit.yaml
kube-apiserver-arg:
    - audit-log-maxbackup=1
    - audit-log-maxage=3
    - audit-log-maxsize=10
EOF

chmod 750 /etc/rancher/k3s/config.yaml.d/audit.yaml

}

sleep 5

echo "Starting RHSM registration script (Simple Content Access enabled) at $(date)"

RHSM_USERNAME="${rhsm_username}"
RHSM_PASSWORD="${rhsm_password}"

if [[ -z "$RHSM_USERNAME" || -z "$RHSM_PASSWORD" ]]; then
    echo "ERROR: RHSM username or password not provided. Skipping registration."
    exit 1
fi

echo "Attempting to register system with RHSM..."
# With Simple Content Access, --auto-attach is generally sufficient after registration.
subscription-manager register --username="$RHSM_USERNAME" --password="$RHSM_PASSWORD" --auto-attach || {
    echo "ERROR: RHSM registration failed."
    exit 1
}
echo "RHSM registration successful. Entitlements should be available via Simple Content Access."

echo "Refreshing subscriptions and updating yum/dnf metadata..."
subscription-manager refresh || echo "WARNING: Failed to refresh subscriptions."
yum makecache || dnf makecache || echo "WARNING: Failed to refresh package cache."

echo "RHSM registration script finished at $(date)"

echo "Starting LVM disk setup at $(date)"

# Install LVM2 utilities if not already present
echo "Installing lvm2..."
yum install -y lvm2 || dnf install -y lvm2 || { echo "ERROR: Failed to install lvm2."; exit 1; }
echo "lvm2 installed."

echo "Creating logical volumes..."
processed_disks=""

for disk in $(lsblk -o NAME,TYPE | grep disk | awk '{print $1}'); do
  if ! lsblk /dev/$disk | grep -q part; then
    echo "Processing /dev/$disk"
    parted /dev/$disk --script mklabel gpt
    parted /dev/$disk --script mkpart primary 0% 100%
    pvcreate /dev/$${disk}1
    processed_disks="$processed_disks /dev/$${disk}1"
  fi
done

if [ -n "$processed_disks" ]; then
  vgcreate vg_aiops $processed_disks
else
  echo "No disks were processed."
fi

lvcreate -L 119G -n lv_storage vg_aiops
lvcreate -L 119G -n lv_platform vg_aiops
lvcreate -L 24G -n lv_rancher vg_aiops
mkfs.xfs /dev/vg_aiops/lv_storage
mkfs.xfs /dev/vg_aiops/lv_platform
mkfs.xfs /dev/vg_aiops/lv_rancher
mkdir -p /var/lib/aiops/storage
mkdir -p /var/lib/aiops/platform
mkdir -p /var/lib/rancher
mount /dev/vg_aiops/lv_storage /var/lib/aiops/storage
mount /dev/vg_aiops/lv_platform /var/lib/aiops/platform
mount /dev/vg_aiops/lv_rancher /var/lib/rancher
echo "/dev/vg_aiops/lv_storage /var/lib/aiops/storage xfs defaults,nofail 0 2" | tee -a /etc/fstab
echo "/dev/vg_aiops/lv_platform /var/lib/aiops/platform xfs defaults,nofail 0 2" | tee -a /etc/fstab
echo "/dev/vg_aiops/lv_rancher /var/lib/rancher xfs defaults,nofail 0 2" | tee -a /etc/fstab

echo "All specified Logical Volumes created, formatted, mounted, and added to fstab."
echo "LVM disk setup finished at $(date)"

# k3s won't run with nm-cloud-setup enabled
systemctl stop nm-cloud-setup.timer
systemctl disable nm-cloud-setup.timer 
systemctl stop nm-cloud-setup.service
systemctl disable nm-cloud-setup.service

%{ if mode == "extended" }
# allow SELinux users to execute files that have been modified, this
# is needed for extended installation, if this is not set then the
# aimanager-aio-cr-api pods will CrashLoop due to selinux
setsebool -P selinuxuser_execmod 1
%{ endif }

curl -LO "https://github.com/IBM/aiopsctl/releases/download/v${aiops_version}/aiopsctl-linux_amd64.tar.gz"
tar xf "aiopsctl-linux_amd64.tar.gz"
mv aiopsctl /usr/local/bin/aiopsctl
rm -f aiopsctl-linux_amd64.tar.gz

# Get the initial SELinux status
SELINUX_INITIAL_STATE=$(getenforce)
echo "Initial SELinux state is: $SELINUX_INITIAL_STATE"

# Check if SELinux is enforcing and disable it temporarily because RHEL 8.10 
# SELinux policy prevents cloud-init from adding firewall rules
if [ "$SELINUX_INITIAL_STATE" = "Enforcing" ]; then
    echo "Disabling SELinux temporarily to apply firewall rules."
    setenforce 0
else
    echo "SELinux is not in 'enforcing' mode. Skipping temporary disable."
fi

echo "Opening firewall ports"
firewall-cmd --permanent --add-port=80/tcp # Application HTTP port
firewall-cmd --permanent --add-port=443/tcp # Application HTTPS port
firewall-cmd --permanent --add-port=6443/tcp # Control plane server API and mirrored registry
firewall-cmd --permanent --add-port=8472/udp # Virtual network
firewall-cmd --permanent --add-port=10250/tcp # k3s Kubelet metrics and logs (optional)
firewall-cmd --permanent --add-port=2379/tcp # k3s etcd client communication
firewall-cmd --permanent --add-port=2380/tcp # k3s etcd peer communication
firewall-cmd --permanent --add-port=51820/udp # Flannel + WireGuard (IPv4 traffic)
firewall-cmd --permanent --add-port=51821/udp # Flannel + WireGuard (IPv6 traffic)
firewall-cmd --permanent --add-port=5001/tcp # mirrored registry
firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16 # pods
firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16 # services
firewall-cmd --reload
#systemctl stop firewalld
#systemctl disable firewalld

# Re-enable SELinux only if it was originally enforcing
if [ "$SELINUX_INITIAL_STATE" = "Enforcing" ]; then
    echo "Re-enabling SELinux."
    setenforce 1
else
    echo "SELinux was not in 'enforcing' mode. No changes made."
fi

# optional
yum -y install bind-utils bash-completion

first_instance="${common_prefix}-k3s-server-0.${base_domain}"
instance_id=$(hostname)

# this is not being set automatically
export HOME=/root

# move to save disk space on /
mkdir -p /var/lib/aiops/storage/.aiopsctl
ln -s /var/lib/aiops/storage/.aiopsctl /root/.aiopsctl

k3s_install_params=("--accept-license=${accept_license}")
k3s_install_params+=("--role=control-plane")
k3s_install_params+=("--token=${k3s_token}")
%{ if use_private_registry }
k3s_install_params+=("--registry=${private_registry}")
k3s_install_params+=("--registry-user=${private_registry_user}")
k3s_install_params+=("--registry-token=${private_registry_user_password}")
k3s_install_params+=("--insecure-skip-tls-verify=${private_registry_skip_tls}")
k3s_install_params+=("--offline")
%{ else }
k3s_install_params+=("--registry-token=${ibm_entitlement_key}")
%{ endif }
k3s_install_params+=("--app-storage /var/lib/aiops/storage")
k3s_install_params+=("--platform-storage /var/lib/aiops/platform")
k3s_install_params+=("--image-storage /var/lib/aiops/storage")
k3s_install_params+=("--load-balancer-host=${k3s_url}")
%{ if ignore_prereqs } 
k3s_install_params+=("--force")
%{ endif }

INSTALL_PARAMS="$${k3s_install_params[*]}"

if [[ "$first_instance" == "$instance_id" ]]; then
  echo "Happy, happy, joy, joy: Cluster init!"

  if [[ "$install_k3s" == "true" ]]; then
    aiopsctl cluster node up $INSTALL_PARAMS
  else
    echo "Skipping install."
    exit 0
  fi

  # Check if SELinux is enforcing
  if [ "$(getenforce)" == "Enforcing" ]; then
    echo "SELinux is in Enforcing mode. Restoring context to k3s so it can start."
    # Restore the context on the file after it's installed
    restorecon -v "/usr/local/bin/k3s"
  else
    echo "SELinux is not in Enforcing mode. No action needed."
  fi

  disable_checksum_offload

  k3s_audit_config

  nonroot_config

  # wait for k3s startup
  until kubectl get pods -A | grep 'Running'; do
    echo 'Waiting for k3s startup'
    sleep 5
  done

  # Loop until all nodes are registered
  while true; do
    node_count=$(kubectl get nodes | tail -n +2 | wc -l)
    if [ "$node_count" -eq "$num_nodes" ]; then
      echo "Node count is $num_nodes - Exiting loop."
      break
    else
      echo "Current node count is $node_count. Waiting..."
      sleep 10  # Wait for 10 seconds before checking again
    fi
  done

  # update coredns for haproxy resolution
  kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  default.server: |
    cp-console-aiops.${k3s_url} {
        hosts {
              ${haproxy_ip} cp-console-aiops.${k3s_url}
              fallthrough
        }
    }
    aiops-cpd.${k3s_url} {
        hosts {
              ${haproxy_ip} aiops-cpd.${k3s_url}
              fallthrough
        }
    }
EOF
  kubectl -n kube-system rollout restart deployment coredns

  # additional sleep to make sure all nodes are up
  sleep 10

  # install aiops
  if [[ "$install_aiops" == "true" ]]; then

    # Certificate and key file paths
    CERT_FILE=/tmp/aiops-certificate-chain.pem
    KEY_FILE=/tmp/aiops.key.pem
    
    # Initialize an empty string for the optional parameters
    CERT_PARAMS=""

    # Check if both the certificate and key files exist
    if [[ -f "$CERT_FILE" && -f "$KEY_FILE" ]]; then
      CERT_PARAMS="--certificate-file $CERT_FILE --key-file $KEY_FILE"
    fi

    # Execute the aiopsctl command with the conditional parameters
    aiopsctl server up --load-balancer-host="${k3s_url}" --mode "${mode}" $CERT_PARAMS --force

    # make sure certificate was created
    CERT_SECRET_NAME="aiops-custom-certificate"
    AIOPS_NAMESPACE="aiops"

    # Check if the secret exists
    if ! kubectl get secret "$CERT_SECRET_NAME" -n "$AIOPS_NAMESPACE" >/dev/null 2>&1; then
      echo "Secret '$CERT_SECRET_NAME' not found in namespace '$AIOPS_NAMESPACE'."
      
      # Check if CERT_PARAMS is not empty
      if [[ -n "$CERT_PARAMS" ]]; then
        echo "CERT_PARAMS is set. Creating the custom certificate..."
        aiopsctl server custom-certificate $CERT_PARAMS
      else
        echo "CERT_PARAMS is empty. Skipping certificate creation."
      fi
    else
      echo "Secret '$CERT_SECRET_NAME' already exists in namespace '$AIOPS_NAMESPACE'."
    fi

    # clean up .aiopsctl
    rm -fr ~/.aiopsctl/
  fi

  # set up SA for k8s topology
  fn_configure_rbac_for_service_account

  # wait for k8ss SA token
  fn_wait_for_secret_token

  # load k8s topology
  fn_load_k8s_observer_job

  # give k8s observer time to run
  sleep 60
  
  # need entity types defined
  fn_create_topology_merge_rules

  fn_load_vcenter_observer_job
  # run observer job again after merge rules created
  fn_load_k8s_observer_job  

else
  echo ":( Cluster join"

  # nothing to do, exit
  if [[ "$install_k3s" == "false" ]]; then
    echo "Skipping install."
    exit 0
  fi

  wait_lb
  sleep 5
  aiopsctl cluster node up --server-url="https://$first_instance:6443" $INSTALL_PARAMS

  # Check if SELinux is enforcing
  if [ "$(getenforce)" == "Enforcing" ]; then
    echo "SELinux is in Enforcing mode. Restoring context to k3s so it can start."
    # Restore the context on the file after it's installed
    restorecon -v "/usr/local/bin/k3s"
  else
    echo "SELinux is not in Enforcing mode. No action needed."
  fi

  disable_checksum_offload

  k3s_audit_config

  nonroot_config

  # clean up .aiopsctl
  rm -fr ~/.aiopsctl/
fi

# Check if kubectl is installed and set up completion
if command -v kubectl &> /dev/null; then
    echo "kubectl is installed. Setting up Bash completion..."
    echo 'source <(kubectl completion bash)' >> ~/.bashrc
    echo "   -> Added permanent entry to ~/.bashrc"
else
    echo "kubectl is NOT installed."
fi

cat << 'EOF' >> ~/.bashrc

# Function to list unhealthy K8s pods by filtering out 'Completed' and 'Ready' states (e.g., '1/1')
kget_unhealthy_pods() {
  kubectl get pods -A | grep -vE "Completed|([0-9]+)/\1"
}

# enable vi on command line
set -o vi
# kubectl alias
alias k=kubectl
EOF