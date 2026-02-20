output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "cp_instance_ids" {
  value = [for i in aws_instance.cp : i.id]
}

output "wk_instance_ids" {
  value = [for i in aws_instance.wk : i.id]
}

output "cp_private_ips" {
  value = [for i in aws_instance.cp : i.private_ip]
}

output "wk_private_ips" {
  value = [for i in aws_instance.wk : i.private_ip]
}

output "api_nlb_dns" {
  value = aws_lb.api.dns_name
}
