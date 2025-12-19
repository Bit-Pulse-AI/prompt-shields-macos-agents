enum AuthState: Sendable {
    case loggedIn
    case acceptTerms
    case loggedOut(Error? = nil)
    case undetermined
}
