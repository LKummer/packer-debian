variable "proxmox_node" {
  description = "Proxmox node ID to create the template on."
  type        = string
}

variable "template_name" {
  description = "Name of the created template."
  type        = string
  default     = "debian"
}

variable "template_name_suffix" {
  description = "Suffix added to template_name, used to add Git commit hash or tag to template name."
  type        = string
  default     = ""
}

variable "template_description" {
  description = "Description of the created template."
  type        = string
  default     = <<EOF
Alpine Linux cloud image with QEMU guest agent, cloud-init and Python.
https://git.houseofkummer.com/homelab/devops/packer-alpine
EOF
}

source "proxmox-iso" "debian" {
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  iso_storage_pool = "local"
  iso_url          = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.6.0-amd64-netinst.iso"
  iso_checksum     = "224cd98011b9184e49f858a46096c6ff4894adff8945ce89b194541afdfd93b73b4666b0705234bd4dff42c0a914fdb6037dd0982efb5813e8a553d8e92e6f51"

  template_name        = "${var.template_name}${var.template_name_suffix}"
  template_description = var.template_description

  unmount_iso = true

  scsi_controller = "virtio-scsi-pci"
  os              = "l26"
  qemu_agent      = true

  memory   = 2048
  cores    = 2

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  disks {
    type              = "scsi"
    disk_size         = "10G"
    storage_pool      = "local-lvm"
    storage_pool_type = "lvm-thin"
    format            = "raw"
  }

  http_directory = "http"
  ssh_username = "root"
  ssh_password = "packer"
  ssh_port     = 22
  ssh_timeout  = "10m"

  boot_wait    = "10s"
  boot_command = ["<esc><wait>auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter>"] 

  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"
}

build {
  sources = ["source.proxmox-iso.debian"]

  provisioner "shell" {
    inline = [
      "apt-get install --yes python3-pip",
      "passwd --lock root",
      "echo PasswordAuthentication no >> /etc/ssh/sshd_config"
    ]
  }

  provisioner "file" {
    content = <<EOF
growpart:
  devices:
    - '/dev/sda2'
    - '/dev/sda6'
EOF
    destination = "/etc/cloud/cloud.cfg.d/99_growpart.cfg"
  }
}
