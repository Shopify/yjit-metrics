locals {
  init_script_template = file("yjit-metrics-init-script.sh")

  # Since this is a shell script (with lots of $vars) it would be awkward to use
  # a templatestring here so just use one replace call to pass in the vars.
  init_script = replace(
    local.init_script_template,
    "{{vars}}",
    join("\n", [
      "region='${var.region}'",
      "secret_name='${var.secret_name}'",
    ])
  )

  user_data = base64encode(
    # Use a multipart template to enable the option
    # for running the script at every boot.
    templatefile("user-data-multipart.tmpl", {
      user_data = local.init_script
    })
  )

  monitoring = false
}

# Put all the parameters in a launch template to simplify creation of instances
# so that only overrides need to be specified.
resource "aws_launch_template" "yjit-metrics" {
  for_each = local.amis
  name     = "${var.launch_template_name}-${each.key}"

  # The ami could be a paramter in SSM that can be managed independently
  # (that could be set elsewhere in the terraform) but if we are running
  # terraform to set the value either way it doesn't really help anything.
  image_id = data.aws_ami.yjit-benchmarking[each.key].id

  instance_type = each.value.instance_type
  key_name      = aws_key_pair.yjit-benchmarking.key_name
  user_data     = local.user_data

  block_device_mappings {
    device_name = var.root_device_name
    ebs {
      volume_size = var.benchmarking_volume_size_gb
    }
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.yjit-benchmarking.arn
  }
  metadata_options {
    instance_metadata_tags = "enabled"
  }
  monitoring {
    enabled = local.monitoring
  }

  vpc_security_group_ids = [aws_security_group.allow_ssh.id]
}

# Create the main benchmarking instances, one x86 and one arm, that will live in
# AWS, be started for the job, and then stopped when the job is complete.
resource "aws_instance" "benchmarking" {
  for_each = local.amis
  tags     = merge(var.tags, { Name = "yjit-benchmarking-${each.key}" })

  launch_template {
    id = aws_launch_template.yjit-metrics[each.key].id
  }

  # Changes to the launch template won't necessarily propagate to existing
  # instances (but may show up in the terraform plan as changes that never seem
  # to get applied).  If you desire to do so you may need to copy those values here:
  user_data = aws_launch_template.yjit-metrics[each.key].user_data
  instance_type = aws_launch_template.yjit-metrics[each.key].instance_type
}

# Create a separate instance for running the report aggregation
# that is smaller and cheaper than a metal instance.
# This will be started after the benchmarks on the other servers are completed
# (as they may complete after different durations).
resource "aws_instance" "reporting" {
  instance_type = var.reporting_instance_type
  tags          = merge(var.tags, { Name = "yjit-reporting" })

  # Needs to be in the same AZ as the EBS.
  availability_zone = data.aws_ebs_volume.reporting-ebs.availability_zone

  launch_template {
    id = aws_launch_template.yjit-metrics["x86"].id
  }
  root_block_device {
    volume_size = var.reporting_root_volume_size_gb
  }

  # Copy launch template values to avoid shifting plans (see above).
  user_data = aws_launch_template.yjit-metrics["x86"].user_data
}
