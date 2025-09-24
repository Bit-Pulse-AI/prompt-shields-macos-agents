import Foundation
import SwiftUI
import AppKit
import os

// MARK: - Web Billing Manager

protocol WebBillingNetworkService: NetworkService {
//    func createCustomer(userId: String, email: String?, name: String?) async throws -> WebBillingCustomer
//    func getCustomer(customerId: String) async throws -> WebBillingCustomer
//    func getSubscription(customerId: String) async throws -> WebBillingSubscription?
//    func createCheckoutSession(customerId: String, priceId: String, successUrl: String?, cancelUrl: String?) async throws -> WebBillingCheckoutSession
//    func createPortalSession(customerId: String) async throws -> WebBillingPortalSession
//    func openWebBilling(url: String) async throws
//    func syncSubscriptionStatus(customerId: String) async throws -> WebBillingSubscription?
}

struct WebBillingNetworkServiceImpl: WebBillingNetworkService {
    @Inject
    private var networkManager: NetworkManager
    
    @Inject
    private var keychainManager: KeychainManager
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: WebBillingNetworkService.self)
    )
    
    // MARK: - Customer Management
    
//    func createCustomer(userId: String, email: String?, name: String?) async throws -> WebBillingCustomer {
//        let createCustomer = CreateCustomerRequest(
//            userId: userId,
//            email: email,
//            name: name,
//            metadata: ["app_user_id": userId]
//        )
//        
//        do {
//            let request = try RequestBuilder().request(
//                url: "\(baseURL)/billing/customers",
//                method: .POST,
//                body: createCustomer,
//                headers: keychainManager.applicationJSONAuthorizedHeader
//            )
//            let response: CreateCustomerResponse = try await networkManager.performWithAutoRefresh(request: request).decode()
//            
//            return WebBillingCustomer(
//                id: response.customerId,
//                email: response.email,
//                name: response.name,
//                createdAt: response.createdAt,
//                metadata: response.metadata
//            )
//        } catch {
//            logger.error("Failed to create customer: \(error)")
//            throw WebBillingError.networkError(error)
//        }
//    }
    
