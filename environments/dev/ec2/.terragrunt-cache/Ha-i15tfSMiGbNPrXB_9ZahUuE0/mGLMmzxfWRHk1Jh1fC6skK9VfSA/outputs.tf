output "instance_ids" {
  description = "IDs das instâncias EC2"
  value = {
    for k, v in aws_instance.main : k => v.id
  }
}

output "public_ips" {
  description = "IPs públicos das instâncias"
  value = {
    for k, v in aws_instance.main : k => v.public_ip
  }
}

output "private_ips" {
  description = "IPs privados das instâncias"
  value = {
    for k, v in aws_instance.main : k => v.private_ip
  }
}

