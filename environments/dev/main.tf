resource "aws_key_pair" "sshkey" {
  key_name   = local.tag.owner
  public_key = "${file("${path.root}/data/credentials/${local.tag.owner}.pub")}"
}

module "vpc" {
  source = "../../modules/terraform-aws-vpc"

  name = local.stack.name
  cidr = local.stack.vpc.cidr

  azs             = local.stack.vpc.azs
  private_subnets = local.stack.vpc.private_subnets
  public_subnets  = local.stack.vpc.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Owner = local.tag.owner
    Environment = local.tag.env
    Name = local.stack.name
  }
}

module "sg-wordpress-elb" {
  source = "../../modules/terraform-aws-security-group"

  name = "     wordpress-elb"
  vpc_id  = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      rule        = "http-80-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
  egress_with_cidr_blocks = [
    {
      rule        = "all-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}


module "sg-wordpress-node" {
  source = "../../modules/terraform-aws-security-group"

  name = "wordpress-node"
  vpc_id  = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule        = "http-80-tcp"
      source_security_group_id = module.sg-wordpress-elb.this_security_group_id
    },
  ]
  egress_with_cidr_blocks = [
    {
      rule        = "all-tcp"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

module "sg-wordpress-rds-mysql" {
  source = "../../modules/terraform-aws-security-group"

  name = "wordpress-rds-mysql"
  vpc_id  = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule        = "mysql-tcp"
      source_security_group_id = module.sg-wordpress-node.this_security_group_id
    },
  ]
}

module "rds-mysql-wordpress" {
  source  = "../../modules/terraform-aws-rds"

  identifier = replace(local.stack.wordpress_rds.name,"_","")

  engine            = local.stack.wordpress_rds.type
  engine_version    = "5.7.19"
  instance_class    = local.stack.wordpress_rds.instance_type
  allocated_storage = 10

  name     = local.stack.wordpress_rds.name
  username = local.stack.wordpress_rds.username
  password = local.stack.wordpress_rds.password
  port     = "3306"

  iam_database_authentication_enabled = false

  vpc_security_group_ids = [module.sg-wordpress-rds-mysql.this_security_group_id]

  maintenance_window = "Mon:00:00-Mon:03:00"
  backup_window      = "03:00-06:00"

  #monitoring_interval = "30"
  #monitoring_role_name = "MyRDSMonitoringRole"
  create_monitoring_role = false

  tags = {
    Owner = local.tag.owner
    Environment = local.tag.env
    Name = local.stack.name
  }

  subnet_ids = module.vpc.private_subnets
  family = "mysql5.7"
  major_engine_version = "5.7"

  # Snapshot name upon DB deletion
  # final_snapshot_identifier = "demodb"

  deletion_protection = false

  parameters = [
    {
      name = "character_set_client"
      value = "utf8"
    },
    {
      name = "character_set_server"
      value = "utf8"
    }
  ]
}

data "template_file" "launch-configuration-wordpress_node" {
  template = "${file("${path.module}/data/launch-configs/aws_launch_config_wordpress_node.tpl")}"

  vars = {
    WORDPRESS_DB_HOST = module.rds-mysql-wordpress.this_db_instance_address
    WORDPRESS_DB_NAME = module.rds-mysql-wordpress.this_db_instance_name
    WORDPRESS_DB_USER = module.rds-mysql-wordpress.this_db_instance_username
    WORDPRESS_DB_PASSWORD = module.rds-mysql-wordpress.this_db_instance_password
  }

}

module "asg" {
  source = "../../modules/terraform-aws-autoscaling"
  name = local.stack.name

  key_name = aws_key_pair.sshkey.id
  lc_name = local.stack.name
  image_id = local.stack.wordpress_node.image_id
  instance_type = local.stack.wordpress_node.instance_type
  security_groups = [module.sg-wordpress-node.this_security_group_id]
  // load_balancers = [module.elb.this_elb_id]

  root_block_device = [
    {
      volume_size = local.stack.wordpress_node.root_volume_size
      volume_type = local.stack.wordpress_node.root_volume_type
    },
  ]

  asg_name                  = local.stack.name
  vpc_zone_identifier       = module.vpc.private_subnets
  health_check_type         = "EC2"
  min_size                  = local.stack.wordpress_node.min_size
  max_size                  = local.stack.wordpress_node.max_size
  desired_capacity          = local.stack.wordpress_node.desired_capacity
  wait_for_capacity_timeout = 0

  user_data                 = "${data.template_file.launch-configuration-wordpress_node.rendered}"

  tags = [
    {
      key                 = "Environment"
      value               = local.tag.env
      propagate_at_launch = true
    },
    {
      key                 = "Owner"
      value               = local.tag.owner
      propagate_at_launch = true
    },
  ]

}

module "elb" {
  source = "../../modules/terraform-aws-elb"
  name = local.stack.name

  subnets         = module.vpc.public_subnets
  security_groups = [module.sg-wordpress-elb.this_security_group_id]
  internal        = false

  listener = [
    {
      instance_port     = "80"
      instance_protocol = "HTTP"
      lb_port           = "80"
      lb_protocol       = "HTTP"
    },
  ]

  health_check = {
    target              = "TCP:80"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  tags = {
    Owner = local.tag.owner
    Environment = local.tag.env
    Name = local.stack.name
  }
}
