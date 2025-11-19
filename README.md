## PromptShields for macOS

Context‑aware AI assistance for macOS. PromptShields monitors focused text fields system‑wide (with your permission), surfaces helpful actions in a subtle overlay, and can inject results back into the active app. It integrates authentication, secure storage, and a clean SwiftUI architecture tailored for macOS.


### Highlights

- **Overlay UI on top of any app**: Renders hidden title bar SwiftUI windows that follow the focused text element.
- **Accessibility‑powered context**: Detects the focused field, extracts text safely, and updates in near real‑time.
- **Direct text injection**: Writes results back into the focused element or selection.
- **LLM‑backed suggestions**: Calls backend APIs for analysis and suggestions, with pluggable providers (Azure PromptShields, Google).
- **Auth0 authentication**: Secure login, token refresh, and Keychain storage.
- **SwiftData persistence**: Local caching of profiles, preferences, suggestions, and more.
- **Status Bar menu**: Quick access to show the main window, About, and Quit.
- **Swift Package Manager**: Pure SPM dependencies (Auth0, JWTDecode, Stripe, Google/Firebase utils, etc.).


### Requirements

- macOS 14.0+ (Sonoma or later) — uses SwiftData and modern SwiftUI APIs
- Xcode 15 or later
- Swift Package Manager (built into Xcode)


### Quick start

1) Clone and open the project
   - Open `PromptShields.MacOS.Widget.xcodeproj` in Xcode.

2) Configure signing
   - Select the `PromptShields.MacOS.Widget` target and enable automatic signing with your team.

3) First run
   - Build and run the app (Cmd+R).
   - On first launch, macOS will prompt for Accessibility permissions. Grant access in:
     System Settings → Privacy & Security → Accessibility → enable PromptShields.
   - Use the Status Bar item (“PS” icon) to show the main window if needed.

4) Verify deep link scheme
   - The app registers `promptshields://` for web billing flows. This is already configured in `Resources/Info.plist`.


### Configuration

- Backend base URL — `PromptShields.MacOS.Widget/Resources/Const.swift`

```swift
let baseURL = "https://apim-3n5enx234xc3g.azure-api.net/fjords/api/v1"
// let baseURL = "http://localhost:8000/api/v1"
```

- Web billing callback URLs — `Resources/Const.swift`

```swift
let webBillingScheme = "promptshields"
let webBillingSuccessURL = "\(webBillingScheme)://success"
let webBillingCancelURL = "\(webBillingScheme)://cancel"
```

- Auth0 — `PromptShields.MacOS.Widget/Auth0.plist`
  - Replace with your own tenant values if needed (ClientId, Domain).

- URL scheme — `PromptShields.MacOS.Widget/Resources/Info.plist`
  - The `CFBundleURLTypes` entry for `promptshields` is preconfigured.


### Using PromptShields

- The app runs with a small Status Bar item (PS). Use it to:
  - Show the main PromptShields window
  - Open About
  - Quit the app
- When a text field is focused in any app and permissions are granted, an overlay will align with the field. Actions may appear depending on context and app state; results can be injected back into the focused element or selection.


### Architecture overview

- **SwiftUI App structure** — `MainApp.swift`
  - Multiple scenes: `main-window`, `overlay-render`, `action-render`.
  - Borderless/hidden title bar windows with specific levels and behaviors to float and align to targets.

- **Accessibility** — `Managers/Accessibility`
  - `AccessibilityManagerImpl`: polls for focus changes (with a pausable timer), prompts for permissions, updates overlay state.
  - `TextExtractor`: recursively and safely extracts text via `AXUIElement`.
  - `TextInjector`: writes text back to focused elements or selections.
  - `AXUIElementSafeWrapper`: safe, defensive interactions with the AX APIs.

- **Networking (services)** — `Managers/Networking`
  - `NetworkManagerImpl`: async/await requests with robust logging and error handling; auto‑retry on 401/403 after refresh via `TokenRefreshManager`.
  - Common helpers: `RequestBuilder`, `JSONCoder`, `NetworkError`, `PaginatedResponse`, `ListResponse`, `URLSessionProtocol`.
  - Typed services per domain:
    - `LLMNetworkService` (`/llm/`): fetch available LLM providers.
    - `SuggestionNetworkService`:
      - `POST /suggestion/analyze/` analyze text (provider, group, team, app).
      - `GET /teams/{teamId}/suggestion_group/{suggestionGroupId}/suggestions` list suggestions (offset/limit).
      - `GET /suggestion/types` fetch available suggestion types.
      - `GET /teams/{teamId}/suggestion_group/{suggestionGroupId}` fetch suggestion group.
    - `ProfileNetworkService` (`/profiles/`): read current profile.
    - `UserNetworkService` (Auth0 SDK):
      - `webAuth()` login/logout, `userInfo` read, `users.patch` update names, refresh via `TokenRefreshManager`.
    - `OrganisationNetworkService` (`/tenants/{tenantId}/organisations`): CRUD + list with pagination.
    - `SubscriptionNetworkService`:
      - `GET /organisations/{organisationId}/subscriptions` list/read.
      - `POST /payment/checkout` Stripe checkout session creation.
      - `POST /payment/cancel` cancel subscription.
    - `TeamNetworkService` (`/subscriptions/{subscriptionId}/teams`): CRUD + list with pagination.
    - `TenantNetworkService` (`/tenants/{tenantId}`): read tenant.
    - `WebBillingNetworkService`: placeholder scaffolding for browser‑based billing flows (currently commented methods).

