# Public NLB za kube-apiserver (6443)
resource "aws_lb" "api" {
  name               = "${var.name}-api"
  load_balancer_type = "network"
  subnets            = [aws_subnet.public.id]

  tags = { Name = "${var.name}-api-nlb" }
}

resource "aws_lb_target_group" "api" {
  name        = "${var.name}-api-tg"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = aws_vpc.this.id
  target_type = "instance"

  health_check {
    protocol = "TCP"
    port     = "6443"
  }

  tags = { Name = "${var.name}-api-tg" }
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_lb_target_group_attachment" "cp_attach" {
  count            = 3
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.cp[count.index].id
  port             = 6443
}

resource "aws_lb" "api_internal" {
  name               = "${var.name}-api-internal"
  load_balancer_type = "network"
  internal           = true

  # imaš samo jedan private subnet u modulu
  subnets = [aws_subnet.private.id]

  tags = { Name = "${var.name}-api-internal-nlb" }
}

resource "aws_lb_target_group" "api_internal" {
  name        = "${var.name}-api-internal-tg"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = aws_vpc.this.id
  target_type = "instance"

  health_check {
    protocol = "TCP"
    port     = "6443"
  }

  tags = { Name = "${var.name}-api-internal-tg" }
}

resource "aws_lb_listener" "api_internal" {
  load_balancer_arn = aws_lb.api_internal.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_internal.arn
  }
}

resource "aws_lb_target_group_attachment" "cp_attach_internal" {
  count            = 3
  target_group_arn = aws_lb_target_group.api_internal.arn
  target_id        = aws_instance.cp[count.index].id
  port             = 6443
}

#############################################
# Outputs (da lako pokupiš DNS)
#############################################

output "api_internal_nlb_dns" {
  value = aws_lb.api_internal.dns_name
}