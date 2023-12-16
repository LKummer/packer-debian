packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.6"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "preseed_url" {
  description = "Preseed file URL."
  type        = string
  default     = "http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg"
}

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
Debian Linux cloud image with QEMU guest agent and cloud-init.
https://git.houseofkummer.com/homelab/devops/packer-debian
EOF
}

source "proxmox-iso" "debian" {
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  iso_storage_pool = "local"
  iso_url          = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.4.0-amd64-netinst.iso"
  iso_checksum     = "64d727dd5785ae5fcfd3ae8ffbede5f40cca96f1580aaa2820e8b99dae989d94"

  template_name        = "${var.template_name}${var.template_name_suffix}"
  template_description = var.template_description

  unmount_iso = true

  scsi_controller = "virtio-scsi-single"
  os              = "l26"
  qemu_agent      = true

  memory = 2048
  cores  = 2

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  disks {
    type         = "scsi"
    disk_size    = "10G"
    storage_pool = "local-lvm"
    format       = "raw"
    io_thread    = true
  }

  http_directory = "http"
  ssh_username   = "root"
  ssh_password   = "packer"
  ssh_port       = 22
  ssh_timeout    = "10m"

  boot_wait = "10s"
  boot_command = [
    "<esc><wait>",
    "auto url=${var.preseed_url}<enter>"
  ]

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
    content     = <<EOF
growpart:
  devices:
    - '/dev/sda2'
    - '/dev/sda6'
EOF
    destination = "/etc/cloud/cloud.cfg.d/99_growpart.cfg"
  }
}
