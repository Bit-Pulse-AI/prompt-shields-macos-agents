enum AuthState: Sendable {
    case loggedIn
    case loggedOut(Error? = nil)
    case undetermined
}
