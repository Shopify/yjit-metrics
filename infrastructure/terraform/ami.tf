# AMIs should be pre-built by packer.
# We _could_ import them here
# but it's nice to be able to tear down the terraform while keeping the AMIs.

data "aws_ami" "yjit-benchmarking" {
  for_each    = local.amis
  owners      = ["self"]
  most_recent = true

  dynamic "filter" {
    for_each = {
      name                  = replace(var.benchmarking_ami_name_pattern, "{{arch}}", each.value.arch)
      architecture          = each.value.arch
      "root-device-type"    = "ebs"
      "virtualization-type" = var.virtualization_type
    }

    content {
      name   = filter.key
      values = [filter.value]
    }
  }
}
