# Terraform Toolkit v2

One-command setup for all your Terraform helper tools on a fresh macOS machine.

## Quick Install

```bash
bash install.sh
```

Safe to re-run — it skips what's already installed and won't duplicate `.zshrc` entries.

## What Gets Installed

### CLI Tools (via Homebrew)

| Tool | Purpose |
|------|---------|
| `terraform` | Infrastructure as Code |
| `jq` | JSON parsing for plan summaries |
| `tflint` | Terraform linter |
| `tfsec` | Security scanner |
| `infracost` | Cost estimation |
| `pre-commit` | Git hook framework |

### Shell Commands (added to `~/.zshrc`)

| Command | Description |
|---------|-------------|
| `tplan` | Plan + colored module-grouped summary (auto-inits) |
| `tplan-summary` | Show summary of an existing plan file |
| `tcost` | Estimate monthly cost of infrastructure |
| `tcost --full` | Expanded view with full resource names + sub-costs |
| `tcheck` | Run all checks: fmt + validate + tflint + tfsec |
| `tval` | Run `terraform validate` |
| `tfmt` | Format `.tf` files recursively |
| `tlint` | Run tflint linter |
| `tlint-sec` | Run tfsec security scan |
| `tdiff` | Show `.tf`/`.yaml` changes since last commit |
| `tdiff-staged` | Show staged `.tf`/`.yaml` changes |
| `thelp` | Show all commands with descriptions |

### Other Files

| File | Purpose |
|------|---------|
| `~/bin/tf-plan-summary` | Plan summary script (used by `tplan`) |
| `~/.cursor/rules/terraform.mdc` | Global Cursor AI rule for Terraform best practices |

## Uninstall

1. Remove the block between `# >>> terraform-toolkit-v2 >>>` and `# <<< terraform-toolkit-v2 <<<` from `~/.zshrc`
2. `rm ~/bin/tf-plan-summary`
3. `rm ~/.cursor/rules/terraform.mdc`

## Post-Install

```bash
source ~/.zshrc    # or open a new terminal
thelp              # see all available commands
infracost auth login   # one-time free registration for cost estimates
```
