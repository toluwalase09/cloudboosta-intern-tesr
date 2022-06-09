
  

#step 1 declaring all our networking resources for our infrasctruce
#declaring vpc
resource "aws_vpc" "myvpc" {
    cidr_block = "10.0.0.0/16"
}

#declaring internet gateway
resource "aws_internet_gateway" "my_internet_gateway" {
    vpc_id = aws_vpc.myvpc.id


    tags = {
        name = "gateway"
    }
  
}

#declaring subnet in the firt availability zone
resource "aws_subnet" "subnet_1" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "Az-1"
  }
}

#declaring subnet in the second availability zone
resource "aws_subnet" "subnet_2" {
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "Az-2"
  }
}


#declaring internet gateway attachment
resource "aws_internet_gateway_attachment" "vpc_igw" {
  internet_gateway_id = aws_internet_gateway.my_internet_gateway.id
  vpc_id              = aws_vpc.myvpc.id

}

#declaring route table
resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_internet_gateway.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_internet_gateway.my_internet_gateway.id
  }

  tags = {
    Name = "routing"
  }
}
#association subnet with route table
resource "aws_route_table_association" "subnet_1_association" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.my_route_table.id
}


resource "aws_route_table_association" "subnet_2_association" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.my_route_table.id
}


#security group
resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description      = "https"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

   ingress {
    description      = "http"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
     cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

    ingress {
    description      = "ssh"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}


#network interface
#resource "aws_network_interface" "test" {
 # subnet_id       = aws_subnet.public_a.id
#  private_ips     = ["10.0.0.50"]
#  security_groups = [aws_security_group.allow_tls]
#}
#elastic ip
#resource "aws_eip" "one" {
#  vpc                       = true
#  loadnetwork_interface      = aws_network_interface.test.id
#  associate_with_private_ip = "10.0.0.10"
#  depend_on = [aws_network_interface.test]
#}
#load balancer

resource "aws_lb" "test" {
  name               = "test-lb-tf"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.subnet_1, aws_subnet.subnet_2]

  enable_deletion_protection = true

  tags = {
    Environment = "production"
  }
}

resource "aws_lb" "example" {
  name               = "example"
  load_balancer_type = "network"

  subnet_mapping {
    subnet_id     = aws_subnet.subnet_1.id

  }

  subnet_mapping {
    subnet_id     = aws_subnet.subnet_2.id
  }
}
#step 2: creation of intsances and autoscalling group

#instances creation
#resource "aws_instance" "my_instance" {
#  ami           = "ami-09d56f8956ab235b3" # us-west-2
#  instance_type = "t2.micro"
#  key_name = "cloudboosta"

 # network_interface {
#    network_interface_id = aws_network_interface.test.id
#    device_index         = 0
#  }
#}



#autoscalling

#launch configuration for autoscalling

#defining the data 
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["318867684519"] # Canonical
}

#launch config resources
resource "aws_launch_configuration" "as_conf" {
  name_prefix   = "terraform-lc-example-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name = "cloudboosta.pem"

  lifecycle {
    create_before_destroy = true
  }
}

#autoscalling group
resource "aws_autoscaling_group" "custom-group-autoscaling" {
  name                      = "custom-group-autoscaling"
  max_size                  = 4
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 3
  force_delete              = true
 ## placement_group           = aws_placement_group.test.id
  launch_configuration      = aws_launch_configuration.as_conf
 vpc_zone_identifier       = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]
  tag {
    key = "name"
    value = "custom_ec2_instance"
    propagate_at_launch = true
  }
}
#define autoscaling policy
resource "aws_autoscaling_policy" "custom_cpu_policy" {
  name = "custom-cpu-policy"
  autoscaling_group_name = aws_autoscaling_group.custom-group-autoscaling.name
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = 1
  cooldown = 60
  policy_type = "SimpleScaling"
}


#cloudwacth monitoring
resource "aws_cloudwatch_metric_alarm" "custom-cpu-alarm" {
  alarm_name                = "custom-cpu-alarm"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = 2
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = 120
  statistic                 = "Average"
  threshold                 = 20
  alarm_description         = "This metric monitors ec2 cpu utilization"
  insufficient_data_actions = []

  dimensions = {
    "AutoScalingGroupName" : aws_autoscaling_group.custom-group-autoscaling.name
  }
  
  actions_enabled = true
  alarm_actions = [aws_autoscaling_policy.custom_cpu_policy.arn]
}

