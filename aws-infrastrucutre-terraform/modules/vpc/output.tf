output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet1" {
  value = aws_subnet.public_1.id
}

output "subnet2" {
  value = aws_subnet.public_2.id
}

output "subnet3" {
  value = aws_subnet.public_3.id
}

output "subnet4" {
  value = aws_subnet.private_1.id
}

output "subnet5" {
  value = aws_subnet.private_2.id
}
output "subnet6" {
  value = aws_subnet.private_3.id
}

