resource "aws_launch_template" "app" {
  name_prefix   = "ha-project-"
  image_id      = var.ami_id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = base64encode(file("${path.module}/user_data.sh"))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ha-project-instance"
    }
  }
}

resource "aws_lb_target_group" "app" {
  name     = "ha-project-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path = "/"
    interval = 15
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 2
    matcher = "200"
  }

  tags = {
    Name = "ha-project-tg"
  }
}


resource "aws_lb" "app" {
  name               = "ha-project-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "ha-project-alb"
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Auto Scaling Group

resource "aws_autoscaling_group" "app" {
  name                      = "ha-project-asg"
  vpc_zone_identifier       = aws_subnet.private[*].id
  target_group_arns = [ aws_lb_target_group.app.arn ]
  health_check_type         = "ELB"
  health_check_grace_period = 60

  max_size                  = 5
  min_size                  = 2
  desired_capacity          = 4

  launch_template {
    id = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "ha-project-asg-instance"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "ha-project-cpu-scaling"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}
