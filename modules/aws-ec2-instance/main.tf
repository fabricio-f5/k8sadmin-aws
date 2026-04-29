resource "aws_instance" "main" {
    ami                    = data.aws_ssm_parameter.ami_id.value
    instance_type          = var.instance_type
    key_name               = data.aws_ssm_parameter.key_name.value
    subnet_id              = var.subnet_id
    vpc_security_group_ids = [var.vpc_security_group_id]
    iam_instance_profile   = var.iam_instance_profile
    monitoring             = true
    ebs_optimized          = true
    metadata_options {
        http_endpoint               = "enable"
        http_tokens                 = "required"
        http_out_response_hop_limit = 1
    }
    root_block_device {
        encrypted = true
    }
    tags = {
        name = var.instance_name
    }
}