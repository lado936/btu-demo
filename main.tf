provider "aws" {
  region = var.aws_region
  #access_key ="API_ACCESS_KEY"
  #secret_key ="API_SECRET_KEY"
  profile = "btu"
}

## Network

resource "aws_vpc" "terra_vpc" {
  cidr_block       = var.vpc_cidr
  instance_tenancy = "default"

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "terra_ingress_subnet_az_1" {
  vpc_id                  = aws_vpc.terra_vpc.id
  cidr_block              = var.ingress_subnet_az_1_CIDR
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = "true"

  tags = {
    Name = "Ingress Subnet 1"
  }

  depends_on = [
    "aws_vpc.terra_vpc"
  ]
}

resource "aws_subnet" "terra_ingress_subnet_az_2" {
  vpc_id                  = aws_vpc.terra_vpc.id
  cidr_block              = var.ingress_subnet_az_2_CIDR
  availability_zone       = "eu-central-1b"
  map_public_ip_on_launch = "true"

  tags = {
    Name = "Ingress Subnet 2"
  }

  depends_on = [
    "aws_vpc.terra_vpc"
  ]
}

resource "aws_subnet" "terra_private_subnet_az_1" {
  vpc_id            = aws_vpc.terra_vpc.id
  cidr_block        = var.private_subnet_az_1_CIDR
  availability_zone = "eu-central-1a"

  tags = {
    Name = "Application Subnet 1"
  }

  depends_on = [
    "aws_vpc.terra_vpc"
  ]
}

resource "aws_subnet" "terra_private_subnet_az_2" {
  vpc_id            = aws_vpc.terra_vpc.id
  cidr_block        = var.private_subnet_az_2_CIDR
  availability_zone = "eu-central-1b"

  tags = {
    Name = "Application Subnet 2"
  }

  depends_on = [
    "aws_vpc.terra_vpc"
  ]
}

resource "aws_security_group" "demo_terra_alb_sg" {
  name        = "demo_terra_alb_sg"
  description = "Allow all inbound traffic"
  vpc_id      = aws_vpc.terra_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.private_subnet_az_1_CIDR}"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.private_subnet_az_2_CIDR}"]
  }

  tags = {
    Name = "demo_terra_alb_sg"
  }

  depends_on = [
    "aws_vpc.terra_vpc"
  ]
}

resource "aws_security_group" "terra_app_server_sg" {
  name        = "terra_app_server_sg"
  description = "Allow all inbound traffic"
  vpc_id      = aws_vpc.terra_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.ingress_subnet_az_1_CIDR}"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.ingress_subnet_az_2_CIDR}"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.ingress_subnet_az_1_CIDR}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terra_app_server_sg"
  }

  depends_on = [
    "aws_vpc.terra_vpc"
  ]
}

resource "aws_security_group" "terra_bastion_sg" {
  name        = "terra_bastion_sg"
  description = "Allow all inbound traffic"
  vpc_id      = aws_vpc.terra_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.bastion_ssh_from}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terra_bastion_sg"
  }

  depends_on = [
    "aws_vpc.terra_vpc"
  ]
}

resource "aws_launch_configuration" "terra_bastion_lc" {
  name_prefix     = "terraform-bastion-"
  image_id        = "ami-0db9040eb3ab74509"
  instance_type   = "t2.micro"
  key_name        = var.key_name
  security_groups = ["${aws_security_group.terra_bastion_sg.id}"]

  lifecycle {
    create_before_destroy = true
  }




  depends_on = [
    "aws_security_group.terra_bastion_sg"
  ]
}

resource "aws_autoscaling_group" "terra-bastion" {
  name                 = "terraform-bastion-asg"
  launch_configuration = aws_launch_configuration.terra_bastion_lc.name
  min_size             = 1
  max_size             = 1
  vpc_zone_identifier  = ["${aws_subnet.terra_ingress_subnet_az_1.id}"]

  lifecycle {
    create_before_destroy = true
  }
  tag {
    propagate_at_launch = true
    key                 = "Name"
    value               = "Bastion"

  }
  depends_on = [
    "aws_launch_configuration.terra_bastion_lc",
    "aws_subnet.terra_ingress_subnet_az_1",
  ]
}

resource "aws_alb_target_group" "terra_alb_target_group" {
  name     = "demo-terra-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.terra_vpc.id

  depends_on = [
    "aws_vpc.terra_vpc"
  ]
}

resource "aws_alb" "terra_alb" {
  name               = "demo-terra-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.demo_terra_alb_sg.id}"]
  subnets            = ["${aws_subnet.terra_ingress_subnet_az_1.id}", "${aws_subnet.terra_ingress_subnet_az_2.id}"]

  enable_deletion_protection = false

  tags = {
    Environment = "production"
  }

  depends_on = [
    "aws_security_group.demo_terra_alb_sg",
    "aws_subnet.terra_ingress_subnet_az_1",
    "aws_subnet.terra_ingress_subnet_az_2"
  ]
}

resource "aws_alb_listener" "terra_alb_listener" {
  load_balancer_arn = aws_alb.terra_alb.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.terra_alb_target_group.id
    type             = "forward"
  }

  depends_on = [
    "aws_alb.terra_alb",
    "aws_alb_target_group.terra_alb_target_group"
  ]
}

