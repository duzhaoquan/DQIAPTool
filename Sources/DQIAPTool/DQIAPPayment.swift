//
//  DQIAPPayment.swift
//  
//
//  Created by zhaoquan.du on 2023/1/30.
//

import Foundation
import UIKit
import StoreKit


public class DQIAPPayment: NSObject  {
    
    
    public var userStoreKitV2 = false
    public static let shared: DQIAPPayment = DQIAPPayment()
//    private var proId:String = ""
    
    public var checkReceiptFromOwnServer = true
    // IAP serverapi
    //https://developer.apple.com/documentation/appstoreserverapi
    //21008 is production  21007dev sandbox
    var receiptState = 21007
    private let url_receipt_sandbox = "https://sandbox.itunes.apple.com/verifyReceipt"
    //生产环境验证地址
    private let url_receipt_itunes = "https://buy.itunes.apple.com/verifyReceipt"
    
    public enum URLType {
        case dev
        case dev_beta
        case pro_beta
        case pro
    }
    public var urlType: URLType = .dev
    public var urlVersion = "v1"
    
    public var url_dev = ""
    public var url_dev_beta = ""
    public var url_pro_beta = ""
    public var url_pro = ""
    
    let createPaymentUrl = "/payment/onetime/initiate"//开始订单接口
    let checkReceiptUrl = "/payment/status-and-notify"//验证支付票据接口
    
    private lazy var baseUrl:String = {
        switch self.urlType {
        case .dev:
            return url_dev + urlVersion
        case .dev_beta:
            return url_dev_beta + urlVersion
        case .pro_beta:
            return url_pro_beta + urlVersion
        case .pro:
            return url_pro + urlVersion
        }
    }()
    
    
    private override init() {
        super.init()
    }
    public weak var delegate: DQIAPDelegate?
    /// appDelegate invoke
    public func install(delegate:DQIAPDelegate){
        self.delegate = delegate
        currentOrder = DQIAPOrder.getLastOrderForKeychain()
        if userStoreKitV2, #available(iOS 15.0, *) {
            DQIAPStoreV2.shared.install(delegate:delegate)
        }else{
            SKPaymentQueue.default().add(self)
            //ios16中，支付成功但没有finish的transaction设置完代理后不会自动回调，需要手动重新再次加入一下
            let payments = SKPaymentQueue.default().transactions
            if !payments.isEmpty{
                payments.forEach({SKPaymentQueue.default().add($0.payment)})
            
            }
        }
        
        if let keychainOrderID = currentOrder?.uuid{
            let time =  DispatchTime.now() + Double(Int64(60 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
            DispatchQueue.global().asyncAfter(deadline: time){
                if let order = self.currentOrder, order.uuid == keychainOrderID{
                    if order.transactionId == nil && order.deferedDate == nil{//创建完订单，没支付，处理失败订单
                        //MARK:- 调失败接口上传信息
                        self.updatePurchaseStatus(status: "failed")
                        self.finishCurrentOrder()
                        if self.userStoreKitV2, #available(iOS 15.0, *) {
                            DQIAPStoreV2.shared.finishCurrentOrder()
                        }
                        
                    }
                }
            }
        }
        
    }
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    public func doTestPay(pid:String) {
        if SKPaymentQueue.canMakePayments() == false {
            return
        }
        let set = Set<String>.init([pid])
        
        let request = SKProductsRequest.init(productIdentifiers: set)
        request.delegate = self
        request.start()
    }
    
