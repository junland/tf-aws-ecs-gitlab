data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_vpc" "selected" {
  id = local.vpc_id
}

data "aws_ssm_parameter" "ecs_ami" {
  count = var.ami_id == null ? 1 : 0
  name  = "/aws/service/bottlerocket/aws-ecs-2/x86_64/latest/image_id"
}

data "aws_subnet" "host" {
  id = local.private_subnet_ids[0]
}
