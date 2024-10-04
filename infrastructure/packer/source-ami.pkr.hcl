# Packer can't use for_each on a data source.

data "amazon-ami" "source-x86" {
  filters = {
    name                = replace(var.source_ami_name, "{{arch}}", "amd64")
    virtualization-type = var.virtualization_type
    root-device-type    = "ebs"
  }
  owners      = [var.source_ami_owner]
  most_recent = true
  region      = var.region
}

data "amazon-ami" "source-arm" {
  filters = {
    name                = replace(var.source_ami_name, "{{arch}}", "arm64")
    virtualization-type = var.virtualization_type
    root-device-type    = "ebs"
  }
  owners      = [var.source_ami_owner]
  most_recent = true
  region      = var.region
}

locals {
  source_ami_ids = {
    "x86" = data.amazon-ami.source-x86.id
    "arm" = data.amazon-ami.source-arm.id
  }
}
