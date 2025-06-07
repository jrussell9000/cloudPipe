resource "aws_security_group" "efs" {
  name_prefix = "${var.name}-efs-sg"
  vpc_id      = module.vpc.vpc_id
  description = "Security group allowing ingress/egress rules required for EFS"
}

resource "aws_vpc_security_group_ingress_rule" "efs_ingress" {
  security_group_id = aws_security_group.efs.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 2049
  ip_protocol       = "tcp"
  to_port           = 2049
}

# EFS file system policy
resource "aws_iam_policy" "node_efs_policy" {
  name        = "${var.name}_node_efs_policy"
  path        = "/"
  description = "Policy for EKS nodes to use EFS"

  policy = jsonencode({
    "Statement" : [
      {
        "Action" : [
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:CreateAccessPoint",
          "elasticfilesystem:DeleteAccessPoint",
          "ec2:DescribeAvailabilityZones"
        ],
        "Effect" : "Allow",
        "Resource" : "*",
        "Sid" : ""
      }
    ],
    "Version" : "2012-10-17"
  })
}

# EFS file system
resource "aws_efs_file_system" "this" {
  creation_token = var.name
  lifecycle_policy {
    transition_to_ia = "AFTER_7_DAYS"
  }
}

# EFS Mount Points - one in each AZ
resource "aws_efs_mount_target" "efs_mount_targets_private_1" {
  file_system_id  = aws_efs_file_system.this.id
  security_groups = [aws_security_group.efs.id]
  subnet_id       = module.vpc.private_subnets[0]
}

resource "aws_efs_mount_target" "efs_mount_targets_private_2" {
  file_system_id  = aws_efs_file_system.this.id
  security_groups = [aws_security_group.efs.id]
  subnet_id       = module.vpc.private_subnets[1]
}

resource "aws_efs_mount_target" "efs_mount_targets_private_3" {
  file_system_id  = aws_efs_file_system.this.id
  security_groups = [aws_security_group.efs.id]
  subnet_id       = module.vpc.private_subnets[2]
}

#---------------------------------------------------------------
# Storage Class - EFS
#---------------------------------------------------------------
# Storageclasses cannot be updated, must be replaced
# Code below ensures storageclass is replaced every time, regardless of updates
# see https://stackoverflow.com/a/74944901
resource "terraform_data" "replacement" {
  input = timestamp()
}

resource "kubectl_manifest" "efs-storage-class" {
  yaml_body = templatefile("${path.module}/yamls/efs/efs-storageclass.yaml", {
    efs_id = aws_efs_file_system.this.id
  })

  lifecycle {
    replace_triggered_by = [
      terraform_data.replacement
    ]
  }
}
