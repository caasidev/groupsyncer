# GroupSyncer

<div align="center">
    <img src="./assets/GSLOGO.png" alt="GroupSyncer Logo">
</div>

A modern bash-based tool for automatically updating AWS Security Group rules with your current IP address.

Great for VPN users whose IP often changes, or for managing access to multiple services on different ports.

## Features

- Auto-detects your current public IP address
- Updates rules based on description patterns
- Supports multiple ports in a single command
- Supports multiple AWS profiles
- Dry-run mode for safe testing
- Comprehensive logging

## How It Works

GroupSyncer searches for AWS Security Group rules that match both:

1. **Port specification**: Rules on the exact ports you specify (or port 22 by default)
2. **Description pattern**: Rules whose description contains the text you provide

### Rule Matching Logic

- The tool searches across all specified ports for ingress rules
- Only rules with descriptions containing your search term are updated
- Each matching rule has its CIDR block updated to your current IP/32
- Rules on different ports are treated independently

## Requirements

- `bash` 4.0+
- `aws` CLI
- `jq`
- `curl`
- Internet connection for IP detection

## Installation

```bash
git clone https://github.com/caasidev/groupsyncer.git
cd groupsyncer
chmod +x groupsyncer
```

## Usage

```bash
# Basic usage (defaults to SSH port 22)
./groupsyncer -d "Office"

# Update multiple ports
./groupsyncer -d "Remote" -p "22,80,443"

# Update database ports
./groupsyncer -d "Database" -p "3306,5432"

# Dry run to see what would change
./groupsyncer -d "Home" --dry-run

# Use specific AWS profile
./groupsyncer -d "VPN" --profile production

# Use specific IP address
./groupsyncer -d "Remote" -i 192.168.1.100

# Verbose output
./groupsyncer -d "Office" --verbose
```

### Common Port Examples

```bash
# SSH only (default)
./groupsyncer -d "Office"

# Web services
./groupsyncer -d "WebServer" -p "80,443"

# Database services
./groupsyncer -d "Database" -p "3306,5432,27017"  # MySQL, PostgreSQL, MongoDB

# Development services
./groupsyncer -d "DevEnv" -p "22,3000,8080,9000"

# Custom application ports
./groupsyncer -d "AppServices" -p "8443,9443"
```

## Configuration

Set up your AWS credentials using one of the following methods:

- AWS CLI (`aws configure`)
- Environment variables
- IAM roles (for EC2 instances)

## Project Structure

```
groupsyncer/
├── groupsyncer          # Main executable
├── lib/                 # Modular libraries
│   ├── aws.sh           # AWS CLI operations
│   ├── config.sh        # Configuration & argument parsing
│   ├── ip.sh            # IP detection & validation
│   └── logger.sh        # Logging utilities
├── README.md            # Main documentation
├── LICENSE              # MIT License
└── .gitignore           # Git ignore patterns
```

### Modern Bash Best Practices

- `set -euo pipefail` in all scripts
- Proper variable quoting and local scoping
- Comprehensive error handling
- Clean function separation

## License

MIT License

## Troubleshooting

### Common Issues

**No rules found**

- Verify the description text appears in your security group rule descriptions
- Check that you're specifying the correct ports
- Use `--verbose` for detailed search information

**Port validation errors**

```bash
# Invalid formats
./groupsyncer -d "Test" -p "ssh"          # Use numbers only
./groupsyncer -d "Test" -p "22-80"        # Use comma separation
./groupsyncer -d "Test" -p "22, 80, 443"  # Spaces are OK but not required

# Valid formats
./groupsyncer -d "Test" -p "22"
./groupsyncer -d "Test" -p "22,80,443"
./groupsyncer -d "Test" -p "22, 80, 443"
```

**Partial updates**

- If some ports update successfully but others fail, check the specific port configurations
- Each port is updated independently - failures on one port don't affect others
- Review the log file for detailed error information
