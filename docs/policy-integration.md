# Policy enforcement: Promptly ↔ AI-SPM dashboard

## Roles

- **AI-SPM dashboard** (`Bit-Pulse-AI/ai-spm-dashboard`) is the **PDP** (Policy Decision Point). It owns policy templates, instance tuning, governance UI, audit feed.
- **Promptly** (this repo) is the **PEP** (Policy Enforcement Point). It runs the configured policies on every prompt the user is about to send, takes the configured action (`redact`, `block`, `flag`, `log`), and reports violations back.

The two communicate over HTTPS:

```
                  GET /api/policies              POST /api/policies/violations
  AI-SPM Dashboard ◀───── Promptly ──────────────────────────▶ AI-SPM Dashboard
       (PDP)             (PEP, on Mac)                              (audit feed)
```

## Wire format

### `GET /api/policies`

Returns the bundle of *active* policy instances and their referenced templates. Promptly polls every 5 minutes (configurable via `PolicyClient.refreshInterval`).

```jsonc
{
  "instances": [{
    "id": "policy-abc",
    "name": "Block PII in customer-facing prompts",
    "templateId": "owasp-llm02-pii-output",
    "templateVersion": "1.0.0",
    "parameterValues": {
      "pii_confidence": 0.85,
      "redact_categories": ["EMAIL", "PHONE", "PERSON"]
    },
    "enforcementMode": "redact",     // log | flag | block | redact
    "severity": "high",
    "appliesTo": {
      "applicationIds": ["chatgpt", "claude"],   // empty = all
      "dataClassifications": ["pii"],
      "riskTiers": ["high"],
      "departments": []
    },
    "allowList": [],
    "status": "active",
    "createdAt": "2026-04-23T10:00:00Z",
    "updatedAt": "2026-04-23T10:00:00Z"
  }],
  "templates": [{
    "id": "owasp-llm02-pii-output",
    "name": "Sensitive Info Disclosure",
    "version": "1.0.0",
    "category": "OWASP_LLM",
    "severity": "high",
    "description": "...",
    "rationale": "...",
    "triggers": [{"stage": "input", "description": "Inbound prompts"}],
    "detectors": [
      { "id": "pii-named-entity", "type": "pii_detector", "configRef": "pii_confidence", "description": "..." },
      { "id": "pii-regex",        "type": "regex",        "configRef": "pii_patterns",   "description": "..." }
    ],
    "actions": [{ "type": "redact", "description": "Replace with placeholders" }],
    "tags": ["pii", "owasp"],
    "regulatoryReferences": ["GDPR Art. 5", "CCPA 1798.100"],
    "owaspReference": "LLM02"
  }],
  "snapshotAt": "2026-04-23T10:05:12Z"
}
```

Swift counterparts: `ActivePoliciesResponse`, `PolicyInstance`, `PolicyTemplate` in [`PolicyTypes.swift`](../PromptShields.MacOS.Widget/Managers/Policy/PolicyTypes.swift).

### `POST /api/policies/violations`

Promptly POSTs one envelope per triggered policy after enforcement. **Never includes raw prompt text** — only a SHA-256 hex of the prompt and the matched substring (capped at 200 chars). The dashboard rejects anything where `promptHash` isn't a 64-char hex digest.

```jsonc
{
  "id": "violation-uuid",
  "policyInstanceId": "policy-abc",
  "applicationId": "chatgpt",
  "timestamp": "2026-04-23T10:05:30Z",
  "actionTaken": "redact",
  "severity": "high",
  "detectorId": "pii-named-entity",
  "promptHash": "ab12...64hex",
  "user": "anna@example.com",
  "evidence": {
    "detectorOutput": "Detected EMAIL",
    "matchedPattern": "anna@example.com",
    "confidence": 0.9
  },
  "reviewed": false
}
```

Response: `201 { accepted: true, id: "violation-uuid" }` or `400 { error: "..." }`.

## Detector parity

Promptly implements detectors in pure Swift on the device — never calls back to the dashboard at evaluation time. Detector types it understands today:

