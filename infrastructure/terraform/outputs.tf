# Create outputs for anything we might want to reference elsewhere.

# The jobs will need to be able to start the benchmarking instances.
output "benchmarking-instance-x86-id" {
  value = aws_instance.benchmarking["x86"].id
}

output "benchmarking-instance-arm-id" {
  value = aws_instance.benchmarking["arm"].id
}

# The jobs will need to be able to create new instances from the launch template.
output "benchmarking-launch-template-x86-id" {
  value = aws_launch_template.yjit-metrics["x86"].id
}

output "benchmarking-launch-template-arm-id" {
  value = aws_launch_template.yjit-metrics["arm"].id
}

# The jobs will need to be able to start the reporting instance.
output "reporting-instance-id" {
  value = aws_instance.reporting.id
}
