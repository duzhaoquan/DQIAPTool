//
//  DQIAPDelegate.swift
//  
//
//  Created by zhaoquan.du on 2023/1/30.
//

import Foundation

public protocol DQIAPDelegate: NSObjectProtocol {
    //This method is called when the payment status changes
    func orderStatusChanged(order: DQIAPOrder?,status:DQIAPStatus)
    //This method is called when the token is renewed when the token expires
    func refreshToken(token: String,completion:@escaping (String?)->Void);
    //Call this method to get the token after the payment is successful but there is no order
    func fetchOrderToken(productId:String,completion:@escaping (String?)->Void)
    //Provide a network method
    func httpPost(url:String,params: [String : Any]?,headers: [String : String]?,completion: @escaping (Result<Data, Error>)->Void)
}
