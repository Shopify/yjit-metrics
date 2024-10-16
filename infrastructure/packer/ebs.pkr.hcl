source "amazon-ebsvolume" "yjit-reporting" {
  region        = var.region
  ssh_username  = var.ssh_username
  instance_type = "t2.medium"
  source_ami    = data.amazon-ami.source-x86.id

  availability_zone = var.reporting_availability_zone

  ebs_volumes {
    volume_type           = "gp2"
    device_name           = local.reporting_ebs_device_name
    delete_on_termination = false
    tags                  = merge(var.tags, { Name = var.reporting_ebs_name })
    volume_size           = var.reporting_ebs_volume_size_gb
  }
}

build {
  name = "reporting-ebs"

  sources = [
    "sources.amazon-ebsvolume.yjit-reporting"
  ]

  provisioner "shell" {
    inline = [
      "lsblk", # debug

      # Format the device.
      "sudo mkfs -t '${local.reporting_ebs_fs_type}' '${local.reporting_ebs_device_name}'",
      # Label it so we can find it in fstab.
      "sudo e2label '${local.reporting_ebs_device_name}' '${local.reporting_ebs_device_label}'",

      # Mount it.
      "sudo mkdir -p '${local.reporting_ebs_mount_point}'",
      "sudo mount '${local.reporting_ebs_device_name}' '${local.reporting_ebs_mount_point}'",
      "sudo chown $(id -u):$(id -g) '${local.reporting_ebs_mount_point}'",
      "cd '${local.reporting_ebs_mount_point}'",

      # This repo is open source and publicly readable.
      # A token for pushing to yjit-raw repos will be provided to the reporting instance that uses this volume.
      "git clone --branch pages https://github.com/yjit-raw/yjit-reports.git",
      # Symlink to provide the name that yjit-metrics expects.
      "ln -s yjit-reports ghpages-yjit-metrics",

      # This needs to be copied over from the existing instance manually.
      "mkdir -p built-yjit-reports",
    ]
  }
}
