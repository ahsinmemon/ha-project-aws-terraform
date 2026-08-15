resource "aws_security_group" "alb" {
  name        = "ha-project-alb-sg"
  description = "Allow HTTP from the internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }


    tags = {
    Name = "ha-project-alb-sg"
  }

}

resource "aws_security_group" "ec2" {
  name        = "ha-project-ec2-sg"
  description = "Allow HTTP from ALB only, ssh for admin"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from ALB"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

    ingress {
    description = "SSH for chaos test access"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }


    tags = {
    Name = "ha-project-ec2-sg"
  }

}


resource "aws_security_group" "rds" {
  name        = "ha-project-rds-sg"
  description = "Allow MySQL from EC2 instances only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL from EC2"
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }


    tags = {
    Name = "ha-project-rds-sg"
  }

}