| Type | Implementation |
|---|---|
| `regex` | `NSRegularExpression`, runs `parameterValues[configRef]` as `[String]` patterns |
| `keyword_list` | Case-insensitive substring match |
| `pii_detector` | Reuses `PIIDetector` (email, phone, card, SSN, IBAN, IP, currency, person-name) |
| `secrets_scanner` | `PIIDetector.apiKey` + `.jwt` + `-----BEGIN ... PRIVATE KEY-----` |
| `entropy` | Shannon-entropy on tokens ≥20 chars, threshold 4.5 bits/char |
| `classifier` | Heuristic vocab-based stand-in for the dashboard's ML classifier |
| `llm_judge`, `rate_counter` | **Skipped** on-device — these need cloud state |

When a policy uses a detector type Promptly doesn't run, that detector is silently skipped (no false negatives surface as false positives).

## Action precedence

Multiple instances can match the same prompt. Strongest-wins:

```
allow < log < flag < redact < block
```

`PolicyEnforcer.stronger` is the single source of truth ([`PolicyEnforcer.swift`](../PromptShields.MacOS.Widget/Managers/Policy/PolicyEnforcer.swift)).

## App scope

- `PolicyInstance.appliesTo.applicationIds` is matched against `MonitoredApp.id` (e.g. `chatgpt`, `claude`, `notion`, `copilot`). Empty list = applies globally.
- The dashboard publishes app ids that match Promptly's `MonitoredApps.plist`. New AI tools added to the plist must be reflected in the dashboard's app catalogue.

## Configuration

Promptly reads the dashboard URL from `UserDefaults` key `ai.bit-pulse.promptshields.aiSPMDashboardURL`. Dev-machine override:

```bash
defaults write ai.bit-pulse.PromptShields-MacOS-Widget-Dev \
    ai.bit-pulse.promptshields.aiSPMDashboardURL \
    -string "https://dashboard.staging.promptly.app"
```

Absent that, the bootstrap installs `NullPolicyTransport`: `PolicyEnforcer.evaluate()` always returns `.allow`, no network calls happen, and Promptly behaves exactly as it did before this integration. The local `PIIDetector`-driven Redaction-first UX continues to work.

Production builds will move the URL into the gitignored `Resources/<env>/Const.swift` once the dashboard goes GA.

## Schema sync

The two repos drift unless tests pin the wire format:

- **Promptly** [`PolicyTypesTests`](../PromptShields.MacOS.WidgetTests/PolicyTypesTests.swift) decodes a JSON literal that matches the dashboard's `PolicyTemplate` + `PolicyInstance` shape exactly. A rename in the TS schema (`enforcementMode` → `mode`, etc.) will fail the Swift test on CI before the macOS app ships against a broken contract.
- **Dashboard** route handlers ([`/api/policies`](../../ai-spm-dashboard/app/api/policies/route.ts), [`/api/policies/violations`](../../ai-spm-dashboard/app/api/policies/violations/route.ts)) re-export the canonical TS types so Next.js typechecking catches drift on the dashboard side.

When you need to change the wire format:

1. Update the TS types in `ai-spm-dashboard/lib/policy-templates/types.ts`.
2. Mirror the change in `PromptShields.MacOS.Widget/Managers/Policy/PolicyTypes.swift`.
3. Update the test JSON literal in `PolicyTypesTests`.
4. Bump `templateVersion` on any affected templates so existing instances detect the upgrade.

## Failure modes

| Scenario | Behaviour |
|---|---|
| Dashboard URL not configured | `NullPolicyTransport` — local-only mode (PIIDetector still works) |
| Dashboard returns 5xx / network down | `PolicyClient.lastError` is set; in-memory cache from last successful fetch keeps serving until refresh succeeds. Fail-open: if there's *no* prior cache, `evaluate()` returns `.allow` |
| Detector type unknown to PEP | Detector skipped, others on the same template still run |
| `parameterValues` missing the ref | Detector returns no match, no crash |

## Roadmap

- **PR-12 in `promptly-prd.md`** — Jira correlation: dashboard ingests Jira tickets and joins against `PolicyViolation.timestamp` to produce a "tickets avoided" metric.
- **PR-15 in `promptly-prd.md`** — URL-level app gating in Promptly: violations include `applicationUrl` so the dashboard can scope per-domain rules (e.g. only enforce inside chat.openai.com tabs, not all of Chrome).
- **Backend persistence**: today the dashboard's instance store is in-memory + fixture-seeded. Move to a real DB (Supabase / Neon) before the first paying customer.
- **Bearer auth**: the v1 transport accepts an optional `bearerTokenProvider` closure but doesn't wire one yet. Hook into `AuthenticationManagerImpl` once tenant scoping is needed.
