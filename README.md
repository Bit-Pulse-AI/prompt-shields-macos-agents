# PromptShields macOS Widget

A production-grade macOS menu bar application that provides AI-powered text suggestions and prompt enhancement through system-wide accessibility integration.

## Overview

PromptShields is a native macOS application built with SwiftUI that monitors focused text fields across all applications and provides intelligent suggestions using LLM-powered analysis. The app runs as a menu bar widget with floating overlay windows that appear contextually near active text inputs.

### Key Features

- **System-wide Text Detection**: Monitors focused text fields across all macOS applications using the Accessibility API
- **AI-Powered Suggestions**: Analyzes text and provides context-aware suggestions via backend LLM services
- **Floating Overlay UI**: Non-intrusive overlay windows that appear near active text fields
- **Secure Local Storage**: Encrypted persistence using SwiftData with AES-256-GCM encryption
- **Auth0 Integration**: Secure authentication with automatic token refresh
- **Team & Organization Support**: Multi-tenant architecture with team-based access control
- **Stripe Billing Integration**: Subscription management with multiple tiers

## Requirements

- **macOS**: 14.0 (Sonoma) or later
- **Xcode**: 15.0 or later
- **Swift**: 5.9+ with Swift 6 language mode enabled

## Architecture

The application follows **SOLID principles** and is designed for **Swift 6 strict concurrency**:

```
PromptShields.MacOS.Widget/
├── Common/
│   ├── DependencyContainer.swift    # IoC container for dependency injection
│   ├── Injector.swift               # @Inject property wrapper
│   ├── PausableTimer.swift          # Adaptive polling timer
│   └── Extensions/
│       ├── SecureString.swift       # AES-GCM encryption extensions
│       └── String.swift             # Utility extensions
├── Domain/
│   ├── Models/
│   │   ├── Common/Domain.swift      # Domain protocol & base types
│   │   └── Persistent/              # SwiftData models with encryption
│   └── Services/                    # Domain services (business logic)
├── Managers/
│   ├── Accessibility/               # macOS Accessibility API integration
│   ├── Auth/                        # Auth0 authentication
│   ├── Keychain/                    # Secure credential storage
│   ├── Networking/                  # API client & services
│   └── Persistence/                 # SwiftData persistence layer
├── Screens/                         # SwiftUI views
└── Resources/                       # Assets & configuration
```

### Design Principles

#### SOLID Compliance

- **Single Responsibility**: Each class has one reason to change
- **Open/Closed**: New dependencies added via registration, not code modification
- **Liskov Substitution**: All protocols can be substituted with mocks for testing
- **Interface Segregation**: Focused protocols (e.g., `NetworkManager`, `KeychainManager`)
- **Dependency Inversion**: Depends on abstractions via `DependencyContainer`

#### Swift 6 Concurrency

- All shared state uses `actor` isolation or `Sendable` conformance
- `@MainActor` for UI-bound operations
- No data races - verified with strict concurrency checking
- Structured concurrency with `Task` and `async/await`

## Setup

### 1. Clone & Open

```bash
git clone <repository-url>
cd prompt-shields-macos-widget
open PromptShields.MacOS.Widget.xcodeproj
```

### 2. Configure Auth0

Create or update `Auth0.plist` with your credentials:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>ClientId</key>
    <string>YOUR_AUTH0_CLIENT_ID</string>
    <key>Domain</key>
    <string>YOUR_AUTH0_DOMAIN</string>
</dict>
</plist>
```

### 3. Configure API Endpoint

Update `Resources/Const.swift`:

```swift
let baseURL = "https://your-api-endpoint.com/api/v1"
```

### 4. Build & Run

1. Select the `PromptShields.MacOS.Widget` scheme
2. Build and run (⌘R)
3. Grant Accessibility permissions when prompted

## Accessibility Permissions

The app requires Accessibility permissions to detect focused text fields:

1. Open **System Preferences** → **Privacy & Security** → **Accessibility**
2. Add PromptShields to the allowed applications
3. Restart the app if prompted

## Dependency Injection

The app uses a custom IoC container for dependency injection:

```swift
// Registration (in DependencyContainer.swift)
container.register(UserDomainService.self) { UserDomainServiceImpl() }
container.registerSingleton(KeychainManager.self, instance: KeychainManagerImpl.shared)

