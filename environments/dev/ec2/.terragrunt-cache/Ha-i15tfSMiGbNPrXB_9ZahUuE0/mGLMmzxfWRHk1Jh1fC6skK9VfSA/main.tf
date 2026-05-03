resource "aws_instance" "main" {
  for_each = var.instances

  ami                    = data.aws_ami.ubuntu_22.id
  instance_type          = each.value.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.iam_instance_profile

  monitoring    = true
  ebs_optimized = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name        = each.key
    Environment = var.environment
  }
}