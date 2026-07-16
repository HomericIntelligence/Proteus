# Contributing to Proteus

Thank you for your interest in contributing to Proteus! This is the CI/CD pipeline
automation hub for the [HomericIntelligence](https://github.com/HomericIntelligence) distributed
agent mesh — it orchestrates image builds, test runs, image promotion, and Myrmidons dispatch
via Dagger.

For an overview of the full ecosystem, see the
[Odysseus](https://github.com/HomericIntelligence/Odysseus) meta-repo.

## Quick Links

- [Development Setup](#development-setup)
- [What You Can Contribute](#what-you-can-contribute)
- [Development Workflow](#development-workflow)
- [Building and Testing](#building-and-testing)
- [Pull Request Process](#pull-request-process)
- [Code Review](#code-review)

## Development Setup

### Prerequisites

- [Git](https://git-scm.com/)
- [GitHub CLI](https://cli.github.com/) (`gh`)
- [Node.js](https://nodejs.org/) 20+ (for Dagger TypeScript SDK)
- [Dagger CLI](https://docs.dagger.io/cli/465058/install/) for pipeline execution
- [Pixi](https://pixi.sh/) for environment management
- [Just](https://just.systems/) as the command runner

### Environment Setup

```bash
# Clone the repository
git clone https://github.com/HomericIntelligence/Proteus.git
cd Proteus

# Activate the Pixi environment
pixi shell

# Install Dagger TypeScript dependencies
cd dagger && npm install && cd ..

# List available recipes
just --list
```

### Verify Your Setup

```bash
# Validate pipeline configuration
just validate

# Run linter
just lint
```

## What You Can Contribute

- **Pipeline stages** — New Dagger TypeScript pipeline steps in `dagger/`
- **Image promotion logic** — Improvements to `scripts/promote-image.sh`
- **Validation scripts** — YAML and config validation improvements
- **Justfile recipes** — New build, test, or deployment commands
- **Documentation** — README updates, pipeline usage guides

## Development Workflow

### 1. Find or Create an Issue

Before starting work:

- Browse [existing issues](https://github.com/HomericIntelligence/Proteus/issues)
- Comment on an issue to claim it before starting work
- Create a new issue if one doesn't exist for your contribution

### 2. Branch Naming Convention

Create a feature branch from `main`:

```bash
git checkout main
git pull origin main
git checkout -b <issue-number>-<short-description>

# Examples:
git checkout -b 15-add-security-scan-stage
git checkout -b 10-fix-promote-script-auth
```

**Branch naming rules:**

- Start with the issue number
- Use lowercase letters and hyphens
- Keep descriptions short but descriptive

### 3. Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```text
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**

| Type       | Description                |
|------------|----------------------------|
| `feat`     | New feature                |
| `fix`      | Bug fix                    |
| `docs`     | Documentation only         |
| `style`    | Formatting, no code change |
| `refactor` | Code restructuring         |
| `test`     | Adding/updating tests      |
| `chore`    | Maintenance tasks          |

**Example:**

```bash
git commit -m "feat(pipeline): add container security scan stage

Integrates Trivy scanning into the Dagger pipeline, failing the
build on critical or high severity CVEs.

Closes #15"
```

## Building and Testing

### Run Pipelines

```bash
# Build a specific service
just build <NAME>

# Test a specific service
just test <NAME>

# Run the full pipeline for a service
just pipeline <NAME>
```

### Promote Images

```bash
# Promote an image from one tag to another
just promote <SRC> <DEST>

# Dispatch Myrmidons apply to a host
just dispatch-apply <HOST>
```

### Validate and Lint

```bash
# Validate YAML and pipeline configuration
just validate

# Run linter
just lint
```

### TypeScript Conventions

- **Runtime**: Node.js 20+
- **SDK**: Dagger TypeScript SDK (`@dagger.io/dagger`)
- **Patterns**: Use async/await, strong typing for pipeline inputs/outputs
- **Secrets**: Use Dagger secrets API — never pass credentials as CLI arguments

## Pull Request Process

### Before You Start

1. Ensure an issue exists for your work
2. Create a branch from `main` using the naming convention
3. Implement your changes
4. Run `just validate` and `just lint` to verify

### Creating Your Pull Request

```bash
git push -u origin <branch-name>
gh pr create --title "[Type] Brief description" --body "Closes #<issue-number>"
```

**PR Requirements:**

- PR must be linked to a GitHub issue
- PR title should be clear and descriptive
- Validation and linting must pass

### Never Push Directly to Main

The `main` branch is protected. All changes must go through pull requests.

## Code Review

### What Reviewers Look For

- **Pipeline correctness** — Does the pipeline produce the expected artifacts?
- **Secrets handling** — Are credentials managed via Dagger secrets, not CLI args?
- **Idempotency** — Can the pipeline be safely re-run?
- **Promotion safety** — Are image tags and digests validated before promotion?
- **Script safety** — Are shell scripts free of command injection risks?

### Responding to Review Comments

- Keep responses short (1 line preferred)
- Start with "Fixed -" to indicate resolution

## Markdown Standards

All documentation files must follow these standards:

- Code blocks must have a language tag (`typescript`, `bash`, `yaml`, `text`, etc.)
- Code blocks must be surrounded by blank lines
- Lists must be surrounded by blank lines
- Headings must be surrounded by blank lines

## Reporting Issues

### Bug Reports

Include: clear title, steps to reproduce, expected vs actual behavior, Dagger/Node versions.

### Security Issues

**Do not open public issues for security vulnerabilities.**
See [SECURITY.md](SECURITY.md) for the responsible disclosure process.

## Code of Conduct

Please review our [Code of Conduct](CODE_OF_CONDUCT.md) before contributing.

## CI Pipeline Data & Privacy

Proteus CI pipelines process the following developer metadata:

- **Commit emails and GitHub usernames** — included in Git commit objects and GitHub Actions event payloads
- **Timing metadata** — workflow run durations and timestamps recorded by GitHub Actions
- **SARIF artifacts** — static-analysis results retained for **90 days** (configured in `.github/workflows/_required.yml`)
- **CI logs** — retained per the [GitHub Actions log retention policy](https://docs.github.com/en/actions/learn-github-actions/usage-limits-billing-and-administration#artifact-and-log-retention-policy) (default 90 days)

This data is used solely for CI/CD automation, code quality enforcement, and audit purposes within the HomericIntelligence organization. It is not shared with third parties beyond the GitHub platform itself.

If you have questions about data handling, contact <security@homericintelligence.com>.

## Releases

We do not maintain a `CHANGELOG.md`. Release notes are generated from
Conventional Commit messages by `.github/workflows/release.yml` when a
`vX.Y.Z` tag is pushed. See [docs/releases.md](docs/releases.md) for the
full policy. Keep commit subjects in the `feat:` / `fix:` / `docs:` /
`test:` / `chore:` format so the generated notes stay readable.

---

Thank you for contributing to Proteus!
