import os
import Foundation

@propertyWrapper
struct Inject<T>: Sendable {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: Inject.self)
    )
    
    var wrappedValue: T {
        if T.self == TeamDomainService.self {
            return TeamDomainServiceImpl() as! T
        } else if T.self == TeamNetworkService.self {
            return TeamNetworkServiceImpl() as! T
        } else if T.self == SubscriptionDomainService.self {
            return SubscriptionDomainServiceImpl() as! T
        } else if T.self == SubscriptionNetworkService.self {
            return SubscriptionNetworkServiceImpl() as! T
        } else if T.self == OrganisationDomainService.self {
            return OrganisationDomainServiceImpl() as! T
        } else if T.self == OrganisationNetworkService.self {
            return OrganisationNetworkServiceImpl() as! T
        } else if T.self == PersistenceManager.self {
            return PersistenceManagerImpl.shared as! T
        } else if T.self == KeychainManager.self {
            return KeychainManagerImpl.shared as! T
        } else if T.self == ProfileDomainService.self {
            return ProfileDomainServiceImpl() as! T
        } else if T.self == ProfileNetworkService.self {
            return ProfileNetworkServiceImpl() as! T
        } else if T.self == UserDomainService.self {
            return UserDomainServiceImpl() as! T
        } else if T.self == UserNetworkService.self {
            return UserNetworkServiceImpl() as! T
        } else if T.self == UserPreferencesDomainService.self {
            return UserPreferencesDomainServiceImpl() as! T
        } else if T.self == NetworkManager.self {
            return NetworkManagerImpl() as! T
        } else {
            logger.error("Missing injectable type \(T.self)")
            fatalError()
        }
    }
}
