//
//  DQIAPStatus.swift
//  
//
//  Created by zhaoquan.du on 2023/1/30.
//

import UIKit
import StoreKit

public enum DQIAPStatus {

    case appleStoreConnecting
    case purchasing
    case purchased
    case receiptChecking
    case deferred //ask for buy: ask permission for your parent or guardian
    
    case complete
    case failed(Error)
    
    public static func failureToString(error:Error) -> String {
    
        let nsError = error as NSError
        if nsError.domain == SKError.errorDomain{
            switch nsError.code {
            case SKError.clientInvalid.rawValue, SKError.paymentNotAllowed.rawValue:
                return "You are not allowed to make payment."
            case SKError.paymentCancelled.rawValue:
                return "Payment has been cancelled."
            case SKError.unknown.rawValue, SKError.paymentInvalid.rawValue:
                fallthrough
            default:
                print ("Something went wrong making payment.")
                return error.localizedDescription
            }
        } else if let iapError = error as? DQIAPError {
            return iapError.reason
        }
        
        return error.localizedDescription
        
        
    }

}
public struct DQIAPError :Error{
    public var reason:String
    public var code:Int
    public init(reason: String, code: Int) {
        self.reason = reason
        self.code = code
    }
}

