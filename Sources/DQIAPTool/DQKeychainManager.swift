//
//  DQKeychainManager.swift
//  
//
//  Created by zhaoquan.du on 2023/1/30.
//

import UIKit

public class DQKeychainManager: NSObject {
    // create Quary Dictionary
    class func createQuaryMutableDictionary(identifier:String)->NSMutableDictionary {
        var service = "DQIAPPayment"
        if let bundleID = Bundle.main.bundleIdentifier{
            service = bundleID
        }

        let keychainQuaryMutableDictionary = NSMutableDictionary.init(capacity: 0)
        // set save type
        keychainQuaryMutableDictionary.setValue(kSecClassGenericPassword, forKey: kSecClass as String)
        // set service key and account key
        keychainQuaryMutableDictionary.setValue(service, forKey: kSecAttrService as String)
        keychainQuaryMutableDictionary.setValue(identifier, forKey: kSecAttrAccount as String)
        // set parameter
        keychainQuaryMutableDictionary.setValue(kSecAttrAccessibleAfterFirstUnlock, forKey: kSecAttrAccessible as String)
        // return dic
        return keychainQuaryMutableDictionary
    }

    // TODO: 存储数据
    @discardableResult public class func keyChainSave<T: Encodable>(value:T ,key:String)->Bool {
        let encoder = JSONEncoder()
        var valueData: Data?
        do {
            valueData = try encoder.encode(value)
        } catch  {
            return false
        }
        guard  let valueData = valueData else {
            return false
        }
        // create Quary Dictionary
        let keyChainSaveMutableDictionary = self.createQuaryMutableDictionary(identifier: key)
        // delete old data
        SecItemDelete(keyChainSaveMutableDictionary)
        // set new data
        keyChainSaveMutableDictionary.setValue(valueData, forKey: kSecValueData as String)
        // save
        let saveState = SecItemAdd(keyChainSaveMutableDictionary, nil)
        if saveState == noErr  {
            return true
        }
        return false
    }

    // TODO: 更新数据
    @discardableResult public class func keyChainUpdata<T: Encodable>(value:T ,for key:String)->Bool {
        let encoder = JSONEncoder()
        var valueData: Data?
        do {
            valueData = try encoder.encode(value)
        } catch  {
            return false
        }
        guard  let valueData = valueData else {
            return false
        }
        // create Quary Dictionary
        let keyChainUpdataMutableDictionary = self.createQuaryMutableDictionary(identifier: key)
        // create dic
        let updataMutableDictionary = NSMutableDictionary.init(capacity: 0)
        // set data
        updataMutableDictionary.setValue(valueData, forKey: kSecValueData as String)
        // Update data
        let updataStatus = SecItemUpdate(keyChainUpdataMutableDictionary, updataMutableDictionary)
        if updataStatus == noErr {
            return true
        }
        return false
    }

    public class func keyChainReadValue<T: Decodable>(for key:String)-> T? {

        // create Quary Dictionary
        let keyChainReadmutableDictionary = self.createQuaryMutableDictionary(identifier: key)
        // set parameter
        keyChainReadmutableDictionary.setValue(kCFBooleanTrue, forKey: kSecReturnData as String)
        keyChainReadmutableDictionary.setValue(kSecMatchLimitOne, forKey: kSecMatchLimit as String)
        // result obj
        var queryResult: AnyObject?
        // quary
        let readStatus = withUnsafeMutablePointer(to: &queryResult) { SecItemCopyMatching(keyChainReadmutableDictionary, UnsafeMutablePointer($0))}
        if readStatus == errSecSuccess {
            if let data = queryResult as? Data {
                return try? JSONDecoder().decode(T.self, from: data)
            }
        }
        return nil
    }

    // delete data
    public class func keyChianDelete(identifier:String)->Void{
        // create delete Dictionary
        let keyChainDeleteMutableDictionary = self.createQuaryMutableDictionary(identifier: identifier)
        // delete data
        SecItemDelete(keyChainDeleteMutableDictionary)
    }

}

