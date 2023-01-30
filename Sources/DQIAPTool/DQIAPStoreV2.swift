//
//  DQIAPStoreV2.swift
//  
//
//  Created by zhaoquan.du on 2023/1/30.
//

import Foundation
import StoreKit

public enum StoreError: Error {
    case failedVerification
}

@available(iOS 15.0, *)
public class DQIAPStoreV2 {
    
    static let shared: DQIAPStoreV2 = DQIAPStoreV2()
    typealias Transaction = StoreKit.Transaction
    
    private(set) var fuel: [Product] = []
    
    var updateListenerTask: Task<Void, Error>? = nil
    
//    var statusChanged:(DQIAPStatus) -> Void = {_ in
//
//    }

    private var currentTransaction:Transaction?
    private var currentOrder: DQIAPOrder?
    
    private init() {
        
    }
    weak var delegate: DQIAPDelegate?
    func install(delegate:DQIAPDelegate){
        currentOrder = DQIAPOrder.getLastOrderForKeychain()
        //Start a transaction listener as close to app launch as possible so you don't miss any transactions.
        self.updateListenerTask = listenForTransactions()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func getCurrentOrder()->DQIAPOrder?{
        return currentOrder
    }
    func canStartNewIAP() -> Bool{
        return currentOrder == nil
    }
    func finishCurrentOrder(){
        DQIAPPayment.shared.finishCurrentOrder()
        currentOrder?.deleteKeychainOrderRecord()
        currentOrder = nil
        guard let tran = currentTransaction else {
            return
        }
        currentTransaction = nil
        Task{
            await tran.finish()
        }
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            //Iterate through any transactions that don't come from a direct call to `purchase()`.
            for await result in Transaction.updates {
                do {
                    _ = try self.checkVerified(result)
//                    transaction.appAccountToken?.uuidString
                    
                    //Always finish a transaction.
                    self.finishCurrentOrder()
                    //MARK: - update gems
                    self.delegate?.orderStatusChanged(order: self.currentOrder, status: .complete)
                } catch {
                    self.delegate?.orderStatusChanged(order: self.currentOrder, status: .failed(error))
                    self.finishCurrentOrder()
                    //StoreKit has a transaction that fails verification. Don't deliver content to the user.
                    print("Transaction failed verification")
                }
            }
        }
    }

    func startIAPPayment(ids:[String], order:DQIAPOrder){
        
        self.currentOrder = order
        currentOrder?.saveToKeyChain()
        Task {
            
            if let pro = await requestProducts(ids:ids)?.last{
                
                _ = try? await  purchase(pro)
            }
           
        }
        
    }
    
    private func requestProducts(ids:[String]) async -> [Product]?{
        
        
            //During store initialization, request products from the App Store.
            do {
                //Request products from the App Store using the identifiers that the Products.plist file defines.
                
                let storeProducts = try await Product.products(for: ids)

                var newFuel: [Product] = []

                //Filter the products into categories based on their type.
                for product in storeProducts {
                    switch product.type {
                    case .consumable:
                        newFuel.append(product)
                        
                    case .nonConsumable:
                        break
                    case .autoRenewable:
                        break
                    case .nonRenewable:
                        break
                    default:
                        //Ignore this product.
                        print("Unknown product")
                    }
                }

                //Sort each product category by price, lowest to highest, to update the store.
                fuel = newFuel
                return newFuel
            } catch let error{
                self.delegate?.orderStatusChanged(order: currentOrder, status: .failed(DQIAPError(reason: "get product faile", code: -1)))
                finishCurrentOrder()
                print("Failed product request from the App Store server: \(error)")
                return nil
            }
        
        
        
    }
    
    private func purchase(_ product: Product) async throws -> Transaction? {
        /*
         UUID 是苹果定义的接口 UUID().uuidString 获取，格式如：4713AE2D-11A5-40EA-B836-CBCD1EC96A76。如果需要关联 用户ID 和开发者订单号，需要开发者自动映射，或者服务器端生成返回等
         */
        //Begin purchasing the `Product` the user selects.
                                          //6e738162-133f-4d11-b446-4293709529799328312
        let uuidString = UUID().uuidString//367E28C7-CF53-438A-98C3-24DFA11706BF
        print("------uuid ------: \(uuidString)")
        let uuid = Product.PurchaseOption.appAccountToken(UUID.init(uuidString: uuidString)!)
        let result = try await product.purchase(options: [uuid])//options: Set<Product.PurchaseOption>([.appAccountToken(UUID(uuidString: "uid1")!)]))
        
        switch result {
            
        case .success(let verification):
            //Check whether the transaction is verified. If it isn't,
            //this function rethrows the verification error.
            let transaction = try checkVerified(verification)
            self.currentTransaction = transaction
            //The transaction is verified. Deliver content to the user.
            currentOrder?.transactionId = "\(transaction.id)"
            currentOrder?.updateTokeyChain()
            self.delegate?.orderStatusChanged(order: currentOrder, status: .complete)
            print(transaction.debugDescription)
            //Always finish a transaction.
//            await transaction.finish()

            return transaction
        case .userCancelled, .pending:
            self.delegate?.orderStatusChanged(order: currentOrder, status: .failed(DQIAPError(reason: "user Cancelled", code: -1)))
            self.finishCurrentOrder()
            return nil
        default:
            return nil
        }
    }
    
    //Check whether the JWS passes StoreKit verification.
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            //StoreKit parses the JWS, but it fails verification.
            throw StoreError.failedVerification
        case .verified(let safe):
            //The result is verified. Return the unwrapped value.
            return safe
        }
    }
    
    /*All transactions：全部的购买交易订单
     Latest transactions：最新的购买交易订单。（分为订阅品项和除订阅品项外的所有类型二种）
     Current entitlements：当前用户有购买的权限。（全部的订阅品项、和非消耗品项）
    */
    func allTransaction() async -> [Transaction] {
        var all = [Transaction]()
        
        for await result in  Transaction.all {
            do {
                let tran = try checkVerified(result)
                all.append(tran)
                
            } catch let error {
            
                print("error:----\(error)")
            }
            
        }
        return all
        
        //Transaction.latest(for: "pid")
        
    }
    //获取推广内购商品
    func Promotion() async -> [SKProduct]?{
        let promotion = SKProductStorePromotionController()
        
        let prodicts = try? await promotion.promotionOrder()
        return prodicts
    }
    
    
}

