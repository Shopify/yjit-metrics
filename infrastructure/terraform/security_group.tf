locals {
  all_ipv4 = "0.0.0.0/0"
  all_ipv6 = "::/0"
}

resource "aws_security_group" "allow_ssh" {
  name        = "yjit-allow-ssh"
  description = "Allow SSH inbound traffic and all outbound traffic"

  tags = {
    Name = "yjit-allow-ssh"
  }
}

# Allow SSH connections to each instance to enable commands to be run.
resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv4" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv4         = local.all_ipv4
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_ipv6" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv6         = local.all_ipv6
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

# Allow all outbound traffic.
resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv4         = local.all_ipv4
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv6" {
  security_group_id = aws_security_group.allow_ssh.id
  cidr_ipv6         = local.all_ipv6
  ip_protocol       = "-1" # semantically equivalent to all ports
}
