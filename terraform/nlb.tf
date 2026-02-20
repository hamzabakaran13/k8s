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
