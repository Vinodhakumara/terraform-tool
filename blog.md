# I Built a Terraform Toolkit That Saves Me 30 Minutes Every Day — Here's How

If you work with Terraform daily, you know the pain. You run `terraform plan`, and it dumps a wall of text. You squint at it trying to figure out what's actually changing. You forget to lint before pushing. You have no idea how much your changes will cost until the bill arrives.

I got tired of it. So I built a small, portable toolkit — a set of shell commands that sit on top of Terraform and make the entire workflow faster, safer, and more readable.

No new frameworks. No wrappers that hide what Terraform is doing. Just sharp, focused shell functions you can install in 30 seconds and use from any Terraform project on your machine.

---

## The Problem

Here's what my daily Terraform workflow used to look like:

1. Run `terraform plan` — get 200 lines of output
2. Scroll up and down trying to find the *important* changes
3. Miss that one resource getting **destroyed** because it was buried between 40 no-ops
4. Push code without linting — CI fails
5. Get surprised by costs at the end of the month

Sound familiar?

---

## The Solution: 11 Shell Commands

I created a set of global shell functions that work from **any** Terraform directory on my machine. No per-repo setup. No Makefiles. Just `cd` into any Terraform folder and go.

Here's the full list:

| Command | What it does |
|---------|-------------|
| `tplan` | Plan + module-grouped colored summary |
| `tplan-summary` | Re-display summary of an existing plan |
| `tcost` | Estimate monthly infrastructure cost |
| `tcost --full` | Expanded cost view with sub-resources |
| `tcheck` | Run all quality checks in one shot |
| `tfmt` | Format all `.tf` files |
| `tval` | Validate configuration |
| `tlint` | Run tflint linter |
| `tlint-sec` | Run tfsec security scanner |
| `tdiff` | Show Terraform/YAML changes since last commit |
| `tdiff-staged` | Show staged changes only |
| `thelp` | Show all commands with descriptions |

Let me walk through the ones that changed my workflow the most.

---

## 1. `tplan` — The Plan You Can Actually Read

The default `terraform plan` output is functional but noisy. My `tplan` command does three things differently:

- **Auto-initializes** if `.terraform/` doesn't exist
- **Groups changes by module** so you can see the blast radius at a glance
- **Color-codes by action** — red for destroy, green for create, yellow for update

Here's what the output looks like:

```
====== TERRAFORM PLAN SUMMARY ======

DESTROY (2):
  module.cloudsql
    - google_sql_database.analytics
    - google_sql_user.app_reader

CREATE (3):
  module.gke
    + google_container_node_pool.general
    + google_container_node_pool.compute
  module.redis
    + google_redis_instance.cache

UPDATE (1):
  module.cloudsql
    ~ google_sql_database_instance.primary
      ~ settings.tier: db-custom-2-8192 -> db-custom-4-16384
      ~ settings.disk_size: 50 -> 100

=====================================
Total: 2 to destroy, 3 to create, 1 to update

WARNING: This plan includes resource destruction. Review carefully.
```

Destroys are listed first because they're the most dangerous. Updates show the actual attribute diffs inline. Everything is grouped by the top-level module so you immediately know *which part* of your infrastructure is affected.

Under the hood, it runs `terraform show -json` on the plan file and parses it with `jq`. The entire summary script is a standalone bash file at `~/bin/tf-plan-summary` — no dependencies beyond `terraform` and `jq`.

---

## 2. `tcost` — Know the Cost Before You Apply

