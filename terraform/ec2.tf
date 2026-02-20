data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Control-plane instances (private subnet, no public IP)
resource "aws_instance" "cp" {
  count = 3

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_cp
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.cp.id]

  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  associate_public_ip_address = false


  tags = {
    Name = "${var.name}-cp-${count.index + 1}"
    Role = "control-plane"
  }
}

# Worker instances (private subnet, no public IP)
resource "aws_instance" "wk" {
  count = 3

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type_wk
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.wk.id]

  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name

  associate_public_ip_address = false


  tags = {
    Name = "${var.name}-wk-${count.index + 1}"
    Role = "worker"
  }
}
