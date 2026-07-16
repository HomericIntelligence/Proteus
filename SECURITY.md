# Security Policy

## Reporting Security Vulnerabilities

**Do not open public issues for security vulnerabilities.**

We take security seriously. If you discover a security vulnerability, please report it responsibly.

## How to Report

### Email (Preferred)

Send an email to: **<security@homericintelligence.com>**

Or use the GitHub private vulnerability reporting feature if available.

### What to Include

Please include as much of the following information as possible:

- **Description** - Clear description of the vulnerability
- **Impact** - Potential impact and severity assessment
- **Steps to reproduce** - Detailed steps to reproduce the issue
- **Affected files** - Which pipeline scripts, configs, or recipes are affected
- **Suggested fix** - If you have a suggested fix or mitigation

### Example Report

```text
Subject: [SECURITY] Image promotion script leaks registry credentials in logs

Description:
The promote-image.sh script passes registry credentials as command-line
arguments to skopeo, which are visible in process listings and CI logs.

Impact:
An attacker with access to CI logs could extract container registry
credentials and push malicious images.

Steps to Reproduce:
1. Run just promote src-tag dest-tag with verbose logging enabled
2. Check CI output or /proc/<pid>/cmdline
3. Observe registry credentials in plaintext

Affected Files:
scripts/promote-image.sh

Suggested Fix:
Use skopeo's --authfile flag or environment variables instead of CLI args.
```

## Response Timeline

We aim to respond to security reports within the following timeframes:

| Stage                    | Timeframe              |
|--------------------------|------------------------|
| Initial acknowledgment   | 48 hours               |
| Preliminary assessment   | 1 week                 |
| Fix development          | Varies by severity     |
| Public disclosure        | After fix is released  |

## Severity Assessment

We use the following severity levels:

| Severity     | Description                          | Response           |
|--------------|--------------------------------------|--------------------|
| **Critical** | Remote code execution, data breach   | Immediate priority |
| **High**     | Privilege escalation, data exposure  | High priority      |
| **Medium**   | Limited impact vulnerabilities       | Standard priority  |
| **Low**      | Minor issues, hardening              | Scheduled fix      |

## Responsible Disclosure

We follow responsible disclosure practices:

1. **Report privately** - Do not disclose publicly until a fix is available
2. **Allow reasonable time** - Give us time to investigate and develop a fix
3. **Coordinate disclosure** - We will work with you on disclosure timing
4. **Credit** - We will credit you in the security advisory (if desired)

## What We Will Do

When you report a vulnerability:

1. Acknowledge receipt within 48 hours
2. Investigate and validate the report
3. Develop and test a fix
4. Release the fix
5. Publish a security advisory

## Scope

### In Scope

- Dagger TypeScript pipeline scripts (`dagger/`)
- Image promotion and build scripts (`scripts/`)
- Justfile recipes
- CI/CD workflow logic and credential handling

### Out of Scope

- AchaeanFleet Dockerfiles (report to [AchaeanFleet](https://github.com/HomericIntelligence/AchaeanFleet))
- Myrmidons manifests (report to [Myrmidons](https://github.com/HomericIntelligence/Myrmidons))
- Third-party CI tools (Dagger, skopeo — report upstream)
- Social engineering attacks
- Physical security

## Security Best Practices

When contributing to Proteus:

- Never hardcode registry credentials — use Dagger secrets API or environment variables
- Validate image tags and digests before promotion
- Audit promotion scripts for command injection vulnerabilities
- Ensure CI logs do not leak secrets in build output
- Use read-only registry tokens where possible

## Contact

For security-related questions that are not vulnerability reports:

- Open a GitHub Discussion with the "security" tag
- Email: <security@homericintelligence.com>

---

Thank you for helping keep HomericIntelligence secure!
