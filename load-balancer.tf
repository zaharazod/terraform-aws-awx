resource "aws_security_group" "awx_asg" {
  name        = "awx_asg"
  description = "awx traffic"
  vpc_id = var.vpc_id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8" ]
  }

  ingress {
    from_port   = 8052
    to_port     = 8052
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
     from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  tags = {
    Name = "awx_asg"
  }
}


resource "aws_launch_configuration" "this" {
  name          = "awx_${var.cluster_name}"
  image_id      = var.runner_ami
  instance_type = var.runner_instance_type
  security_groups = [ aws_security_group.awx_asg.id ]
  key_name      = var.ec2_key
   lifecycle {
     create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "runner_asg" {
  name      = "${var.cluster_name}-asg"
  tags     = [
    { 
      "key": "Name",  
      "value": "${var.cluster_name}_awx_runner",
      "propagate_at_launch":true
      },
    { 
      "key": "awx",  
      "value": "runner",
      "propagate_at_launch":true
      }
    ]
  max_size  = 1
  min_size  = 1
  launch_configuration = aws_launch_configuration.this.id
  vpc_zone_identifier = var.private_subnets
}


# =============================================
# ALB
# =============================================

resource "aws_security_group" "alb" {
  name_prefix = "${var.cluster_name}-lb"
  vpc_id      = var.vpc_id

  tags = local.common_tags
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "this" {
  name_prefix        = "${var.cluster_name}-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.private_subnets

  enable_deletion_protection = false

  tags = local.common_tags
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "awx" {
  name_prefix = substr("${var.cluster_name}-tgtgrp", 0, 6)
  port        = 8052
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  health_check {
    interval            = 10
    timeout             = 5
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "awx" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.alb_ssl_certificate_arn
  depends_on        = [aws_lb_target_group.awx]

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.awx.arn
  }
}

resource "aws_lb_listener" "https_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
