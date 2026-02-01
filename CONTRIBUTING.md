# Contributing to Molten

Thank you for your interest in contributing to Molten! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for everyone.

## How to Contribute

### Reporting Issues

1. **Search existing issues** to avoid duplicates
2. **Use issue templates** when available
3. **Provide details**:
   - Clear description of the problem
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details (OS, Azure region, etc.)

### Submitting Pull Requests

1. **Fork the repository** and create a feature branch
2. **Follow coding standards**:
   - TypeScript for Functions code
   - HCL formatting for Terraform (`terraform fmt`)
   - Meaningful commit messages
3. **Test your changes**:
   - Run `npm test` for TypeScript code
   - Run `terraform validate` for infrastructure
4. **Update documentation** if needed
5. **Submit PR** with a clear description

### Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/molten.git
cd molten

# Install dependencies
cd src/functions && npm install

# Run locally
func start

# Validate Terraform
cd infra/terraform
terraform init
terraform validate
```

### Commit Message Format

```
type(scope): description

[optional body]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

Examples:
- `feat(telegram): add inline keyboard support`
- `fix(openai): handle rate limit errors`
- `docs(readme): update deployment instructions`

## Security

**Do not submit PRs containing:**
- Secrets, API keys, or tokens
- Personal or sensitive data
- Malicious code

See [SECURITY.md](SECURITY.md) for reporting security vulnerabilities.

## Questions?

Open a GitHub Discussion or Issue for questions about contributing.
