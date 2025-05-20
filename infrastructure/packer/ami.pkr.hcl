source "amazon-ebs" "yjit-dev" {
  ami_virtualization_type = var.virtualization_type
  region                  = var.region
  ssh_username            = var.ssh_username
  tags                    = var.tags

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = var.ami_volume_size_gb
    volume_type = "gp2"
    # Delete the device attached to this temporary instance after the AMI is made.
    delete_on_termination = true
  }
}

locals {
  ym_setup = "/tmp/ym-setup.sh"

  main_script = [
    "set -x",
    # Upgrade system.
    "sudo apt update -y && sudo apt upgrade -y",

    # Install a few useful dev tools.
    "sudo apt install -y ripgrep zsh && sudo chsh -s /bin/zsh ${var.ssh_username}",

    "chmod 0755 ${local.ym_setup} && ${local.ym_setup} cpu packages ruby",
    "mkdir -p ~/src && cd ~/src",
    "git clone https://github.com/Shopify/yjit-bench",

    # Auto-mount the reporting EBS volume when present.
    "sudo mkdir -p ${local.reporting_ebs_mount_point}",
    "echo \"LABEL=${local.reporting_ebs_device_label} ${local.reporting_ebs_mount_point} ${local.reporting_ebs_fs_type} defaults,nofail 0 2\" | sudo tee -a /etc/fstab",

    # Restrict ssh access to non-root user with key.
    "printf \"PasswordAuthentication no\nPermitRootLogin no\n\" | sudo tee /etc/ssh/sshd_config.d/99-custom.conf",

    # Install AWS client so the instance can easily do what is granted by its profile.
    # https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
    <<-EOF
    sudo bash -c '(cd /tmp
      curl "https://awscli.amazonaws.com/awscli-exe-linux-$(arch).zip" -o "awscliv2.zip"
      unzip awscliv2.zip
      ./aws/install
      aws --version
    rm -rf aws "awscliv2.zip")'
    EOF
  ]

  dev_script = [
    # Clone ruby to ~/src/ruby for manual development.
    # We already have yjit-bench.
    "git clone https://github.com/ruby/ruby",
  ]

  unwanted_packages = [
    "modemmanager",
    "unattended-upgrades",
    "update-notifier-common",
  ]

  unwanted_services = [
    "apt-daily.service",
    "apt-daily.timer",
    "apt-daily-upgrade.timer",
    "apt-daily-upgrade.service",
    "fwupd-refresh.timer",
    "logrotate.timer",
    "rsyslog",
  ]

  benchmark_script = [
    # All the yjit-metrics stuff looks for ~/ym.
    "ln -s ~/src ~/ym",

    # Setup the ruby clones and extra repos.
    "${local.ym_setup} repos",

    "sudo apt remove --auto-remove -y ${join(" ", local.unwanted_packages)}",
    "sudo systemctl disable --now ${join(" ", local.unwanted_services)}",

    # Symlink the expected names under ~/ym to the reporting ebs mount.
    # They will only be valid on the reporting instance,
    # but that's the only instance that will try to use them.
    "ln -s ${local.reporting_ebs_mount_point}/ghpages-yjit-metrics ~/ym/",
    "ln -s ${local.reporting_ebs_mount_point}/built-yjit-reports   ~/ym/",
  ]

  cleanup_script = [
    "rm ${local.ym_setup}",
    # These are just the packer temporary key, but may as well.
    "rm ~/.ssh/authorized_keys",
    "sudo rm /root/.ssh/authorized_keys",
  ]
}

build {
  name = "ami-bench"

  dynamic "source" {
    for_each = local.amis
    labels   = ["amazon-ebs.yjit-dev"]
    content {
      name          = "yjit-benchmarking.${source.key}"
      ami_name      = "yjit-benchmarking-${source.value.arch}-${local.timestamp}"
      instance_type = source.value.instance_type
      source_ami    = local.source_ami_ids[source.key]
      run_tags      = merge(var.tags, { Name = "YJIT Benchmarking ${local.timestamp}" })
    }
  }

  provisioner "file" {
    source      = "${local.yjit_metrics_path}/setup.sh"
    destination = local.ym_setup
  }

  provisioner "shell" {
    inline = concat(local.main_script, local.benchmark_script, local.cleanup_script)
  }
}

build {
  name = "ami-dev"

  dynamic "source" {
    for_each = local.amis
    labels   = ["amazon-ebs.yjit-dev"]
    content {
      name          = "yjit-dev.${source.key}"
      ami_name      = "yjit-dev-${source.value.arch}-${local.timestamp}"
      instance_type = source.value.instance_type
      source_ami    = local.source_ami_ids[source.key]
      run_tags      = merge(var.tags, { Name = "YJIT Dev ${local.timestamp}" })
    }
  }

  provisioner "file" {
    source      = "${local.yjit_metrics_path}/setup.sh"
    destination = local.ym_setup
  }

  provisioner "shell" {
    inline = concat(local.main_script, local.dev_script, local.cleanup_script)
  }
}
