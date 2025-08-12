import SwiftUI

extension View {
    func roundedCorners(radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(SpecificRoundedCornerRectangle(radius: radius, corners: corners))
    }
    func showLoading(isLoading: Bool) -> some View {
        modifier(LoadingModifier(isLoading: isLoading))
    }
//    func showAlert(alertData: AlertData?, action: @escaping () async -> Void) -> some View {
//        modifier(AlertModifier(alertData: alertData,
//                               action: action))
//    }
    func navigationTitle(navigationTitle: String?) -> some View {
        modifier(NavigationTitleModifier(navigationTitle: navigationTitle))
    }
    
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

private struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        edges.map { edge -> Path in
            switch edge {
            case .top: return Path(.init(x: rect.minX, y: rect.minY, width: rect.width, height: width))
            case .bottom: return Path(.init(x: rect.minX, y: rect.maxY - width, width: rect.width, height: width))
            case .leading: return Path(.init(x: rect.minX, y: rect.minY, width: width, height: rect.height))
            case .trailing: return Path(.init(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height))
            }
        }.reduce(into: Path()) { $0.addPath($1) }
    }
}
