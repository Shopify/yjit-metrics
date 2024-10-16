# Create key pair so jobs can SSH into the instances to run commands.
resource "aws_key_pair" "yjit-benchmarking" {
  key_name   = var.ssh_key_name
  public_key = var.ssh_public_key
}