This was the game-changer. `tcost` uses [Infracost](https://www.infracost.io/) to estimate what your infrastructure will cost per month, directly from your HCL code. No need to apply first.

The default view gives you a compact, module-grouped breakdown:

```
  INFRACOST ESTIMATE
  /Users/me/infra/envs/dev

  module.cloudsql                                          $245.80/mo
  │  google_sql_database_instance.primary                    $189.50/mo
  │  google_sql_database_instance.replica                     $56.30/mo

  module.gke                                               $312.40/mo
  │  google_container_node_pool.general                      $198.20/mo
  │  google_container_node_pool.compute                      $114.20/mo

  ──────────────────────────────────────────────────────────────────────────
  TOTAL                                                    $558.20/mo
  5 priced  ·  3 free
  Run 'tcost --full' for expanded resource names and sub-costs
```

Costs are color-coded: green under $100, yellow $100–$500, red above $500 — so expensive resources jump out visually.

Running `tcost --full` expands every resource to show sub-component costs (compute, storage, network, etc.), which is invaluable when you're trying to figure out *why* something costs what it does.

---

## 3. `tcheck` — One Command, All Quality Gates

Before I built this, I'd forget to run at least one check before pushing. Now it's just:

```bash
$ tcheck
```

Output:

```
--- Terraform Quality Check ---

  [PASS] terraform fmt
  [PASS] terraform validate
  [PASS] tflint
  [WARN] tfsec -- 2 issue(s), run 'tlint-sec' for details

  Some checks failed.
```

It runs `terraform fmt -check`, `terraform validate`, `tflint`, and `tfsec` in sequence and gives you a colored pass/fail summary. If a tool isn't installed, it shows `[SKIP]` instead of crashing.

---

## 4. `tdiff` — Review Only What Matters

When working in a large repo, `git diff` shows everything. But before a Terraform PR, I only care about `.tf`, `.yaml`, and `.yml` files. That's what `tdiff` filters to:

```bash
$ tdiff           # changes since last commit
$ tdiff-staged    # only staged changes
```

Small thing, but it removes noise and keeps reviews focused.

---

## The Cursor Rule (Bonus for AI-Assisted Coding)

If you use [Cursor](https://cursor.sh/) (or any AI-assisted editor), I also created a global rule file at `~/.cursor/rules/terraform.mdc` that teaches the AI your Terraform conventions:

- Module structure (`main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`)
- Variable typing with `validation` blocks
- YAML-driven configuration patterns
- Security requirements (CMEK, private networking, SSL, deletion protection)
- Common pitfalls (destructive `for_each` key changes, encryption key replacements)

This means when you ask the AI to "add a Cloud SQL instance," it follows your patterns instead of generating generic Terraform.

---

## One-Command Install

Everything is packaged in a single `install.sh` script. On a fresh Mac:

```bash
git clone <your-repo> terraform-toolkit-v2
cd terraform-toolkit-v2
bash install.sh
```

It will:

1. Install CLI tools via Homebrew (terraform, jq, tflint, tfsec, infracost, pre-commit)
2. Create `~/bin/tf-plan-summary`
3. Add all shell functions to `~/.zshrc` inside a clearly marked block
4. Install the Cursor AI rule

It's **idempotent** — safe to run multiple times. It skips tools already installed and won't duplicate the `.zshrc` block.

After install:

```bash
source ~/.zshrc
thelp
```

And you're ready to go from any Terraform directory.

---

## Design Decisions

A few intentional choices worth calling out:

**No `apply` command.** This toolkit is read-only by design. Planning, reviewing, and linting — yes. Applying infrastructure changes from a shortcut — no. That should always be deliberate.

**Global, not per-repo.** I work across multiple Terraform repositories. Having tools that follow me everywhere beats maintaining Makefiles in each repo.

**Graceful degradation.** If `tflint` isn't installed, `tlint` falls back to `pre-commit run terraform_tflint`. If that's not available either, it tells you clearly. Nothing crashes silently.

**Module grouping everywhere.** Both `tplan` and `tcost` group output by top-level module. When you have 50+ resources, knowing that 8 changes are all in `module.gke` is far more useful than a flat list.

---

## Uninstall

If you ever want to remove it cleanly:

1. Delete the block between `# >>> terraform-toolkit-v2 >>>` and `# <<< terraform-toolkit-v2 <<<` from `~/.zshrc`
2. `rm ~/bin/tf-plan-summary`
3. `rm ~/.cursor/rules/terraform.mdc`

That's it. No system-level changes to undo.

---

## Wrapping Up

This toolkit doesn't replace Terraform or any CI/CD pipeline. It makes the *local development loop* faster and safer:

- **See what's changing** without deciphering raw plan output
- **Know what it costs** before you apply
- **Catch issues locally** before CI does
- **Review only Terraform changes** in git

The entire thing is about 400 lines of shell script. No compiled binaries, no package managers, no runtime dependencies beyond what you already have.

If you spend your days writing Terraform, give it a try. The 30 seconds it takes to install will save you 30 minutes every day.

---

*The full source is available on [GitHub](https://github.com/your-username/terraform-toolkit-v2). Star it if you find it useful.*

*Follow me for more infrastructure and DevOps tooling posts.*

---

**Tags:** `Terraform` `DevOps` `Infrastructure as Code` `Developer Tools` `Productivity`