// Usage
struct MyService {
    @Inject private var userService: UserDomainService
    @Inject private var keychain: KeychainManager
}
```

### Available Property Wrappers

| Wrapper | Description |
|---------|-------------|
| `@Inject<T>` | Standard injection, crashes if not registered |
| `@LazyInject<T>` | Deferred resolution, useful for circular dependencies |
| `@OptionalInject<T>` | Returns `nil` if not registered |

## Network Services

| Service | Responsibility |
|---------|---------------|
| `LLMNetworkService` | Available LLM providers |
| `SuggestionNetworkService` | Text analysis & suggestions |
| `UserNetworkService` | Auth0 authentication |
| `ProfileNetworkService` | User profile management |
| `OrganisationNetworkService` | Organization CRUD |
| `SubscriptionNetworkService` | Billing & subscriptions |
| `TeamNetworkService` | Team management |
| `TenantNetworkService` | Multi-tenant support |

All services use `performWithAutoRefresh` for automatic token refresh on 401/403 responses.

## Persistence

### SwiftData Models

All persistent models use AES-256-GCM encryption for sensitive fields:

| Model | Description |
|-------|-------------|
| `User` | User profile with encrypted PII |
| `Profile` | Default tenant/org/team references |
| `Suggestion` | Analyzed text with suggestions |
| `SuggestionGroup` | Grouped suggestions |
| `Organisation` | Organization with subscriptions |
| `Subscription` | Billing tier & Stripe data |
| `Team` | Team with members |
| `Tenant` | Top-level tenant |
| `UserPreferences` | User settings |

### Encryption

```swift
// Automatic encryption via property extension
let encrypted = "sensitive data".encrypt  // AES-256-GCM
let decrypted = encrypted.decrypt

// Encryption key stored in Keychain
try keychainManager.saveEncryptionKey()
let key = try keychainManager.loadEncryptionKey()
```

## Security

### Implemented Security Measures

- **AES-256-GCM Encryption**: All sensitive data encrypted at rest
- **Keychain Storage**: Credentials stored in macOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- **Hashed Identifiers**: Service/account identifiers hashed with SHA-512
- **Token Refresh**: Automatic OAuth token refresh with secure storage
- **No Hardcoded Secrets**: All secrets loaded from configuration files
- **Fail-Safe Encryption**: Graceful degradation on encryption failures (non-crashing)

### Security Best Practices

1. Never commit `Auth0.plist` with real credentials
2. Use environment-specific API endpoints
3. Rotate encryption keys periodically
4. Monitor for `tokenRefreshFailed` notifications

## Testing

### Unit Tests

```bash
# Run all tests
xcodebuild test -scheme PromptShields.MacOS.Widget -destination 'platform=macOS'
```

### Test Coverage

- `AuthManagerTests` - Authentication flow
- `NetworkManagerTests` - API client behavior
- `PaginationTests` - List pagination
- `QueryableMemoryLeakTests` - Memory management

### Mocking Dependencies

```swift
#if DEBUG
// Override for testing
DependencyContainer.shared.override(UserDomainService.self, with: MockUserService())
#endif
```

## Code Quality

### SwiftLint

The project uses SwiftLint with strict rules:

```bash
# Run SwiftLint
swiftlint

# Auto-fix issues
swiftlint --fix
```

Key rules enforced:
- Line length: 120 (warning), 150 (error)
- Function body length: 40 (warning), 50 (error)
- Cyclomatic complexity: 10 (warning), 15 (error)
- No TODOs/FIXMEs in committed code

### Swift 6 Strict Concurrency

The project compiles with Swift 6 strict concurrency checking:

```swift
// In Package.swift or build settings
swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
```

## Troubleshooting

### Accessibility Not Working

1. Check System Preferences → Privacy & Security → Accessibility
2. Remove and re-add the app
3. Restart the application
4. If still failing, restart your Mac

### Authentication Issues

1. Check `Auth0.plist` configuration
2. Verify network connectivity
3. Check for `tokenRefreshFailed` notifications
4. Clear Keychain and re-authenticate

### Encryption Errors

1. Ensure encryption key exists: check Keychain for `encryptionToken`
2. If corrupted, delete and re-create:
   ```swift
   try keychainManager.deleteEncryptionKey()
   try keychainManager.saveEncryptionKey()
   ```
3. Note: This will invalidate all encrypted data

### Build Errors

1. Clean build folder (⇧⌘K)
2. Reset package caches: File → Packages → Reset Package Caches
3. Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [Auth0.swift](https://github.com/auth0/Auth0.swift) | 2.13.0 | Authentication |
| [JWTDecode.swift](https://github.com/auth0/JWTDecode.swift) | 3.3.0 | Token decoding |
| [SimpleKeychain](https://github.com/auth0/SimpleKeychain) | 1.3.0 | Keychain wrapper |
| [Firebase iOS SDK](https://github.com/firebase/firebase-ios-sdk) | 11.15.0 | Analytics |
| [Stripe iOS](https://github.com/stripe/stripe-ios) | 24.19.0 | Payments |

## License

Proprietary - All rights reserved.

## Support

For technical support, contact the development team or open an issue in the repository.
