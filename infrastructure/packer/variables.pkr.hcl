# For the AMI we only need enough for whatever we want to pre-install.
# A new volume size can be specified in the launch template or chosen at instance creation.
# The ubuntu source AMI is 8GB with less than 2GB being occupied.
# We install updates, some new packages, and >3GB in repos.
# The last build snapshot used 6.1GB.
# It can require more than 8GB temporarily, and then the yjit-raw data repo can
# take 7.5GB when switching branches.
variable "ami_volume_size_gb" {
  default = 16
}

variable "region" {
  default = "us-east-2" # Ohio is for lovers (it's also the cheapest place to run metal).
}

variable "reporting_availability_zone" {
  default = "us-east-2b"
}

variable "reporting_ebs_name" {
  default = "YJIT Benchmark Reporting Cache"
}

# As of 2024-09-17
# - the built report cache is 1.5GB
# - yjit-reports repo is 2.5GB
# 8GB is plenty. If we get low the yjit-reports really doesn't need to be on this volume.
variable "reporting_ebs_volume_size_gb" {
  default = 8
}

variable "ssh_username" {
  # This is defined by the source AMI.
  default = "ubuntu"
}

variable "source_ami_name" {
  default = "ubuntu/images/*ubuntu-noble-24.04-{{arch}}-server-*"
}

variable "source_ami_owner" {
  default = "099720109477" # Canonical
}

variable "tags" {
  default = {
    "Project" = "YJIT"
  }
}

variable "virtualization_type" {
  default = "hvm" # Must be 'hvm' for use with metal instance types.
}

# Set PKR_VAR_yjit_metrics_path=... to override.
# Default assumes "yjit-metrics" is checked out next to this repo.
variable "yjit_metrics_path" {
  default = ""
}

locals {
  timestamp         = regex_replace(timestamp(), "[- TZ:]", "")
  yjit_metrics_path = coalesce(var.yjit_metrics_path, "${path.root}/../../../yjit-metrics")

  # The instance type is for setting up the disk image that will become the AMI.
  # These should be smaller than but compatible with the desired target instance type.
  # /c7?.xlarge/ has 4 vCPU and 8GiB memory.
  amis = {
    "x86" = {
      arch            = "x86_64"
      source_ami_arch = "amd64"
      instance_type   = "c7i.xlarge" # compatible with c7i.metal-24xl.
    },
    "arm" = {
      arch            = "arm64"
      source_ami_arch = "arm64"
      instance_type   = "c8g.xlarge" # compatible with c8g.metal-24xl.
    }
  }

  reporting_ebs_device_label = "yjit-reportcache" # 16-char limit
  reporting_ebs_device_name  = "/dev/xvdf"
  reporting_ebs_mount_point  = "/yjit-report-cache"
  reporting_ebs_fs_type      = "ext4"
}
