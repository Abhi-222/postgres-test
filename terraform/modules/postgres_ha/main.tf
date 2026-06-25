# ==========================================
# 0. SSH KEY PAIR
# ==========================================
resource "aws_key_pair" "deployer" {
  key_name   = "postgres-ha-key"
  public_key = var.ssh_public_key
}

# ==========================================
# 1. CORE NETWORKING LAYERS
# ==========================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags = {
    Name        = "postgres-ha-vpc"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "postgres-main-igw"
  }
}

resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id # Placed in the public subnet so it can talk to the IGW
  tags = {
    Name = "postgres-nat-gateway"
  }
}

# ==========================================
# 2. SUBNETS SPECIFICATION (Fixed AZ Mismatch)
# ==========================================
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = var.availability_zones[0] # Explicitly us-east-2a
  map_public_ip_on_launch = true
  tags = {
    Name = "bastion-public-subnet"
  }
}

resource "aws_subnet" "private_master" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 3)
  availability_zone = var.availability_zones[0] # Explicitly us-east-2a
  tags = {
    Name = "postgres-private-master"
  }
}

resource "aws_subnet" "private_replica_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 4)
  availability_zone = var.availability_zones[1] # Explicitly us-east-2b
  tags = {
    Name = "postgres-private-replica-1"
  }
}

resource "aws_subnet" "private_replica_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 5)
  availability_zone = var.availability_zones[2] # Explicitly us-east-2c
  tags = {
    Name = "postgres-private-replica-2"
  }
}

# ==========================================
# 3. ROUTING AND ASSOCIATIONS
# ==========================================
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "pub" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "priv_m" {
  subnet_id      = aws_subnet.private_master.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "priv_r1" {
  subnet_id      = aws_subnet.private_replica_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "priv_r2" {
  subnet_id      = aws_subnet.private_replica_2.id
  route_table_id = aws_route_table.private_rt.id
}

# ==========================================
# 4. SECURITY GROUPS (FIREWALLS)
# ==========================================
resource "aws_security_group" "bastion_sg" {
  name   = "${var.environment}-bastion-host-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Anyone can access the bastion if they have the private key
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "postgres_sg" {
  name   = "${var.environment}-postgres-isolated-db-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id] # Tight restriction: Must hop through Bastion
  }

  ingress {
    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"
    self      = true
  }
  
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_app_cidr_blocks
  }



  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# 5. EC2 COMPUTE TIERS
# ==========================================
resource "aws_instance" "bastion" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = aws_key_pair.deployer.key_name
  tags = {
    Name        = "Bastion-JumpBox"
    Environment = var.environment
  }
}

resource "aws_instance" "postgres_master" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_master.id
  vpc_security_group_ids = [aws_security_group.postgres_sg.id]
  key_name               = aws_key_pair.deployer.key_name
  tags = {
    Name        = "PostgreSQL-Master"
    Role        = "primary"
    Environment = var.environment
  }
}

resource "aws_instance" "postgres_replica_1" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_replica_1.id
  vpc_security_group_ids = [aws_security_group.postgres_sg.id]
  key_name               = aws_key_pair.deployer.key_name
  tags = {
    Name        = "PostgreSQL-Replica-1"
    Role        = "replica"
    Environment = var.environment
  }
}

resource "aws_instance" "postgres_replica_2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_replica_2.id
  vpc_security_group_ids = [aws_security_group.postgres_sg.id]
  key_name               = aws_key_pair.deployer.key_name
  tags = {
    Name        = "PostgreSQL-Replica-2"
    Role        = "replica"
    Environment = var.environment
  }
}

