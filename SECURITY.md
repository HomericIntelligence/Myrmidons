# Security Policy

## Reporting Security Vulnerabilities

**Do not open public issues for security vulnerabilities.**

We take security seriously. If you discover a security vulnerability, please report it responsibly.

## How to Report

### Email (Preferred)

Send an email to: **<4211002+mvillmow@users.noreply.github.com>**

Or use the GitHub private vulnerability reporting feature if available.

### What to Include

Please include as much of the following information as possible:

- **Description** - Clear description of the vulnerability
- **Impact** - Potential impact and severity assessment
- **Steps to reproduce** - Detailed steps to reproduce the issue
- **Affected files** - Which manifests, scripts, or configurations are affected
- **Suggested fix** - If you have a suggested fix or mitigation

### Example Report

```text
Subject: [SECURITY] Agent manifest contains hardcoded API credentials

Description:
The agent manifest at agents/data-collector.yml contains a hardcoded
API token in the environment section instead of referencing a secret.

Impact:
Anyone with read access to the repository can extract the API token
and use it to access the external data service.

Steps to Reproduce:
1. Open agents/data-collector.yml
2. Observe API_TOKEN value in environment block
3. Token is a valid credential for the external service

Affected Files:
agents/data-collector.yml

Suggested Fix:
Replace hardcoded token with a secret reference or environment variable.
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

- YAML agent manifests and definitions
- Shell scripts and provisioning hooks
- Justfile recipes
- Pre-commit hooks (`hooks/`)

### Out of Scope

- ProjectAgamemnon API (report to [ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon))
- Application code in agent repos (report to that repo directly)
- Third-party tools (yq, jq — report upstream)
- Social engineering attacks
- Physical security

## Drift detection as a security control

The `status.sh` and `plan.sh` scripts detect configuration drift between desired YAML
state and actual Agamemnon state. Running `just status` or `just plan` regularly can
surface unauthorized changes to agent configurations made outside GitOps.

## Security Best Practices

When contributing to Myrmidons:

- Never embed secrets, API keys, tokens, or credentials in YAML manifests
- Validate manifest schemas before applying (`just validate`)
- Review privilege levels in agent definitions — use least-privilege
- Use environment variable references for sensitive configuration
- Audit agent manifests for unintended network exposure

## Contact

For security-related questions that are not vulnerability reports:

- Open a GitHub Discussion with the "security" tag
- Email: <4211002+mvillmow@users.noreply.github.com>

---

Thank you for helping keep HomericIntelligence secure!
