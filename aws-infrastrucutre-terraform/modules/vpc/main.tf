resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project}${var.environment}-VPC"
  }
}

//Public Subnets
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_blocks[0]
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project}${var.environment}_public_sub-1"
  }
}


resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_blocks[1]
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project}${var.environment}_public_sub-2"
  }
}

resource "aws_subnet" "public_3" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_blocks[2]
  availability_zone       = var.availability_zones[2]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project}${var.environment}_public_sub-3"
  }
}


//Private Subnets

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_cidr_blocks[3]
  availability_zone = var.availability_zones[0]
  tags = {
    Name = "${var.project}${var.environment}-private_sub-1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_cidr_blocks[4]
  availability_zone = var.availability_zones[1]
  tags = {
    Name = "${var.project}${var.environment}-private_sub-2"
  }
}

resource "aws_subnet" "private_3" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_cidr_blocks[5]
  availability_zone = var.availability_zones[2]
  tags = {
    Name = "${var.project}${var.environment}-private_sub-3"
  }
}


resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.project}${var.environment}-IG"
  }
}

// Public Route Table

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "rtb-${var.project}${var.environment}_public"
  }
}
// Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "rtb-${var.project}${var.environment}-private"
  }
}


resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}


// Public Route Table Associations

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "public_3" {
  subnet_id      = aws_subnet.public_3.id
  route_table_id = aws_route_table.main.id
}

// Private Route Table Associations

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_3" {
  subnet_id      = aws_subnet.private_3.id
  route_table_id = aws_route_table.private.id
}
