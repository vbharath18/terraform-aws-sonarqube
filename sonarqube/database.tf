#---------------------------------------------------------------
# get database password
#---------------------------------------------------------------
data "aws_ssm_parameter" "db_pass" {
  name            = var.db_ssm_pw_loc
  with_decryption = true
}

#---------------------------------------------------------------
# database instance
#---------------------------------------------------------------
resource "aws_db_instance" "dbinstance" {
  name                            = var.db_name
  username                        = var.db_user
  password                        = data.aws_ssm_parameter.db_pass.value
  allocated_storage               = var.db_storage
  allow_major_version_upgrade     = var.db_major_version
  auto_minor_version_upgrade      = var.db_minor_version
  backup_retention_period         = var.db_backup_retain_days
  backup_window                   = var.db_backup_window
  copy_tags_to_snapshot           = var.db_snapshot_tags
  db_subnet_group_name            = aws_db_subnet_group.subnet_group.name
  enabled_cloudwatch_logs_exports = var.db_log_exports
  engine                          = "postgres"
  engine_version                  = var.db_engine_version
  identifier                      = var.db_name
  instance_class                  = var.db_machine
  maintenance_window              = var.db_maint_window
  max_allocated_storage           = var.db_max_storage
  monitoring_interval             = var.db_monitoring_interval
  multi_az                        = var.db_multi_az
  publicly_accessible             = var.db_public
  skip_final_snapshot             = var.db_skip_final_snap
  storage_encrypted               = var.db_encrypted
  storage_type                    = var.db_storage_type
  vpc_security_group_ids          = [aws_security_group.db_sg.id]
  tags = merge(
    var.common_tags,
    {
      "Name" = var.db_name
    }
  )
}

#---------------------------------------------------------------
# networking
#---------------------------------------------------------------
resource "aws_db_subnet_group" "subnet_group" {
  name       = "${var.db_name}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(
    var.common_tags,
    {
      "Name" = "${var.db_name}-subnet-group",
    },
  )
}

resource "aws_security_group" "db_sg" {
  name        = "${var.asg_prefix}-db-sg"
  description = "Allow postgres database Connections"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      "Name" = "${var.asg_prefix}-db-sg",
    },
  )
}

resource "aws_security_group_rule" "allow_postgres" {
  type        = "ingress"
  from_port   = 5432
  to_port     = 5432
  protocol    = "tcp"
  cidr_blocks = var.db_allowed_cidr
  description = "Allow access to postgress"

  security_group_id = aws_security_group.db_sg.id

}
