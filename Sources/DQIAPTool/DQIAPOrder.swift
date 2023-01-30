//
//  DQIAPOrder.swift
//  
//
//  Created by zhaoquan.du on 2023/1/30.
//

import UIKit
import StoreKit

let lastDQIAPOrderKey = "lastDQIAPOrderKey"
public struct DQIAPOrder: Codable {
    public let uuid:String
    public var token: String
    public let productId: String
    public var transactionId: String?
    public var receipt_data: Data?
    public var deferedDate: Date?
    public var createTime = Date()
    
    public init(uuid: String,token:String,productId:String) {
        self.uuid = uuid
        self.token = token
        self.productId = productId
    }
    public init(token:String,productId:String) {
        self.uuid = UUID().uuidString
        self.token = token
        self.productId = productId
    }
    func saveToKeyChain(){
        DQKeychainManager.keyChainSave(value: self, key: lastDQIAPOrderKey)
    }
    func updateTokeyChain(){
        DQKeychainManager.keyChainUpdata(value: self, for: lastDQIAPOrderKey)
    }
    static func getLastOrderForKeychain() -> DQIAPOrder?{
        if let order: DQIAPOrder = DQKeychainManager.keyChainReadValue(for: lastDQIAPOrderKey){
            return order
        }else{
            return nil
        }
    }
    func deleteKeychainOrderRecord(){
        DQKeychainManager.keyChianDelete(identifier: lastDQIAPOrderKey)
    }
}

