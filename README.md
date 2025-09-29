This script install essential tools and configurations for a new development environment. Supported operating systems are MacOS only at the moment.

## Features

### AWS CLI Enhancement
- **Automatic S3 URI correction**: Commands like `aws s3 mb bucket` are automatically corrected to `aws s3 mb s3://bucket`
- **Session management**: Automatic AWS session refresh when expired
- **Safety rules**: Intelligent handling of `rm` vs `rb` commands to prevent misinterpretation
- **Smart filtering**: Intelligent detection prevents interference with non-AWS commands containing "aws" (like `K8S_CLUSTER_NAME=prd.k8s.multpex.com.br`)
- **Advanced command detection**: Works with complex commands including pipes (`kubectl get pods | aws s3 cp...`) and compound statements (`export VAR=value && aws s3 ls...`)
- **Command substitution support**: Detects and processes AWS commands inside `$(aws ...)` and `` `aws ...` `` command substitutions
- **Debug mode**: Set `AWS_MIDDLEWARE_DEBUG=1` for detailed logging

## Installation
Run the following command in your terminal:

`bash -c "$(curl -fsSL https://raw.githubusercontent.com/524c/.dotfiles/main/install.sh)"`