- **Auth** — `Managers/Auth`
  - Auth0 login, JWT decoding, refresh via `TokenRefreshManager`, credentials persisted in Keychain.

- **Domain services** — `Domain/Services`
  - `SuggestionDomainService`: orchestrates analyze/list operations; syncs via persistence layer.
  - `LLMDomainService`: fetches available LLM providers.

- **Persistence** — `Managers/Persistence` + SwiftData models in `Domain/Models/Peristent`
  - `PersistenceManagerImpl` is a `@ModelActor` wrapping SwiftData for async access.
  - Models are stored in `~/Library/Application Support/MyDatabase.sqlite` via `PersistenceStack`.
  - Entities registered: `SuggestionType`, `SuggestionGroup`, `Suggestion`, `Organisation`, `Subscription`, `Team`, `Tenant`, `User`, `UserPreferences`, `Profile`.
  - Key operations:
    - `insert(domain|domains)` to add local data.
    - `update(domain|domains)` to update by persistent identifier.
    - `query(predicate, sortDescriptors, limit)` to fetch lists.
    - `fetchItem(uid|predicate|identifier)` to fetch single items.
    - `syncLocalWithRemote(domain|domains)` to upsert remote data efficiently (uses `uuid`/hash keys).
    - `delete(domain|domains|entity:)` to remove data; `logout()` clears all entities.
  - `ObservableQueryable` provides a simple SwiftUI‑friendly observable wrapper that reloads data on `ModelContext.didSave`, with optional mapping.

- **Dependency Injection** — `Common/Injector.swift`
  - Lightweight `@Inject` property wrapper resolves concrete implementations in a central place.

- **UI** — `Screens/*` and `Common/Views`
  - Dashboard/Main/Account flows, overlay and action components, and a set of shared controls.


### Authentication & security

- Auth0 client/tenant is configured via `Auth0.plist`. Access/refresh tokens are stored in Keychain.
- Token refresh happens automatically on unauthorized responses. If refresh fails, the app posts a logout notification for the UI to handle.


### Billing and deep links

- The app uses a custom URL scheme `promptshields://` for billing callbacks:
  - Success: `promptshields://success`
  - Cancel: `promptshields://cancel`


### Capabilities & entitlements

- Accessibility (requires user approval)
- Keychain access (App Identifier prefix group)
- Associated Domains (for Auth0 web credentials)
- Temporary Apple Events exception for specific system preferences (see `*.entitlements`)


### Development workflow

- SwiftLint
  - Install: `brew install swiftlint`
  - Run from the repo root: `swiftlint`
  - Rules are configured in `.swiftlint.yml` (explicit style, length limits, no TODOs, etc.).

- Tests
  - Run unit and UI tests in Xcode (Cmd+U).
  - Test bundles are in `PromptShields.MacOS.WidgetTests` and `PromptShields.MacOS.WidgetUITests`.


### Troubleshooting

- Overlay not appearing
  - Ensure PromptShields is enabled under System Settings → Privacy & Security → Accessibility.
  - If you just granted access, quit and reopen the app (the app may prompt you).

- Can’t show the main window
  - Use the Status Bar item → “Show PromptShields”.

- Token refresh errors
  - On repeated 401/403, the app posts a logout event; sign in again.

- Deep link callbacks
  - Verify `promptshields://` scheme exists in `Info.plist` and that the browser or billing flow redirects to it.


### Privacy

PromptShields requires Accessibility permission to read and write to focused text fields. Text is processed only to provide the requested features (e.g., suggestions) and sent to the configured backend as needed. Tokens are stored securely in Keychain. Review your organization’s data handling policies before production use.


### Acknowledgements

Auth0, JWTDecode, Stripe, and Google/Firebase libraries are used via SPM.


### License

Proprietary — All rights reserved.