    private var currentOrder:DQIAPOrder?
    private var currentTransaction:SKPaymentTransaction?
    public func getCurrentOrder()->DQIAPOrder?{
        if userStoreKitV2,#available(iOS 15.0, *) {
            return DQIAPStoreV2.shared.getCurrentOrder()
        }else{
            return currentOrder
        }
    }
    public func canStartNewIAP() -> Bool{
        if userStoreKitV2, #available(iOS 15.0, *) {
            return DQIAPStoreV2.shared.canStartNewIAP()
        }else{
            if let order = currentOrder{
                
                //如果下发gems失败，会导致未处理完订单
                if let transactionId = currentOrder?.transactionId, let transaction = currentTransaction,transactionId == transaction.transactionIdentifier  {
                    completePay(transaction: transaction)
                    return false
                }else if order.transactionId == nil{
                    if let time = order.deferedDate {
                        if Date().timeIntervalSince1970 - time.timeIntervalSince1970 > 25 * 3600 {
                            self.updatePurchaseStatus(status: "failed")
                            finishCurrentOrder()
                        }
                    }else{
                        self.updatePurchaseStatus(status: "failed")
                        finishCurrentOrder()
                    }
                    
                }
            }
            
            return currentOrder == nil
        }
        
    }
    
    public func finishCurrentOrder(){
        currentOrder?.deleteKeychainOrderRecord()
        currentOrder = nil
        guard let tran = currentTransaction else {
            return
        }
        SKPaymentQueue.default().finishTransaction(tran)
        currentTransaction = nil
    }
    
    private var productFetchCallbacks = [SKProductsRequest: ([SKProduct]) -> Void]()
    public func fetchProductsInfo(_ productIDs: [String],completion:@escaping ([SKProduct]) -> Void) {
        let set = Set<String>.init(productIDs)
        let request = SKProductsRequest.init(productIdentifiers: set)
        productFetchCallbacks[request] = completion
        request.delegate = self
        request.start()
    }
    
    public func startIAPPayment(order:DQIAPOrder){
        guard SKPaymentQueue.canMakePayments() else {
            self.delegate?.orderStatusChanged(order: order, status: .failed(DQIAPError(reason: "SKPaymentQueue can not Make Payments", code: -1)))
            return
        }
        guard currentOrder == nil else{//有未处理完的支付订单
            self.delegate?.orderStatusChanged(order: order, status: .failed(DQIAPError(reason: "The last transaction is in progress", code: -1)))
            //如果下发gems失败，会导致未处理完订单
            if let transactionId = currentOrder?.transactionId, let transaction = currentTransaction,transactionId == transaction.transactionIdentifier  {
                completePay(transaction: transaction)
                return
            }
            if currentOrder?.transactionId == nil{
                if let deferTime = currentOrder?.deferedDate {
                    if Date().timeIntervalSince1970 - deferTime.timeIntervalSince1970 > 25 * 3600 {
                        self.updatePurchaseStatus(status: "failed")
                        finishCurrentOrder()
                    }
                }else{
                    self.updatePurchaseStatus(status: "failed")
                    finishCurrentOrder()
                }
                
            }
            return
        }
        
        if userStoreKitV2,#available(iOS 15.0, *) {
            DQIAPStoreV2.shared.startIAPPayment(ids: [order.productId], order:order)
            return
        }
        
        currentOrder = order
        currentOrder?.saveToKeyChain()
        
        if checkReceiptFromOwnServer{
            createPaymentServiceTransaction(order: order) {[weak self] code,error in
                guard let `self` = self else{
                    return
                }
                if code == 200{
                    let payment = SKMutablePayment()
                    payment.quantity = 1
//                    payment.applicationUsername = currentOrder?.uuid
                    payment.productIdentifier = order.productId
                    SKPaymentQueue.default().add(payment)
                }else if code == 401{
                    self.delegate?.refreshToken(token: order.token, completion: {[weak self] token in
                        guard let token = token,token.count > 0 else{
                            self?.delegate?.orderStatusChanged(order: self?.currentOrder, status: .failed(DQIAPError(reason: "create payment service transaction failed", code: code)))
                            return
                        }
                        self?.currentOrder?.token = token
                        guard let order = self?.currentOrder else{
                            return
                        }
                        
                        self?.createPaymentServiceTransaction(order: order, completion: {[weak self] code,errorStr in
                            guard let `self` = self else{
                                return
                            }
                            if code == 200{
                                let payment = SKMutablePayment()
                                payment.quantity = 1
            //                    payment.applicationUsername = currentOrder?.uuid
                                payment.productIdentifier = order.productId
                                SKPaymentQueue.default().add(payment)
                            }else{
                                self.delegate?.orderStatusChanged(order: self.currentOrder, status: .failed(DQIAPError(reason: errorStr ?? "create payment service transaction failed", code: code)))
                            }
                            
                        })
                    })
                } else{
                    self.delegate?.orderStatusChanged(order: self.currentOrder, status: .failed(DQIAPError(reason: "create payment service transaction failed", code: code)))
                    
                }
            }
        } else {
            let payment = SKMutablePayment()
            payment.quantity = 1
//            payment.applicationUsername = currentOrder?.uuid
            payment.productIdentifier = order.productId
//            payment.simulatesAskToBuyInSandbox = true // test deferred
            SKPaymentQueue.default().add(payment)
            
        }

    }
    
    private func createPaymentServiceTransaction(order:DQIAPOrder,completion:@escaping (Int,String?) -> Void){
        
        guard let deleagte = self.delegate else{
            self.delegate?.orderStatusChanged(order: order, status: .failed(DQIAPError(reason: "deleagte nil", code: -1)))
            return
        }
        let url =  baseUrl  + createPaymentUrl
     
        
        var params = [String:String]()
        params["token"] = order.token
        params["paymentInstrumentId"] = "externalpg"
        params["pgId"] = "applepay"
        
        deleagte.httpPost(url: url, params: params, headers: nil) { res in
            switch res{
            case .success(_):
                completion(200, nil)
            case .failure(let error):
                
                completion((error as NSError).code, error.localizedDescription)
                
                
            }
        }
        
        
    }
    
    //MARK:购买成功验证凭证
    fileprivate func completePay(transaction:SKPaymentTransaction?,refreshedToken:Bool = false) {
        //获取交易凭证
        guard let recepitUrl = Bundle.main.appStoreReceiptURL else{
            self.delegate?.orderStatusChanged(order: currentOrder, status: .failed(DQIAPError(reason: "Receipt data is null", code: -1)))
            print("交易凭证为空")
            return
        }
        let data:Data?
        do {
            data = try Data(contentsOf: recepitUrl)
        } catch let error {
            self.delegate?.orderStatusChanged(order: currentOrder, status:.failed(error))
            return
        }
        guard let data = data else{
            self.delegate?.orderStatusChanged(order: currentOrder, status: .failed(DQIAPError(reason: "Receipt data is null", code: -1)))
            return
        }
        guard let productId = currentOrder?.productId,productId == transaction?.payment.productIdentifier else{
            //订单productId不匹配，重新创建订单
            if let productId = transaction?.payment.productIdentifier{
                delegate?.fetchOrderToken(productId: productId, completion: { [weak self] token in
                    guard let self = self,let token = token,token.count > 0 else{
                        self?.delegate?.orderStatusChanged(order: self?.currentOrder, status: .failed(DQIAPError(reason: "fetch order token failed", code: -1)))
                        return
                    }
                    
                    self.currentOrder = DQIAPOrder(uuid: UUID().uuidString, token: token, productId: productId)
                    self.currentOrder?.receipt_data = data
                    self.currentOrder?.transactionId = transaction?.transactionIdentifier
                    self.currentOrder?.updateTokeyChain()
                    
                   //客户端请求服务端验证
                    if self.checkReceiptFromOwnServer {
                        self.createPaymentServiceTransaction(order: self.currentOrder!) { code, str in
                            
                            if code == 401  {
                                self.delegate?.refreshToken(token: token, completion: {[weak self] token in
                                    guard let token = token else{
                                        self?.delegate?.orderStatusChanged(order: self?.currentOrder, status: .failed(DQIAPError(reason: "receipt check failed", code: code)))
                                        return
                                    }
                                    self?.currentOrder?.token = token
                                    
                                    self?.completePay(transaction: transaction,refreshedToken: true)
                                })
                            }else{
                                self.verifyForPaymentService(completion: {[weak self] code,errorStr in
                                    if code == 200 {
                                        self?.delegate?.orderStatusChanged(order: self?.currentOrder, status: .complete)
                                    }else if code == 401,!refreshedToken{
                                        guard let order = self?.currentOrder else{
                                            return
                                        }
                                        self?.delegate?.refreshToken(token: order.token, completion: {[weak self] token in
                                            guard let token = token else{
                                                self?.delegate?.orderStatusChanged(order: self?.currentOrder, status: .failed(DQIAPError(reason: "receipt check failed", code: code)))
                                                return
                                            }
                                            self?.currentOrder?.token = token
                                            
                                            self?.completePay(transaction: transaction,refreshedToken: true)
                                        })
                                    }else{
                                        
                                        self?.delegate?.orderStatusChanged(order: self?.currentOrder, status: .failed(DQIAPError(reason: errorStr ?? "receipt check failed", code: code)))
                                        
                                    }
                                })
                            }
                            
                        }
                        
                    }else{
                        self.verifyForApple(data: data,transaction: transaction)
                    }
                    
                })
            }
            
            return
         }
        
         currentOrder?.receipt_data = data
         currentOrder?.transactionId = transaction?.transactionIdentifier
         currentOrder?.updateTokeyChain()
         if self.checkReceiptFromOwnServer {
             verifyForPaymentService {[weak self] code,errorStr in
                 if code == 200 {
                     self?.delegate?.orderStatusChanged(order: self?.currentOrder, status: .complete)
                 }else if code == 401,!refreshedToken{
                     guard let order = self?.currentOrder else{
                         return
                     }
                     self?.delegate?.refreshToken(token: order.token, completion: {[weak self] token in
                         guard let token = token else{
                             self?.delegate?.orderStatusChanged(order: self?.currentOrder, status: .failed(DQIAPError(reason: "receipt check failed", code: code)))
                             return
                         }
                         self?.currentOrder?.token = token
                         
                         self?.completePay(transaction: transaction,refreshedToken: true)
                     })
                 }else{
                     self?.delegate?.orderStatusChanged(order: self?.currentOrder, status: .failed(DQIAPError(reason: errorStr ?? "receipt check failed", code: code)))
                 }
             }
         }else{
             verifyForApple(data: data,transaction: transaction)
         }
         
        
    }
    
    
    private func verifyForApple(data:Data,transaction:SKPaymentTransaction?)  {
        self.delegate?.orderStatusChanged(order: currentOrder, status: .receiptChecking)
        let base64Str = data.base64EncodedString(options: .endLineWithLineFeed)
        let params = NSMutableDictionary()
        params["receipt-data"] = base64Str
        let body = try? JSONSerialization.data(withJSONObject: params, options: .prettyPrinted)
        var request = URLRequest.init(url: URL.init(string: receiptState == 21008 ? url_receipt_itunes : url_receipt_sandbox)!, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = body
        let session = URLSession.shared
        let task = session.dataTask(with: request) { [weak self](data, response, error) in
            guard let data = data, let dict = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? NSDictionary else{
                self?.delegate?.orderStatusChanged(order: self?.currentOrder, status: .failed(DQIAPError(reason: "receipt check failed", code: -1)))
                return
            }
            print("receipt_info:")
            print(dict)

            let status = dict["status"] as? Int
            switch(status){
            case 0:
                self?.delegate?.orderStatusChanged(order: self?.currentOrder, status: .complete)
                break
            case 21007:
                self?.receiptState = 21007
                self?.verifyForApple(data: data, transaction: transaction)
                break
            default:
                self?.delegate?.orderStatusChanged(order: self?.currentOrder, status: .failed(DQIAPError(reason: "receipt check failed", code: -1)))
                break
            }
        }
        task.resume()
    }
    
    private func verifyForPaymentService(completion:@escaping (Int,String?) -> Void){
        guard let order = currentOrder,
              let recieptData = currentOrder?.receipt_data,
              let transaction = currentTransaction
        else{
            completion(-1,"receipt_data nil")
            return
        }
        
        guard let deleagte = self.delegate else{
            completion(-1,"deleagte nil")
            return
        }
        let url = baseUrl + checkReceiptUrl
        var params = [String:Any]()
        params["token"] = order.token
        params["paymentReceipt"] = recieptData.base64EncodedString(options: .endLineWithLineFeed)
        params["pgTransactionId"] = transaction.transactionIdentifier
        params["applepayClientStatus"] = "purchased"
        
        deleagte.httpPost(url: url, params: params, headers: nil) { res in
            switch res{
            case .success(_):
                if let tid = params["pgTransactionId"] as? String {
                    print("verifyForPaymentService success,pgTransactionId:\(tid)")
                }
                completion(200, nil)
                
            case .failure(let error):
                if let tid = params["pgTransactionId"] as? String {
                    print("verifyForPaymentService failure,pgTransactionId:\(tid)")
                }
                completion((error as NSError).code, error.localizedDescription)
                
                
            }
        }
        
    }
    
    private func updatePurchaseStatus(status:String,completion: ((Int,String?) -> Void)? = nil){
        postPurchaseStatus(status: status,completion: completion)
    }
    private func postPurchaseStatus(status:String,second:Bool = false, completion: ((Int,String?) -> Void)? = nil){
        guard let order = currentOrder else{
            completion?(-1,"order nil")
            return
        }
        guard let deleagte = self.delegate else{
            completion?(-1,"deleagte nil")
            return
        }
        
        let url = baseUrl + checkReceiptUrl
        var params = [String:Any]()
        params["token"] = order.token
        params["applepayClientStatus"] = status
        
        deleagte.httpPost(url: url, params: params, headers: nil) {[weak self] res in
            guard let `self` = self else {
                return
            }
            switch res{
            case .success(_):
                completion?(200, nil)
                
            case .failure(let error):
                if !second && (error as NSError).code == 401{
                    self.postPurchaseStatus(status: status,second: true,completion: completion)
                }else{
                    completion?((error as NSError).code, error.localizedDescription)
                }
                
                
                
            }
        }
    }
    
}
// MARK: SKProductsRequestDelegate
extension DQIAPPayment : SKProductsRequestDelegate{
    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        
        guard let callback = productFetchCallbacks[request] else { return }
        productFetchCallbacks[request] = nil

