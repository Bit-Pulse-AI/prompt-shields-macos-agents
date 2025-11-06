import Foundation

struct CheckoutRequest: SendableEncodable {
    let subscriptionTier: String
    let tenantId: String
    let organisationId: String
    let subscriptionId: String
    let billingPeriod: String
    let successURL: String
    let cancelURL: String

    enum CodingKeys: String, CodingKey {
        case tenantId = "tenant_id"
        case subscriptionTier = "subscription_tier"
        case organisationId = "organisation_id"
        case subscriptionId = "subscription_id"
        case billingPeriod = "billing_period"
        case successURL = "success_url"
        case cancelURL = "cancel_url"
    }
}

struct CancelSubscriptionRequest: SendableEncodable {
    let organisationId: String
    let subscriptionId: String

    enum CodingKeys: String, CodingKey {
        case organisationId = "organisation_id"
        case subscriptionId = "subscription_id"
    }
}
