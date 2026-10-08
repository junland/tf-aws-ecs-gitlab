data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_ssm_parameter" "ecs_ami" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

data "aws_subnet" "host" {
  id = local.private_subnet_ids[0]
}