resource "aws_internet_gateway" "terra_gw" {
  vpc_id = aws_vpc.terra_vpc.id

  depends_on = [
    "aws_vpc.terra_vpc"
  ]
}

resource "aws_route_table" "ingress_route_table" {
  vpc_id = aws_vpc.terra_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terra_gw.id
  }

  depends_on = [
    "aws_vpc.terra_vpc",
    "aws_internet_gateway.terra_gw"
  ]
}

resource "aws_route_table_association" "ingress_route_table_assoc_az_1" {
  count          = var.az_count
  subnet_id      = aws_subnet.terra_ingress_subnet_az_1.id
  route_table_id = aws_route_table.ingress_route_table.id

  depends_on = [
    "aws_subnet.terra_ingress_subnet_az_1",
    "aws_route_table.ingress_route_table",
  ]
}

resource "aws_route_table_association" "ingress_route_table_assoc_az_2" {
  count          = var.az_count
  subnet_id      = aws_subnet.terra_ingress_subnet_az_2.id
  route_table_id = aws_route_table.ingress_route_table.id

  depends_on = [
    "aws_subnet.terra_ingress_subnet_az_2",
    "aws_route_table.ingress_route_table"
  ]
}

resource "aws_eip" "nat_1" {
  vpc                       = true
  associate_with_private_ip = var.ingress_subnet_az_1_nat_ip
}

resource "aws_eip" "nat_2" {
  vpc                       = true
  associate_with_private_ip = var.ingress_subnet_az_2_nat_ip
}

resource "aws_nat_gateway" "gw_1" {
  allocation_id = aws_eip.nat_1.id
  subnet_id     = aws_subnet.terra_ingress_subnet_az_1.id

  tags = {
    Name = "gw NAT 1"
  }
}

resource "aws_nat_gateway" "gw_2" {
  allocation_id = aws_eip.nat_2.id
  subnet_id     = aws_subnet.terra_ingress_subnet_az_2.id

  tags = {
    Name = "gw NAT 2"
  }
}

resource "aws_route_table" "app_route_table_1" {
  vpc_id = aws_vpc.terra_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.gw_1.id
  }

  depends_on = [
    "aws_vpc.terra_vpc",
    "aws_nat_gateway.gw_1"
  ]
}

resource "aws_route_table_association" "app_route_table_assoc_az_1" {
  count          = var.az_count
  subnet_id      = aws_subnet.terra_private_subnet_az_1.id
  route_table_id = aws_route_table.app_route_table_1.id

  depends_on = [
    "aws_subnet.terra_private_subnet_az_1",
    "aws_route_table.app_route_table_1"
  ]
}

resource "aws_route_table" "app_route_table_2" {
  vpc_id = aws_vpc.terra_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.gw_2.id
  }

  depends_on = [
    "aws_vpc.terra_vpc",
    "aws_nat_gateway.gw_2"
  ]
}

resource "aws_route_table_association" "app_route_table_assoc_az_2" {
  count          = var.az_count
  subnet_id      = aws_subnet.terra_private_subnet_az_2.id
  route_table_id = aws_route_table.app_route_table_2.id

  depends_on = [
    "aws_subnet.terra_private_subnet_az_2",
    "aws_route_table.app_route_table_2"
  ]
}

## Compute


resource "aws_launch_configuration" "terra_lc" {
  name_prefix     = "terraform-lc-example-"
  image_id        = "ami-0db9040eb3ab74509"
  instance_type   = "t2.micro"
  key_name        = var.key_name
  security_groups = ["${aws_security_group.terra_app_server_sg.id}"]
  user_data       = <<EOF
#!/bin/bash
sudo amazon-linux-extras install -y nginx1
sudo systemctl start nginx
sudo systemctl enable nginx"
EOF
  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    "aws_security_group.terra_app_server_sg"
  ]
}

resource "aws_autoscaling_group" "terra-app-asg_az_1" {
  name                 = "terraform-asg-example-1"
  launch_configuration = aws_launch_configuration.terra_lc.name
  min_size             = 1
  max_size             = 2
  vpc_zone_identifier  = ["${aws_subnet.terra_private_subnet_az_1.id}"]
  target_group_arns    = ["${aws_alb_target_group.terra_alb_target_group.id}"]

  lifecycle {
    create_before_destroy = true
  }
  tag {
    propagate_at_launch = true
    key                 = "Name"
    value               = "web-server-az-1"

  }

  depends_on = [
    "aws_launch_configuration.terra_lc",
    "aws_subnet.terra_private_subnet_az_1",
    "aws_alb_target_group.terra_alb_target_group"
  ]
}

resource "aws_autoscaling_group" "terra-app-asg_az_2" {
  name                 = "terraform-asg-example-2"
  launch_configuration = aws_launch_configuration.terra_lc.name
  min_size             = 1
  max_size             = 2
  vpc_zone_identifier  = ["${aws_subnet.terra_private_subnet_az_2.id}"]
  target_group_arns    = ["${aws_alb_target_group.terra_alb_target_group.id}"]

  tag {
    propagate_at_launch = true
    key                 = "Name"
    value               = "web-server-az-2"
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    "aws_launch_configuration.terra_lc",
    "aws_subnet.terra_private_subnet_az_2",
    "aws_alb_target_group.terra_alb_target_group"
  ]
}




