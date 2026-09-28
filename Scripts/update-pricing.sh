#!/usr/bin/env bash
# Erzeugt Sources/TokenStats/Resources/pricing.json aus der LiteLLM-Preisliste.
# Preise in $ pro Token. Fehlende Cache-Write-Preise: 5 min = 1,25 × Input, 1 h = 2 × Input
# (Anthropic-Standard); bei OpenAI gibt es keinen Cache-Write-Aufschlag.
set -euo pipefail
cd "$(dirname "$0")/.."
URL=https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json
curl -sfL "$URL" | jq --arg date "$(date +%F)" '
  {
    asOf: $date,
    source: "LiteLLM model_prices_and_context_window.json",
    models: (to_entries
      | map(select(
          (.value.litellm_provider == "anthropic" and (.key | test("^claude-")))
          or (.value.litellm_provider == "openai" and (.key | test("^(gpt-5|o[34]|codex)")))
        ))
      | map(select(.value.input_cost_per_token != null and .value.output_cost_per_token != null))
      | map({
          key: .key,
          value: {
            input: .value.input_cost_per_token,
            output: .value.output_cost_per_token,
            cacheRead: (.value.cache_read_input_token_cost // .value.input_cost_per_token),
            cacheWrite5m: (.value.cache_creation_input_token_cost
              // (if .value.litellm_provider == "anthropic" then .value.input_cost_per_token * 1.25 else .value.input_cost_per_token end)),
            cacheWrite1h: (.value.cache_creation_input_token_cost_above_1hr
              // (if .value.litellm_provider == "anthropic" then .value.input_cost_per_token * 2 else .value.input_cost_per_token end))
          }
        })
      | from_entries)
  }' > Sources/TokenStats/Resources/pricing.json
jq -r '"\(.models | length) Modelle, Stand \(.asOf)"' Sources/TokenStats/Resources/pricing.json