//    func getCustomer(customerId: String) async throws -> WebBillingCustomer {
//        do {
//            let request = try RequestBuilder().request(
//                url: "\(baseURL)/billing/customers/\(customerId)",
//                method: .GET,
//                headers: keychainManager.applicationJSONAuthorizedHeader
//            )
//            let response: CreateCustomerResponse = try await networkManager.performWithAutoRefresh(request: request).decode()
//            
//            return WebBillingCustomer(
//                id: response.customerId,
//                email: response.email,
//                name: response.name,
//                createdAt: response.createdAt,
//                metadata: response.metadata
//            )
//        } catch {
//            logger.error("Failed to get customer: \(error)")
//            throw WebBillingError.networkError(error)
//        }
//    }
//    
//    // MARK: - Subscription Management
//    
//    func getSubscription(customerId: String) async throws -> WebBillingSubscription? {
//        let request = try RequestBuilder().request(
//            url: "\(baseURL)/billing/customers/\(customerId)/subscription",
//            method: .GET,
//            headers: keychainManager.applicationJSONAuthorizedHeader
//        )
//        do {
//            let response: GetSubscriptionResponse = try await networkManager.performWithAutoRefresh(request: request).decode()
//            
//            guard let subscription = response.subscription else {
//                return nil
//            }
//            
//            return WebBillingSubscription(
//                id: subscription.id,
//                customerId: subscription.customerId,
//                productId: subscription.productId,
//                priceId: subscription.priceId,
//                status: subscription.status,
//                currentPeriodStart: subscription.currentPeriodStart,
//                currentPeriodEnd: subscription.currentPeriodEnd,
//                trialStart: subscription.trialStart,
//                trialEnd: subscription.trialEnd,
//                cancelAtPeriodEnd: subscription.cancelAtPeriodEnd,
//                billingCycleAnchor: subscription.billingCycleAnchor,
//                metadata: subscription.metadata
//            )
//        } catch {
//            logger.error("Failed to get subscription: \(error)")
//            throw WebBillingError.networkError(error)
//        }
//    }
//    
//    func syncSubscriptionStatus(customerId: String) async throws -> WebBillingSubscription? {
//        do {
//            let request = try RequestBuilder().request(
//                url: "\(baseURL)/billing/customers/\(customerId)/subscription/sync",
//                method: .POST,
//                headers: keychainManager.applicationJSONAuthorizedHeader
//            )
//            let response: SyncSubscriptionResponse = try await networkManager.performWithAutoRefresh(request: request).decode()
//            
//            guard let subscription = response.subscription else {
//                return nil
//            }
//            
//            return WebBillingSubscription(
//                id: subscription.id,
//                customerId: subscription.customerId,
//                productId: subscription.productId,
//                priceId: subscription.priceId,
//                status: subscription.status,
//                currentPeriodStart: subscription.currentPeriodStart,
//                currentPeriodEnd: subscription.currentPeriodEnd,
//                trialStart: subscription.trialStart,
//                trialEnd: subscription.trialEnd,
//                cancelAtPeriodEnd: subscription.cancelAtPeriodEnd,
//                billingCycleAnchor: subscription.billingCycleAnchor,
//                metadata: subscription.metadata
//            )
//        } catch {
//            logger.error("Failed to sync subscription: \(error)")
//            throw WebBillingError.networkError(error)
//        }
//    }
//    
//    // MARK: - Checkout and Portal
//    
//    func createCheckoutSession(customerId: String, priceId: String, successUrl: String?, cancelUrl: String?) async throws -> WebBillingCheckoutSession {
//        let request = CreateCheckoutSessionRequest(
//            customerId: customerId,
//            priceId: priceId,
//            successUrl: successUrl ?? webBillingSuccessURL,
//            cancelUrl: cancelUrl ?? webBillingCancelURL
//        )
//        
//        do {
//            let request = try RequestBuilder().request(
//                url: "\(baseURL)/billing/checkout/sessions",
//                method: .POST,
//                body: request,
//                headers: keychainManager.applicationJSONAuthorizedHeader
//            )
//            let response: CreateCheckoutSessionResponse = try await networkManager.performWithAutoRefresh(request: request).decode()
//            
//            return WebBillingCheckoutSession(
//                id: response.sessionId,
//                url: response.url,
//                customerId: customerId,
//                priceId: priceId,
//                successUrl: successUrl,
//                cancelUrl: cancelUrl,
//                expiresAt: response.expiresAt
//            )
//        } catch {
//            logger.error("Failed to create checkout session: \(error)")
//            throw WebBillingError.networkError(error)
//        }
//    }
//    
//    func createPortalSession(customerId: String) async throws -> WebBillingPortalSession {
//        let createPortalSessionRequest = CreatePortalSessionRequest(
//            customerId: customerId,
//            returnUrl: webBillingReturnURL
//        )
//        
//        do {
//            let request = try RequestBuilder().request(
//                url: "\(baseURL)/billing/portal/sessions",
//                method: .POST,
//                body: createPortalSessionRequest,
//                headers: keychainManager.applicationJSONAuthorizedHeader
//            )
//            
//            let response: CreatePortalSessionResponse = try await networkManager.performWithAutoRefresh(request: request).decode()
//            
//            return WebBillingPortalSession(
//                id: response.sessionId,
//                url: response.url,
//                customerId: customerId,
//                returnUrl: webBillingReturnURL,
//                expiresAt: response.expiresAt
//            )
//        } catch {
//            logger.error("Failed to create portal session: \(error)")
//            throw WebBillingError.networkError(error)
//        }
//    }
//    
//    func openWebBilling(url: String) async throws {
//        guard let billingUrl = URL(string: url) else {
//            throw WebBillingError.invalidUrl
//        }
//        
//        Task { @MainActor in
//            NSWorkspace.shared.open(billingUrl)
//        }
//        
//        logger.info("Opened web billing URL: \(url)")
//    }
}
