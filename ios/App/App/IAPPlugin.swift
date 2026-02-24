import Foundation
import Capacitor
import StoreKit

@objc(IAPPlugin)
public class IAPPlugin: CAPPlugin {

    // Replace with your real App Store Connect product id(s)
    private let productIds: Set<String> = [
        "com.zencards.pro.monthly"
    ]

    // Fetch products to display price strings in JS UI
    @objc func getProducts(_ call: CAPPluginCall) {
        Task {
            do {
                let products = try await Product.products(for: Array(productIds))
                let payload = products.map { p in
                    return [
                        "id": p.id,
                        "displayName": p.displayName,
                        "displayPrice": p.displayPrice
                    ]
                }
                call.resolve(["products": payload])
            } catch {
                call.reject("Failed to load products: \(error.localizedDescription)")
            }
        }
    }

    // Purchase a subscription product
    @objc func purchase(_ call: CAPPluginCall) {
        guard let productId = call.getString("productId") else {
            call.reject("Missing productId")
            return
        }

        Task {
            do {
                let products = try await Product.products(for: [productId])
                guard let product = products.first else {
                    call.reject("Product not found")
                    return
                }

                let result = try await product.purchase()

                switch result {
                case .success(let verification):
                    let transaction = try self.checkVerified(verification)
                    await transaction.finish()

                    call.resolve([
                        "status": "success",
                        "productId": transaction.productID,
                        "transactionId": String(transaction.id),
                        "originalTransactionId": String(transaction.originalID)
                    ])

                case .userCancelled:
                    call.resolve(["status": "cancelled"])

                case .pending:
                    call.resolve(["status": "pending"])

                @unknown default:
                    call.resolve(["status": "unknown"])
                }

            } catch {
                call.reject("Purchase failed: \(error.localizedDescription)")
            }
        }
    }

    // Restore / refresh active entitlements
    @objc func getEntitlements(_ call: CAPPluginCall) {
        Task {
            var active: [String] = []

            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result else { continue }
                if self.productIds.contains(transaction.productID),
                   transaction.revocationDate == nil {
                    active.append(transaction.productID)
                }
            }

            call.resolve(["activeProductIds": active])
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw NSError(domain: "IAP", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unverified transaction"
            ])
        case .verified(let safe):
            return safe
        }
    }
}
