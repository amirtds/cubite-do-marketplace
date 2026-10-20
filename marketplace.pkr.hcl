# Packer template for Cubite's DigitalOcean 1-Click image for the Open edX
# platform.
#
# Converted with `packer hcl2_upgrade` from marketplace-image.json in
# github.com/digitalocean/marketplace-partners at commit
# b70878804ca27c01d5f5e882d26485defbaba210, then adapted for the Open edX
# platform (Verawood) with Tutor 22.0.2 on Ubuntu 24.04.
#
# Build (from the repository root):
#   export DIGITALOCEAN_TOKEN=...   # a token for the team that owns the listing
#   packer init .
#   packer build marketplace.pkr.hcl
#
# Set the token only in the environment. Never pass it with -var or in a
# .pkrvars.hcl file, which put it in the shell history, ps output or on disk.
#
# A test build of the unpatched stock openedx image (see the security gate in
# scripts/01-openedx-installer.sh) needs -var allow_unpatched_openedx=true.
# Its snapshot name ends in -UNPATCHED-TEST and it must never be submitted.
#
# The build Droplet is the $6 s-1vcpu-1gb size, so the snapshot's minimum disk
# is 25 GB and every Droplet plan with enough memory can use the image.
# Nothing Tutor-specific runs here: no Tutor config, no secrets, no Docker
# images. Each Droplet creates its own at first boot and first login.

packer {
  required_version = ">= 1.10.0"
  required_plugins {
    digitalocean = {
      version = ">= 1.4.2, < 2.0.0"
      source  = "github.com/digitalocean/digitalocean"
    }
  }
}

variable "do_token" {
  type        = string
  default     = env("DIGITALOCEAN_TOKEN")
  sensitive   = true
  description = "DigitalOcean API token, read from the DIGITALOCEAN_TOKEN environment variable. Set only DIGITALOCEAN_TOKEN in the environment; never pass the token with -var or a .pkrvars.hcl file, and never write it into a file in this repository."

  validation {
    condition     = length(var.do_token) > 0
    error_message = "Set the DIGITALOCEAN_TOKEN environment variable to a token for the team that owns the Vendor Portal listing."
  }
}

variable "allow_unpatched_openedx" {
  type        = bool
  default     = false
  description = "Test builds only. With Tutor 22.0.0 to 22.0.2 and no files/opt/cubite/openedx-image.env, the installer refuses to build, because the stock overhangio/openedx image lacks the fixes for GHSA-c6xg-fh3c-vvhh and GHSA-c6fp-f54c-6cv4. true builds anyway and names the snapshot ...-UNPATCHED-TEST; such a snapshot must never be submitted."
}

locals {
  # Snapshot names are the only thing the Vendor Portal picker shows, so they
  # are stamped to the minute (UTC), and a test build of the unpatched stock
  # openedx image says so in its name.
  build_time    = formatdate("YYYYMMDD-hhmm", timestamp())
  name_suffix   = var.allow_unpatched_openedx ? "-UNPATCHED-TEST" : ""
  snapshot_name = "cubite-openedx-verawood-tutor22-2404-${local.build_time}${local.name_suffix}"
}

# Region: on 2026-10-19 nyc1 and nyc3 offered no basic s- sizes to this
# account; tor1 offers both the s-1vcpu-1gb build size and the s-4vcpu-8gb
# test size.
source "digitalocean" "openedx" {
  api_token          = var.do_token
  image              = "ubuntu-24-04-x64"
  region             = "tor1"
  size               = "s-1vcpu-1gb"
  ssh_username       = "root"
  droplet_name       = "cubite-openedx-build-${local.build_time}"
  snapshot_name      = local.snapshot_name
  droplet_agent      = false
  monitoring         = false
  ipv6               = false
  private_networking = false
}

build {
  name    = "cubite-openedx"
  sources = ["source.digitalocean.openedx"]

  # Wait for cloud-init so apt is free. On Ubuntu 24.04 it exits 2 because
  # DigitalOcean's vendor-data fails cloud-init's strict schema check, even on
  # DigitalOcean's own images (marketplace-partners issue #186, open), so 2
  # counts as finished.
  provisioner "shell" {
    inline           = ["cloud-init status --wait"]
    valid_exit_codes = [0, 2]
  }

  provisioner "file" {
    source      = "files/etc/"
    destination = "/etc/"
  }

  provisioner "file" {
    source      = "files/opt/"
    destination = "/opt/"
  }

  provisioner "file" {
    source      = "files/var/"
    destination = "/var/"
  }

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "LC_ALL=C",
      "LANG=en_US.UTF-8",
      "LC_CTYPE=en_US.UTF-8",
      "CUBITE_ALLOW_UNPATCHED=${var.allow_unpatched_openedx}",
    ]
    scripts = [
      "scripts/01-openedx-installer.sh",
      "scripts/02-ufw-openedx.sh",
      "scripts/90-cleanup.sh",
    ]
  }

  # 90-cleanup.sh empties the logs and then zero-fills the disk for about a
  # minute and a half, while the kernel keeps logging (mostly ufw blocking
  # internet scanners), so 99-img-check.sh warned about an un-cleared
  # /var/log/kern.log. Stop the system logger (and the socket that would
  # restart it) for the rest of the build, then empty the top-level logs
  # again. rsyslog starts normally on each Droplet's first boot.
  provisioner "shell" {
    inline = [
      "systemctl stop syslog.socket rsyslog.service",
      "find /var/log -maxdepth 1 -type f -name '*.log' -exec truncate -s 0 {} +",
    ]
  }

  # 99-img-check.sh must stay the very last script.
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "LC_ALL=C",
      "LANG=en_US.UTF-8",
      "LC_CTYPE=en_US.UTF-8",
    ]
    scripts = ["scripts/99-img-check.sh"]
  }

  # Records the snapshot ID (artifact_id is "<region>:<snapshot id>").
  # manifest.json is git-ignored.
  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
    custom_data = {
      snapshot_name = local.snapshot_name
    }
  }
}
