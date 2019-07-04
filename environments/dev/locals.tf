locals {
	stack = {
		name = "wordpress"
		
		vpc = {
			cidr = "10.0.0.0/16"
			azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  			private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  			public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
		}

		wordpress_node = {
			image_id =  "ami-0c6b1d09930fac512"
			instance_type = "t2.micro"
			root_volume_size = "50"
			root_volume_type = "gp2"
			min_size = 0
  			max_size = 1
 		 	desired_capacity = 1
		}

		wordpress_rds = {
			name = "wordpress_mysql"
			type = "mysql"
			version = "5.7.19"
			instance_type = "db.t2.micro"
			username = "wordpress_user"
  			password = "YourPwdShouldBeLongAndSecure!"
		}
	}
	
	tag = {
		owner = "quangpm"
		env   = "dev"
	}
}