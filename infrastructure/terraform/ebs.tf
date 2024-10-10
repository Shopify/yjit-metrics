# EBS volume should be pre-built by packer.
# Don't import (or declare a resource for) reporting EBS
# as it contains cache data that can't be (easily) recovered
# (so we wouldn't want it to be automatically destroyed
# if we destroy this whole terraform module).

data "aws_ebs_volume" "reporting-ebs" {
  most_recent = true

  filter {
    name   = "volume-type"
    values = ["gp2"]
  }

  filter {
    name   = "tag:Name"
    values = [var.reporting_ebs_name]
  }
}

resource "aws_volume_attachment" "reporting-ebs" {
  volume_id   = data.aws_ebs_volume.reporting-ebs.id
  instance_id = aws_instance.reporting.id
  device_name = local.reporting_ebs_device_name
}
