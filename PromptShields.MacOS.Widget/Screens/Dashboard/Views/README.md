# Dashboard Views Structure

This directory contains the refactored dashboard view components, broken down for better readability and maintainability.

## Components

### `DashboardView.swift` (Main Container)
- **Purpose**: Main container view that orchestrates the dashboard layout
- **Responsibilities**: 
  - Layout management (HStack with sidebar and content)
  - Background and toolbar configuration
  - Task initialization

### `DashboardSidebar.swift`
- **Purpose**: Handles all sidebar-related functionality
- **Responsibilities**:
  - Sidebar width calculation
  - Compact and expanded sidebar states
  - Channel list management
  - User profile display
  - Collapse/expand functionality

### `DashboardContentArea.swift`
- **Purpose**: Manages the main content area switching
- **Responsibilities**:
  - Content state management (channel, no channel, settings)
  - Active channel view
  - No channel view
  - Settings view

### `DashboardPopupManager.swift`
- **Purpose**: Centralized popup/sheet management
- **Responsibilities**:
  - Search popup
  - PII detection popup
  - LLM selection popup
  - Project creation popup
  - Delete confirmation popup

### `DashboardConstants.swift`
- **Purpose**: Centralized constants and enums
- **Contains**:
  - `DashboardContentState` enum
  - `PopupDeleteType` enum
  - `PopupType` enum
  - `DashboardViewParameters` struct

## Benefits of This Structure

1. **Single Responsibility**: Each component has a clear, focused purpose
2. **Maintainability**: Easier to locate and modify specific functionality
3. **Testability**: Individual components can be tested in isolation
4. **Reusability**: Components can be reused in other contexts
5. **Readability**: Much easier to understand the overall structure

## Usage

The main `DashboardView` automatically uses all these components:

```swift
DashboardView(viewModel: viewModel)
```

All components are generic over the `DashboardViewModel` protocol, ensuring type safety and flexibility. 