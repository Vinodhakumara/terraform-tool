#!/bin/bash
#
# Terraform Toolkit v2 — One-command setup for a new machine.
#
# Installs:
#   - CLI tools: terraform, jq, tflint, infracost, tfsec, pre-commit
#   - ~/bin/tf-plan-summary (module-grouped plan summary script)
#   - Shell functions in ~/.zshrc (tplan, tcost, tcheck, tdiff, etc.)
#   - Global Cursor rule at ~/.cursor/rules/terraform.mdc
#
# Usage:
#   curl -sL <url>/install.sh | bash
#   OR
#   bash install.sh
#
# Safe to re-run — it skips what's already installed and won't duplicate .zshrc entries.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}  Terraform Toolkit v2 — Installer${RESET}"
echo -e "${DIM}  ────────────────────────────────────${RESET}"
echo ""

# ─── 1. Install CLI tools via Homebrew ───────────────────────────────────────

install_tool() {
  local name="$1"
  local brew_pkg="${2:-$1}"
  if command -v "$name" &>/dev/null; then
    echo -e "  ${GREEN}[OK]${RESET} $name already installed"
  else
    echo -e "  ${YELLOW}[INSTALL]${RESET} Installing $name..."
    brew install "$brew_pkg"
    echo -e "  ${GREEN}[OK]${RESET} $name installed"
  fi
}

if ! command -v brew &>/dev/null; then
  echo -e "  ${RED}[ERROR]${RESET} Homebrew not found. Install it first:"
  echo "    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
  exit 1
fi

echo -e "${BOLD}  Installing CLI tools...${RESET}"
install_tool terraform hashicorp/tap/terraform
install_tool jq
install_tool tflint
install_tool infracost
install_tool tfsec
install_tool pre-commit
echo ""

# ─── 2. Create ~/bin/tf-plan-summary ────────────────────────────────────────

echo -e "${BOLD}  Installing tf-plan-summary...${RESET}"
mkdir -p "$HOME/bin"

cat > "$HOME/bin/tf-plan-summary" << 'PLAN_SUMMARY_EOF'
#!/bin/bash
#
# tf-plan-summary — Parse any terraform plan into a clean, module-grouped summary.
# Dependencies: terraform, jq

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

plan_file=""

usage() {
  echo "Usage: tf-plan-summary [OPTIONS] <path-to-tfplan>"
  echo ""
  echo "Options:"
  echo "  --no-color   Disable color output (for piping to files)"
  echo "  -h, --help   Show this help message"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-color)
      RED="" GREEN="" YELLOW="" CYAN="" BOLD="" DIM="" RESET=""
      shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      plan_file="$1"; shift ;;
  esac
done

if [[ -z "$plan_file" ]]; then echo "ERROR: No plan file specified."; echo ""; usage; exit 1; fi
if [[ ! -f "$plan_file" ]]; then echo "ERROR: Plan file not found: ${plan_file}"; exit 1; fi
for cmd in terraform jq; do
  if ! command -v "$cmd" &>/dev/null; then echo "ERROR: '${cmd}' not found in PATH."; exit 1; fi
done

plan_file="$(cd "$(dirname "$plan_file")" && pwd)/$(basename "$plan_file")"
json_output=$(terraform show -json "$plan_file" 2>/dev/null)

if [[ -z "$json_output" ]] || ! echo "$json_output" | jq empty 2>/dev/null; then
  echo "ERROR: Failed to parse plan file. Make sure you're in the terraform-initialized directory."; exit 1
fi

resource_changes=$(echo "$json_output" | jq -c '.resource_changes // []')
creates=$(echo "$resource_changes" | jq -c '[.[] | select(.change.actions == ["create"])]')
destroys=$(echo "$resource_changes" | jq -c '[.[] | select(.change.actions == ["delete"])]')
updates=$(echo "$resource_changes" | jq -c '[.[] | select(.change.actions == ["update"])]')
replaces=$(echo "$resource_changes" | jq -c '[.[] | select(.change.actions == ["delete","create"] or .change.actions == ["create","delete"])]')
reads=$(echo "$resource_changes" | jq -c '[.[] | select(.change.actions == ["read"])]')
noops=$(echo "$resource_changes" | jq -c '[.[] | select(.change.actions == ["no-op"])]')