        DispatchQueue.main.async {
            callback(response.products)
        }
        
    }
    public func request(_ request: SKRequest, didFailWithError error: Error) {
        print(error.localizedDescription)
        if let productsFetchRequest = request as? SKProductsRequest {
            guard let callback = productFetchCallbacks[productsFetchRequest] else { return }
            productFetchCallbacks[productsFetchRequest] = nil
            DispatchQueue.main.async {
                callback([])
            }
        }
    }
//    public func requestDidFinish(_ request: SKRequest) {
//        print(request)
//    }
}
// MARK: SKPaymentTransactionObserver
//处理未完成的交易
extension DQIAPPayment : SKPaymentTransactionObserver{
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for tran in transactions {
            
            switch tran.transactionState {
               
            case .purchased://购买完成
                //成功的未移出的transaction进入app会会掉，失败的不会回掉
                self.delegate?.orderStatusChanged(order: currentOrder, status:.purchased)
                currentTransaction = tran
                completePay(transaction: tran)
                print("-------IAP pay purchased--------------")
                break
            case.purchasing://商品添加进列表
//                 tran.transactionIdentifier此时未nil
                self.delegate?.orderStatusChanged(order: currentOrder, status: .purchasing)
                currentTransaction = tran
                self.updatePurchaseStatus(status: "purchasing")
                print("-------IAP pay purchasing--------------")
                break
            case.restored://已经购买过该商品
                self.delegate?.orderStatusChanged(order: currentOrder, status: .failed(DQIAPError(reason: "product restored", code: -1)))
                self.updatePurchaseStatus(status: "restored")
                currentTransaction = tran
                finishCurrentOrder()
                print("-------IAP pay restored--------------")
                break
            case.failed://购买失败
                self.delegate?.orderStatusChanged(order: currentOrder, status: .failed(tran.error ?? DQIAPError(reason: "purchase failed error", code: -1)))
                handleFailure(tran)
                self.updatePurchaseStatus(status: "failed")
                //低版本iOS13以下添加观察者之后有可能直接走到此处失败的回调中
                currentTransaction = tran
                finishCurrentOrder()
                print("-------IAP pay failed--------------")
                break
            case .deferred:
                //https://stackoverflow.com/questions/42152560/how-to-handle-skpaymenttransactionstatedeferred
                //ask permission for your parent or guardian
                //ask for buy,We get transaction deferred state, if user is part of Apple family sharing & family admin enabled ASK TO BUY.
                currentTransaction = tran
                currentOrder?.deferedDate = Date()
                currentOrder?.updateTokeyChain()
                self.updatePurchaseStatus(status: "deferred")
                self.delegate?.orderStatusChanged(order: currentOrder, status: .deferred)
                print("-------IAP pay deferred--------------")
                break
            @unknown default:
                ()
            }
        }
    }
    private func handleFailure(_ transaction: SKPaymentTransaction) {
        guard let error = transaction.error else { return }
        let nsError = error as NSError
        guard nsError.domain == SKError.errorDomain else { return }

        switch nsError.code {
        case SKError.clientInvalid.rawValue, SKError.paymentNotAllowed.rawValue:
            print ("You are not allowed to make IAP payment.")
        case SKError.paymentCancelled.rawValue:
            print ( "IAP Payment has been cancelled.")
        case SKError.unknown.rawValue, SKError.paymentInvalid.rawValue:
            fallthrough
        default:
            print ("Something went wrong making IAP payment.")
        }
    }

}