create_count=$(echo "$creates" | jq 'length')
destroy_count=$(echo "$destroys" | jq 'length')
update_count=$(echo "$updates" | jq 'length')
replace_count=$(echo "$replaces" | jq 'length')
read_count=$(echo "$reads" | jq 'length')
noop_count=$(echo "$noops" | jq 'length')

echo ""
echo -e "${BOLD}====== TERRAFORM PLAN SUMMARY ======${RESET}"
echo -e "${DIM}Plan file: ${plan_file}${RESET}"
echo -e "${DIM}Directory: $(pwd)${RESET}"
echo ""

get_module_group() {
  local addr="$1"
  if [[ "$addr" == module.* ]]; then echo "$addr" | sed 's/^\(module\.[^.]*\).*/\1/'
  else echo "(root)"; fi
}

strip_module_prefix() {
  local addr="$1" group="$2"
  if [[ "$group" == "(root)" ]]; then echo "$addr"
  else echo "${addr#${group}.}"; fi
}

print_grouped() {
  local label="$1" color="$2" symbol="$3" resources="$4" show_diffs="$5"
  local count
  count=$(echo "$resources" | jq 'length')
  if [[ "$count" -eq 0 ]]; then return; fi

  echo -e "${color}${BOLD}${label} (${count}):${RESET}"
  local addresses prev_group=""
  addresses=$(echo "$resources" | jq -r '.[].address' | sort)

  while IFS= read -r addr; do
    local group short
    group=$(get_module_group "$addr")
    short=$(strip_module_prefix "$addr" "$group")
    if [[ "$group" != "$prev_group" ]]; then
      echo -e "  ${DIM}${group}${RESET}"; prev_group="$group"
    fi
    echo -e "    ${color}${symbol} ${short}${RESET}"
    if [[ "$show_diffs" == "true" ]]; then
      diff_output=$(echo "$resources" | jq -r --arg addr "$addr" '
        .[] | select(.address == $addr) | .change as $c |
        if $c.before != null and $c.after != null then
          [$c.before | to_entries[] | select(. as $entry | ($c.after[$entry.key] // null) != $entry.value) |
          "      ~ \(.key): \(.value | tostring | if length > 60 then .[:57] + "..." else . end) -> \($c.after[.key] | tostring | if length > 60 then .[:57] + "..." else . end)"
          ] | .[]
        else empty end
      ')
      if [[ -n "$diff_output" ]]; then echo -e "${YELLOW}${diff_output}${RESET}"; fi
    fi
  done <<< "$addresses"
  echo ""
}

if [[ "$destroy_count" -gt 0 ]]; then print_grouped "DESTROY" "$RED" "-" "$destroys" "false"; fi

if [[ "$replace_count" -gt 0 ]]; then
  echo -e "${RED}${BOLD}REPLACE (destroy then create) (${replace_count}):${RESET}"
  prev_group=""
  echo "$replaces" | jq -r '.[].address' | sort | while IFS= read -r addr; do
    group=$(get_module_group "$addr"); short=$(strip_module_prefix "$addr" "$group")
    if [[ "$group" != "$prev_group" ]]; then echo -e "  ${DIM}${group}${RESET}"; prev_group="$group"; fi
    echo -e "    ${RED}-/+${RESET} ${short}"
    reason=$(echo "$replaces" | jq -r --arg addr "$addr" '.[] | select(.address == $addr) | if .action_reason then "      reason: \(.action_reason)" else empty end')
    if [[ -n "$reason" ]]; then echo -e "${DIM}${reason}${RESET}"; fi
  done
  echo ""
fi

if [[ "$create_count" -gt 0 ]]; then print_grouped "CREATE" "$GREEN" "+" "$creates" "false"; fi
if [[ "$update_count" -gt 0 ]]; then print_grouped "UPDATE" "$YELLOW" "~" "$updates" "true"; fi

if [[ "$read_count" -gt 0 ]]; then
  echo -e "${CYAN}${BOLD}READ (${read_count}):${RESET}"
  prev_group=""
  echo "$reads" | jq -r '.[].address' | sort | while IFS= read -r addr; do
    group=$(get_module_group "$addr"); short=$(strip_module_prefix "$addr" "$group")
    if [[ "$group" != "$prev_group" ]]; then echo -e "  ${DIM}${group}${RESET}"; prev_group="$group"; fi
    echo -e "    ${CYAN}> ${short}${RESET}"
  done
  echo ""
fi

if [[ "$noop_count" -gt 0 ]]; then echo -e "${DIM}NO-OP: ${noop_count} resources unchanged${RESET}"; echo ""; fi

echo -e "${BOLD}=====================================${RESET}"
echo -ne "${BOLD}Total: ${RESET}"
parts=()
[[ "$destroy_count" -gt 0 ]] && parts+=("${RED}${destroy_count} to destroy${RESET}")
[[ "$replace_count" -gt 0 ]] && parts+=("${RED}${replace_count} to replace${RESET}")
[[ "$create_count" -gt 0 ]] && parts+=("${GREEN}${create_count} to create${RESET}")
[[ "$update_count" -gt 0 ]] && parts+=("${YELLOW}${update_count} to update${RESET}")
[[ "$read_count" -gt 0 ]] && parts+=("${CYAN}${read_count} to read${RESET}")
[[ "$noop_count" -gt 0 ]] && parts+=("${DIM}${noop_count} unchanged${RESET}")
if [[ ${#parts[@]} -eq 0 ]]; then echo -e "${DIM}No changes. Infrastructure is up-to-date.${RESET}"
else echo -e "$(IFS=', '; echo "${parts[*]}")"; fi
echo ""
if [[ "$destroy_count" -gt 0 || "$replace_count" -gt 0 ]]; then
  echo -e "${RED}${BOLD}WARNING: This plan includes resource destruction. Review carefully.${RESET}"; echo ""
fi
PLAN_SUMMARY_EOF

chmod +x "$HOME/bin/tf-plan-summary"
echo -e "  ${GREEN}[OK]${RESET} ~/bin/tf-plan-summary installed"
echo ""

# ─── 3. Add shell functions to ~/.zshrc ─────────────────────────────────────

echo -e "${BOLD}  Configuring shell functions...${RESET}"

MARKER="# >>> terraform-toolkit-v2 >>>"
MARKER_END="# <<< terraform-toolkit-v2 <<<"

if grep -q "$MARKER" "$HOME/.zshrc" 2>/dev/null; then
  echo -e "  ${YELLOW}[SKIP]${RESET} Terraform toolkit block already in ~/.zshrc"
  echo -e "  ${DIM}  To reinstall, remove the block between${RESET}"
  echo -e "  ${DIM}  '$MARKER' and '$MARKER_END' then re-run.${RESET}"
else
  cat >> "$HOME/.zshrc" << 'ZSHRC_EOF'

# >>> terraform-toolkit-v2 >>>
export PATH="$HOME/bin:$PATH"

tplan() {
  if [[ ! -d ".terraform" ]]; then
    echo "--- No .terraform/ found, running terraform init ---"
    terraform init || return $?
    echo ""
  fi
  local plan_out=".tfplan.out"
  echo "--- Running terraform plan ---"
  terraform plan -input=false -out="$plan_out" "$@"
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "terraform plan failed (exit $exit_code)"
    return $exit_code
  fi
  echo ""
  tf-plan-summary "$plan_out"
}

tplan-summary() {
  local plan_file="${1:-.tfplan.out}"
  if [[ ! -f "$plan_file" ]]; then
    echo "ERROR: No plan file found at $plan_file"
    echo "Run 'tplan' first, or specify a plan file."
    return 1
  fi
  tf-plan-summary "$plan_file"
}

alias tfmt='terraform fmt -recursive .'
alias tval='terraform validate'

tlint() {
  if command -v tflint &>/dev/null; then
    echo "--- Running tflint ---"
    tflint --recursive
  elif command -v pre-commit &>/dev/null; then
    echo "--- Running pre-commit terraform hooks ---"
    pre-commit run terraform_tflint --all-files
  else
    echo "ERROR: Neither tflint nor pre-commit found in PATH."
    return 1
  fi
}

tlint-sec() {
  if command -v tfsec &>/dev/null; then
    echo "--- Running tfsec ---"
    tfsec .
  elif command -v pre-commit &>/dev/null; then
    echo "--- Running pre-commit tfsec hook ---"
    pre-commit run tfsec --all-files
  else
    echo "ERROR: Neither tfsec nor pre-commit found in PATH."
    return 1
  fi
}

tcheck() {
  local P='\033[0;32m' F='\033[0;31m' B='\033[1m' R='\033[0m'
  local failed=0 results=()

  echo ""
  echo -e "${B}--- Terraform Quality Check ---${R}"
  echo ""

  terraform fmt -check -recursive . >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then results+=("${P}  [PASS]${R} terraform fmt")
  else results+=("${F}  [FAIL]${R} terraform fmt -- run 'tfmt' to fix"); failed=1; fi

  terraform validate -no-color >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then results+=("${P}  [PASS]${R} terraform validate")
  else results+=("${F}  [FAIL]${R} terraform validate -- run 'tval' for details"); failed=1; fi

  if command -v tflint &>/dev/null; then
    tflint --recursive --no-color >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then results+=("${P}  [PASS]${R} tflint")
    else results+=("${F}  [FAIL]${R} tflint -- run 'tlint' for details"); failed=1; fi
  else results+=("\033[0;33m  [SKIP]${R} tflint -- not installed"); fi

  if command -v tfsec &>/dev/null; then
    local tfsec_out issue_count
    tfsec_out=$(tfsec . --no-color --soft-fail 2>&1)
    issue_count=$(echo "$tfsec_out" | grep -c "Result" 2>/dev/null || echo "0")
    if [[ "$issue_count" -eq 0 ]]; then results+=("${P}  [PASS]${R} tfsec")
    else results+=("${F}  [WARN]${R} tfsec -- ${issue_count} issue(s), run 'tlint-sec' for details"); fi
  else results+=("\033[0;33m  [SKIP]${R} tfsec -- not installed"); fi

  for r in "${results[@]}"; do echo -e "$r"; done
  echo ""
  if [[ $failed -eq 1 ]]; then echo -e "${F}${B}  Some checks failed.${R}"
  else echo -e "${P}${B}  All checks passed.${R}"; fi
  echo ""
  return $failed
}

tdiff() {
  echo ""; git diff --stat -- '*.tf' '*.yaml' '*.yml'
  echo ""; git diff --color -- '*.tf' '*.yaml' '*.yml'
}

tdiff-staged() {
  echo ""; git diff --cached --stat -- '*.tf' '*.yaml' '*.yml'
  echo ""; git diff --cached --color -- '*.tf' '*.yaml' '*.yml'
}

tcost() {
  if ! command -v infracost &>/dev/null; then
    echo "ERROR: infracost not found. Install with: brew install infracost"; return 1
  fi
  local full_mode=false
  [[ "${1:-}" == "--full" || "${1:-}" == "-f" ]] && full_mode=true

  local json_out
  json_out=$(infracost breakdown --path . --format json --show-skipped 2>/dev/null)
  if [[ -z "$json_out" ]] || ! echo "$json_out" | jq empty 2>/dev/null; then
    echo "ERROR: Failed to get cost estimate."; return 1
  fi

  local total resource_count free_count
  total=$(echo "$json_out" | jq -r '.totalMonthlyCost // "0"')
  resource_count=$(echo "$json_out" | jq '[.projects[0].breakdown.resources[] | select(.monthlyCost != null and (.monthlyCost | tonumber) > 0)] | length')
  free_count=$(echo "$json_out" | jq '[.projects[0].breakdown.resources[] | select(.monthlyCost == null or (.monthlyCost | tonumber) == 0)] | length')

  local W=74
  local B=$'\033[1m' G=$'\033[0;32m' Y=$'\033[0;33m' C=$'\033[0;36m'
  local RD=$'\033[0;31m' D=$'\033[2m' RS=$'\033[0m'

  echo ""
  echo -e "${B}  INFRACOST ESTIMATE${RS}"
  echo -e "${D}  $(pwd)${RS}"
  echo -e "${D}  $(printf '%.0s─' $(seq 1 $W))${RS}"

  local jq_query
  if [[ "$full_mode" == true ]]; then
    jq_query='
      [.projects[0].breakdown.resources[]
      | select(.monthlyCost != null and (.monthlyCost | tonumber) > 0)
      | { name: .name, cost: (.monthlyCost | tonumber),
          group: (if (.name | startswith("module.")) then (.name | capture("^(?<g>module\\.[^.]+)") | .g) else "(root)" end),
          subs: [.subresources[]? | select(.monthlyCost != null and (.monthlyCost | tonumber) > 0) | {name: .name, cost: (.monthlyCost | tonumber)}] }]
      | group_by(.group) | map({group: .[0].group, subtotal: (map(.cost) | add), resources: (sort_by(-.cost))})
      | sort_by(-.subtotal) | .[]
      | "G\t\(.group)\t\(.subtotal)", (.resources[] | "R\t\(.name)\t\(.cost)", (.subs[]? | "S\t\(.name)\t\(.cost)"))
    '
  else
    jq_query='
      [.projects[0].breakdown.resources[]
      | select(.monthlyCost != null and (.monthlyCost | tonumber) > 0)
      | { name: .name, cost: (.monthlyCost | tonumber),
          group: (if (.name | startswith("module.")) then (.name | capture("^(?<g>module\\.[^.]+)") | .g) else "(root)" end) }]
      | group_by(.group) | map({group: .[0].group, subtotal: (map(.cost) | add), resources: (sort_by(-.cost))})
      | sort_by(-.subtotal) | .[]
      | "G\t\(.group)\t\(.subtotal)", (.resources[] | "R\t\(.name)\t\(.cost)")
    '
  fi

  echo "$json_out" | jq -r "$jq_query" | while IFS=$'\t' read -r kind name cost; do
    if [[ "$kind" == "G" ]]; then
      cost_fmt=$(printf "%'.2f" "$cost")
      echo ""; printf "  ${B}%-50s %20s${RS}\n" "$name" "\$${cost_fmt}/mo"
    elif [[ "$kind" == "R" ]]; then
      group_prefix=$(echo "$name" | sed 's/^\(module\.[^.]*\)\..*/\1/')
      if [[ "$name" == module.* ]]; then short="${name#${group_prefix}.}"; else short="$name"; fi
      if [[ "$full_mode" == false && ${#short} -gt 48 ]]; then short="${short:0:45}..."; fi
      cost_fmt=$(printf "%'.2f" "$cost")
      cost_rounded=$(printf "%.0f" "$cost" 2>/dev/null)
      cost_color="$G"; [[ "$cost_rounded" -ge 500 ]] && cost_color="$RD"
      [[ "$cost_rounded" -lt 500 && "$cost_rounded" -ge 100 ]] && cost_color="$Y"
      if [[ "$full_mode" == true ]]; then
        printf "  ${D}│${RS}  ${C}%s${RS}\n" "$short"
        printf "  ${D}│${RS}  ${cost_color}%71s${RS}\n" "\$${cost_fmt}/mo"
      else
        printf "  ${D}│${RS}  ${C}%-48s${RS} ${cost_color}%20s${RS}\n" "$short" "\$${cost_fmt}/mo"
      fi
    elif [[ "$kind" == "S" ]]; then
      cost_fmt=$(printf "%'.2f" "$cost")
      cost_rounded=$(printf "%.0f" "$cost" 2>/dev/null)
      cost_color="$G"; [[ "$cost_rounded" -ge 500 ]] && cost_color="$RD"
      [[ "$cost_rounded" -lt 500 && "$cost_rounded" -ge 100 ]] && cost_color="$Y"
      printf "  ${D}│    ├─ %-44s${RS} ${cost_color}%20s${RS}\n" "$name" "\$${cost_fmt}/mo"
    fi
  done

  echo ""; echo -e "  ${D}$(printf '%.0s─' $(seq 1 $W))${RS}"
  local total_fmt total_num total_color
  total_fmt=$(printf "%'.2f" "$total"); total_num=$(printf "%.0f" "$total" 2>/dev/null)
  total_color="$G"; [[ "$total_num" -ge 10000 ]] && total_color="$RD"
  [[ "$total_num" -lt 10000 && "$total_num" -ge 1000 ]] && total_color="$Y"
  printf "  ${B}%-50s${RS} ${total_color}${B}%20s${RS}\n" "TOTAL" "\$${total_fmt}/mo"
  echo -e "  ${D}${resource_count} priced  ·  ${free_count} free${RS}"
  if [[ "$full_mode" == false ]]; then
    echo -e "  ${D}Run 'tcost --full' for expanded resource names and sub-costs${RS}"
  fi
  echo ""
}

thelp() {
  local C='\033[0;36m' G='\033[0;32m' Y='\033[0;33m'
  local D='\033[2m' B='\033[1m' R='\033[0m'
  echo ""
  echo -e "${B}  Terraform Helper Commands${R}"
  echo -e "${D}  ─────────────────────────────────────────────────────${R}"
  echo ""
  echo -e "${B}  Planning & Review${R}"
  echo -e "  ${G}tplan${R}            ${C}Plan + colored summary (auto-inits if needed)${R}"
  echo -e "  ${G}tplan-summary${R}    ${C}Show summary of an existing plan file${R}"
  echo -e "  ${G}tcost${R}            ${C}Estimate monthly cost (--full for expanded view)${R}"
  echo ""
  echo -e "${B}  Validation & Linting${R}"
  echo -e "  ${G}tcheck${R}           ${C}Run all checks: fmt + validate + tflint + tfsec${R}"
  echo -e "  ${G}tval${R}             ${C}Run terraform validate${R}"
  echo -e "  ${G}tfmt${R}             ${C}Format .tf files recursively${R}"
  echo -e "  ${G}tlint${R}            ${C}Run tflint linter${R}"
  echo -e "  ${G}tlint-sec${R}        ${C}Run tfsec security scan${R}"
  echo ""
  echo -e "${B}  Git & Diff${R}"
  echo -e "  ${G}tdiff${R}            ${C}Show .tf/.yaml changes since last commit${R}"
  echo -e "  ${G}tdiff-staged${R}     ${C}Show staged .tf/.yaml changes${R}"
  echo ""
  echo -e "${B}  Help${R}"
  echo -e "  ${G}thelp${R}            ${C}Show this help${R}"
  echo ""
  echo -e "${D}  ─────────────────────────────────────────────────────${R}"
  echo -e "${D}  Usage: cd into any terraform directory, then run a command.${R}"
  echo ""
  echo -e "${Y}  Examples:${R}"
  echo -e "    ${D}\$${R} cd envs/dev && tplan"
  echo -e "    ${D}\$${R} tplan -target=module.gke"
  echo -e "    ${D}\$${R} tcost"
  echo -e "    ${D}\$${R} tcheck"
  echo -e "    ${D}\$${R} tdiff"
  echo ""
}
# <<< terraform-toolkit-v2 <<<
ZSHRC_EOF

  echo -e "  ${GREEN}[OK]${RESET} Shell functions added to ~/.zshrc"
fi
echo ""

# ─── 4. Create global Cursor rule ───────────────────────────────────────────

echo -e "${BOLD}  Installing Cursor rule...${RESET}"
mkdir -p "$HOME/.cursor/rules"

cat > "$HOME/.cursor/rules/terraform.mdc" << 'CURSOR_RULE_EOF'
---
description: Terraform best practices and conventions for GCP infrastructure
globs: ["**/*.tf", "**/config/**/*.yaml"]
alwaysApply: false
---

# Terraform Best Practices

## Module Structure

Every reusable module must contain exactly these files:

- `main.tf` — Resource definitions
- `variables.tf` — Input variables with type, description, and defaults
- `outputs.tf` — Output values
- `versions.tf` — Terraform and provider version constraints

Do not put resources in `variables.tf` or `outputs.tf`.

## Variable Definitions

Every variable must have:
- `type` — Use `object()` with `optional()` for complex structures
- `description` — One-line explanation
- `default` — Sensible default when possible; omit only for required inputs

Use `validation` blocks for enum-like values and business constraints.
Use `nullable = false` when null is never valid.

```hcl
variable "activation_policy" {
  description = "When the instance should be active: ALWAYS, NEVER, or ON_DEMAND."
  type        = string
  default     = "ALWAYS"
  nullable    = false
  validation {
    condition     = contains(["ALWAYS", "NEVER", "ON_DEMAND"], var.activation_policy)
    error_message = "Must be ALWAYS, NEVER, or ON_DEMAND."
  }
}
```

## Naming Conventions

- Resources and variables: `snake_case`
- Resource names should be descriptive (e.g., `google_sql_database_instance.primary` not `.this`)
- GCP resource name prefix: `gcp-<org>-<team>-<env>-<purpose>`
- Modules referenced as relative paths: `../../modules/<module>`

## YAML-Driven Configuration Pattern

For bulk resource creation, use YAML config files parsed with `fileset()` + `yamldecode()`:

1. Place YAML configs under `config/<category>/<team>/`
2. Parse in locals with `fileset()` + `yamldecode()`
3. Normalize optional fields with `try()` and sensible defaults
4. Feed into modules via `for_each` on a map keyed by resource name

Every YAML file must start with `---`.

## Dynamic Blocks

Prefer `dynamic` blocks with null-check `for_each` over conditional resources:

```hcl
dynamic "backup_configuration" {
  for_each = local.enable_backup ? { 1 = 1 } : {}
  content { ... }
}

dynamic "psc_config" {
  for_each = var.psc_allowed_consumer_projects != null ? [""] : []
  content { ... }
}
```

## Security Requirements

Always consider when creating or modifying resources:

- **Encryption**: Use CMEK (`encryption_key_name`) for data-at-rest encryption
- **Private networking**: Use PSA or PSC — never expose databases via public IP unless explicitly required
- **SSL**: Set `ssl_mode` to at least `ENCRYPTED_ONLY` for database connections
- **Deletion protection**: Enable both `gcp_deletion_protection` and `terraform_deletion_protection` for production
- **Secrets**: Reference via Secret Manager paths, never hardcode passwords in `.tf` files
- **Labels**: Always attach labels with at least `environment` and `component` keys

## Provider Configuration

Pin providers in `versions.tf` with range constraints:

```hcl
terraform {
  required_version = ">= 1.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "> 3.6, < 7"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "> 3.6, < 7"
    }
  }
}
```

Use `google-beta` provider for resources requiring beta features.

## Lifecycle Rules

Use `ignore_changes` sparingly and only for attributes managed outside Terraform.
Always add a comment explaining why:

```hcl
lifecycle {
  ignore_changes = [
    settings[0].disk_autoresize,  # managed by GCP autoresize
  ]
}
```

## Common Pitfalls

- Changing a `for_each` key (e.g., resource name in YAML) destroys and recreates the resource
- Modifying `encryption_key_name` forces resource replacement on Cloud SQL
- Changing `database_version` major version forces replacement
- `network_config` changes between PSA and PSC are destructive
- `root_password` changes are in-place but may cause brief connectivity issues
- `moved` blocks should be used when renaming resources to avoid destroy+create

## State Management

- Use GCS backend with environment-specific prefixes
- Never hardcode state bucket paths in resource configurations
- Use `terraform_remote_state` data sources for cross-environment references

## Code Quality Checks

Before pushing changes, run these checks (available as shell commands):
- `tfmt` — Format all .tf files
- `tval` — Validate configuration
- `tlint` — Run tflint
- `tcheck` — Run all checks in sequence
- `tdiff` — Review .tf/.yaml changes since last commit
CURSOR_RULE_EOF

echo -e "  ${GREEN}[OK]${RESET} ~/.cursor/rules/terraform.mdc installed"
echo ""

# ─── 5. Register Infracost API key ─────────────────────────────────────────

if command -v infracost &>/dev/null; then
  if ! infracost configure get api_key &>/dev/null || [[ -z "$(infracost configure get api_key 2>/dev/null)" ]]; then
    echo -e "${BOLD}  Infracost setup...${RESET}"
    echo -e "  ${YELLOW}[ACTION]${RESET} Run this to register (free): ${BOLD}infracost auth login${RESET}"
    echo ""
  fi
fi

# ─── Done ───────────────────────────────────────────────────────────────────

echo -e "${GREEN}${BOLD}  Setup complete!${RESET}"
echo ""
echo -e "  ${DIM}Open a new terminal or run:${RESET}  source ~/.zshrc"
echo -e "  ${DIM}Then type:${RESET}                    thelp"
echo ""
