
//  Created by Dominik on 10/07/2016.

//    The MIT License (MIT)
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.

//    v2.0

import StoreKit

// MARK: - Request URLs

private enum RequestURL : String {
    
    case appleSandbox = "https://sandbox.itunes.apple.com/verifyReceipt"
    case appleProduction = "https://buy.itunes.apple.com/verifyReceipt"
    case myServer = ""
}

// MARK: - HTTP Method

private enum HTTPMethod: String {
    
    case post = "POST"
}

// MARK: - JSON Object Keys

private enum JSONObjectKey: String {
    
    case receiptData = "receipt-data" // The base64 encoded receipt data.
    case password // Only used for receipts that contain auto-renewable subscriptions. Your app’s shared secret (a hexadecimal string).
}

// MARK: - JSON Response Keys

private enum JSONResponseKey: String {
    
    case status // See ReceiptStatusCode
    // For iOS 6 style transaction receipts, the status code reflects the status of the specific transaction’s receipt.
    // For iOS 7 style app receipts, the status code is reflects the status of the app receipt as a whole. For example, if you send a valid app receipt that contains an expired subscription, the response is 0 because the receipt as a whole is valid.
    case receipt // A JSON representation of the receipt that was sent for verification. For information about keys found in a receipt, see Receipt Fields.
    case latest_receipt // Only returned for iOS 6 style transaction receipts for auto-renewable subscriptions. The base-64 encoded transaction receipt for the most recent renewal.
    case latest_receipt_info // Only returned for iOS 6 style transaction receipts for auto-renewable subscriptions. The JSON representation of the receipt for the most recent renewal.
}

// MARK: - Receipt Status Code

private enum ReceiptStatusCode: Int {
    
    case unknown = -2 // No decodable status
    case none = -1 // No status returned
    case valid = 0 // Valid status
    case jsonNotReadable = 21000 // The App Store could not read the JSON object you provided.
    case malformedOrMissingData = 21002 // The data in the receipt-data property was malformed or missing.
    case receiptCouldNotBeAuthenticated = 21003 // The receipt could not be authenticated.
    case sharedSecretNotMatching = 21004 // The shared secret you provided does not match the shared secret on file for your account.
    // Only returned for iOS 6 style transaction receipts for auto-renewable subscriptions.
    case receiptServerUnavailable = 21005 // The receipt server is currently not available.
    case subscriptionExpired = 21006 // This receipt is valid but the subscription has expired. When this status code is returned to your server, the receipt data is also decoded and returned as part of the response.
    // Only returned for iOS 6 style transaction receipts for auto-renewable subscriptions.
    case testReceipt = 21007 //  This receipt is from the test environment, but it was sent to the production environment for verification. Send it to the test environment instead.
    case productionEnvironment = 21008 // This receipt is from the production environment, but it was sent to the test environment for verification. Send it to the production environment instead.
}

// MARK: - Receipt Info Field

private enum ReceiptInfoField: String {
    
    case bundle_id // This corresponds to the value of CFBundleIdentifier in the Info.plist file.
    case application_version // This corresponds to the value of CFBundleVersion (in iOS) or CFBundleShortVersionString (in OS X) in the Info.plist.
    case original_application_version // The version of the app that was originally purchased. This corresponds to the value of CFBundleVersion (in iOS) or CFBundleShortVersionString (in OS X) in the Info.plist file when the purchase was originally made.
    case creation_date // The date when the app receipt was created.
    case expiration_date // The date that the app receipt expires. This key is present only for apps purchased through the Volume Purchase Program.
    case in_app // The receipt for an in-app purchase. This will be an array of dictionaries with all your individial receipts. See below
    
    enum InApp: String {
        
        case quantity // The number of items purchased. This value corresponds to the quantity property of the SKPayment object stored in the transaction’s payment property.
        case product_id // The product identifier of the item that was purchased. This value corresponds to the productIdentifier property of the SKPayment object stored in the transaction’s payment property.
        case transaction_id // The transaction identifier of the item that was purchased. This value corresponds to the transaction’s transactionIdentifier property.
        case original_transaction_id // For a transaction that restores a previous transaction, the transaction identifier of the original transaction. Otherwise, identical to the transaction identifier. This value corresponds to the original transaction’s transactionIdentifier property. All receipts in a chain of renewals for an auto-renewable subscription have the same value for this field.
        case purchase_date // The date and time that the item was purchased. This value corresponds to the transaction’s transactionDate property.
        case original_purchase_date // For a transaction that restores a previous transaction, the date of the original transaction. This value corresponds to the original transaction’s transactionDate property. In an auto-renewable subscription receipt, this indicates the beginning of the subscription period, even if the subscription has been renewed.
        case expires_date // The expiration date for the subscription, expressed as the number of milliseconds since January 1, 1970, 00:00:00 GMT. This key is only present for auto-renewable subscription receipts.
        case cancellation_date // For a transaction that was canceled by Apple customer support, the time and date of the cancellation. Treat a canceled receipt the same as if no purchase had ever been made.
        #if os(iOS) || os(tvOS)
        case app_item_id // A string that the App Store uses to uniquely identify the application that created the transaction. If your server supports multiple applications, you can use this value to differentiate between them. Apps are assigned an identifier only in the production environment, so this key is not present for receipts created in the test environment. This field is not present for Mac apps. See also Bundle Identifier.
        #endif
        case version_external_identifier // An arbitrary number that uniquely identifies a revision of your application. This key is not present for receipts created in the test environment.
        case web_order_line_item_id // The primary key for identifying subscription purchases.
    }
}

// MARK: - Receipt Validator

private let validationErrorString = "Receipt validation failed: "
private var transactionProductID = ""

/*
 Swifty Receipt Validator
 
 A protocol extension to manage in app purchase receipt validation.
 */
public protocol SwiftyReceiptValidator: class {
    func usesSubscriptions() -> Bool
    func appSharesSecret() -> String
}
public extension SwiftyReceiptValidator {
    
    /// Validate receipt
    ///
    /// - parameter productID: The product ID String for the product to validate.
    func validateReceipt(forProductID productID: String, withCompletionHandler completionHandler: @escaping (Bool) -> ()) {
        transactionProductID = productID
        
        SwiftyReceiptObtainer.shared.fetch { [unowned self] receiptURL in
            guard let validReceiptURL = receiptURL else {
                print("Receipt fetch error")
                completionHandler(false)
                return
            }
            
            self.startReceiptValidation(forURL: validReceiptURL, withCompletionHandler: completionHandler)
        }
    }
}

// MARK: - Start Receipt Validation

private extension SwiftyReceiptValidator {
    
    /// Start receipt validation
    ///
    /// - parameter url: The URL of the receipt to validate.
    func startReceiptValidation(forURL url: URL, withCompletionHandler completionHandler: @escaping (Bool) -> ()) {
        print("Starting receipt validation")
        
        // Check for valid receipt content for url
        
        // Receipt data
        
        guard let payloadData = self.payloadData(for: url) else {
            print(validationErrorString + "Payload data error")
            completionHandler(false)
            return
        }
        
        /// URL request to production server first, if it fails because in test environment try sandbox
        /// This handles validation directily with apple. This is not the recommended way by apple as it is not secure.
        /// It is still better than not doing any validation at all.
        /// If you will use your own server than just will have to adjust this last bit of code to only send to your server and than connect to
        /// apple production/sandbox for there.
        ///
        /// - parameter forURL: The url to handle the receipt request.
        /// - parameter data: The playload data for the request.
        handleReceiptRequest(forURL: RequestURL.appleProduction.rawValue, data: payloadData) { [unowned self] (isSuccess, status, json) in
            guard !isSuccess else {
                print("Receipt validation passed in production mode, unlocking product(s)")
                completionHandler(true)
                return
            }
            
            /// Check if failed production request was due to a test receipt
            guard status == ReceiptStatusCode.testReceipt.rawValue else {
                completionHandler(false)
                print(validationErrorString + "Status = \(status ?? ReceiptStatusCode.unknown.rawValue)")
                return
            }
            
            print(validationErrorString + "Production url used in sandbox mode, trying sandbox url...")
            
            /// Handle request to sandbox server
            self.handleReceiptRequest(forURL: RequestURL.appleSandbox.rawValue, data: payloadData) { (isSuccess, status, json) in
                guard isSuccess else {
                    completionHandler(false)
                    print(validationErrorString + "Status = \(status ?? ReceiptStatusCode.unknown.rawValue)")
                    return
                }
                    
                print("Receipt validation passed in sandbox mode, unlocking product(s)")
                completionHandler(true)
            }
        }
    }
    
    func payloadData(for url: URL) -> Data? {
        var receipt: Data?
        
        do {
            receipt = try Data(contentsOf: url)
        }
            
        catch let error as NSError {
            print(error.localizedDescription)
            return nil
        }
        
        // Prepare payload
        let receiptData = receipt?.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0))
        var payload = [JSONObjectKey.receiptData.rawValue: receiptData]
        
        if self.usesSubscriptions() {
            payload[JSONObjectKey.password.rawValue] = self.appSharesSecret()
        }
        
        var receiptPayloadData: Data?
        
        do {
            receiptPayloadData = try JSONSerialization.data(withJSONObject: payload, options: JSONSerialization.WritingOptions(rawValue: 0))
        }
            
        catch let error as NSError {
            print(error.localizedDescription)
            return nil
        }
        
        return receiptPayloadData
    }
}


// MARK: - Handle URL Request

private let urlRequestString = "URL request - "

private extension SwiftyReceiptValidator {
    
    /// Handle receipt request
    ///
    /// - parameter url: The url string for the receipt request.
    /// - parameter data: The Data object for the request.
    func handleReceiptRequest(forURL url: String, data: Data, withCompletionHandler completionHandler: @escaping (_ isSuccess: Bool, _ status: Int?, _ json: [String : AnyObject]?) -> ()) {
        
        // Request url
        guard let requestURL = URL(string: url) else {
            print(validationErrorString + "Request url not found")
            completionHandler(false, nil, nil)
            return
        }
        // Request
        var request = URLRequest(url: requestURL)
        request.httpMethod = HTTPMethod.post.rawValue
        request.httpBody = data
        
        let task = URLSession.shared.dataTask(with: request, completionHandler: { (data, response, error) in
            
            /// URL request error
            if let error = error {
                print(validationErrorString + urlRequestString + error.localizedDescription)
                completionHandler(false, nil, nil)
                return
            }
            
            /// URL request data error
            guard let data = data else {
                print(validationErrorString + urlRequestString + "Data error")
                completionHandler(false, nil, nil)
                return
            }
            
            /// JSON
            var json: [String: AnyObject]?
            
            do {
                json = try JSONSerialization.jsonObject(with: data, options: .mutableLeaves) as? [String : AnyObject]
            }
            catch let error as NSError {
                print(validationErrorString + urlRequestString + error.localizedDescription)
                completionHandler(false, nil, nil)
                return
            }
            
            /// Parse json
            guard let parseJSON = json else {
                print(validationErrorString + urlRequestString + "JSON parse error")
                completionHandler(false, nil, nil)
                return
            }
            
            /// Check for receipt status in json
            guard let status = parseJSON[JSONResponseKey.status.rawValue] as? Int else {
                print(validationErrorString + urlRequestString + "Receipt status not found in json response")
                completionHandler(false, nil, nil)
                return
            }
            
            /// Check receipt status is valid
            guard status == ReceiptStatusCode.valid.rawValue else {
                print(validationErrorString + urlRequestString + "Invalid receipt status in json response = \(status)")
                completionHandler(false, status, parseJSON)
                return
            }
            
            print("Valid receipt status in json reponse: \(status)")
            
            /// Handle additional security checks
            
            /// Check receipt send for verification exists in json response
            guard let receipt = parseJSON[JSONResponseKey.receipt.rawValue] else {
                print(validationErrorString + urlRequestString + "Could not find receipt send for validation in json reponse")
                completionHandler(false, nil, parseJSON)
                return
            }
            
            print(urlRequestString + "Valid receipt in json reponse = \(receipt)")
            
            /// Check receipt contains correct bundle and product id for app
            guard self.isAppBundleIDMatching(withReceipt: receipt) && self.isTransactionProductIDMatching(withReceipt: receipt as! [String : AnyObject]) else {
                completionHandler(false, nil, parseJSON)
                return
            }
            
            // Validation successfull, unlock content
            print(urlRequestString + "Receipt verification successful")
            completionHandler(true, nil, parseJSON)
        })
        
        task.resume()
    }
}

// MARK: - Receipt Validation Additional Checks

private extension SwiftyReceiptValidator {
    
    /// Check if app bundle ID is matching with receipt bundle ID
    ///
    /// - parameter receipt: The receipt object to check the bundle ID with.
    func isAppBundleIDMatching(withReceipt receipt: AnyObject) -> Bool {
        let receiptBundleID = receipt[ReceiptInfoField.bundle_id.rawValue] as? String ?? "NoReceiptBundleID"
        let appBundleID = Bundle.main.bundleIdentifier ?? "NoAppBundleID"
        
        guard receiptBundleID == appBundleID else {
            print(validationErrorString + urlRequestString + "App bundle id: \(appBundleID) not matching with receipt bundle id: \(receiptBundleID)")
            return false
        }
        
        return true
    }
    
    /// Check if transaction product ID is matching with receipt product ID
    ///
    /// - parameter receipt: The receipt object to check the product ID with.
    func isTransactionProductIDMatching(withReceipt receipt: [String: AnyObject]) -> Bool {
        guard let inApp = receipt[ReceiptInfoField.in_app.rawValue] as? [AnyObject] else {
            print(validationErrorString + urlRequestString + "Could not find receipt in app array in json response")
            return false
        }
        
        var receiptProductID = ""
        
        for receiptInApp in inApp {
            receiptProductID = receiptInApp[ReceiptInfoField.InApp.product_id.rawValue] as? String ?? "NoReceiptProductID"
            if receiptProductID == transactionProductID {
                return true
            }
        }
        
        print(validationErrorString + urlRequestString + "Transaction product ID \(transactionProductID) not matching with receipt product id = \(receiptProductID)")
        return false
    }
}

//MARK: Subscription Validation
public extension SwiftyReceiptValidator {
    func validateSubscription(forProductID productID: String, withCompletionHandler completionHandler: @escaping (Bool, Date?) -> ()) {
        
        transactionProductID = productID
        
        SwiftyReceiptObtainer.shared.fetch { [unowned self] receiptURL in
            guard let validReceiptURL = receiptURL else {
                print("Receipt fetch error")
                completionHandler(false, nil)
                return
            }
            
            self.startSubscriptionValidation(forURL: validReceiptURL, withCompletionHandler: completionHandler)
        }
    }
}

private extension SwiftyReceiptValidator {
    func startSubscriptionValidation(forURL url: URL, withCompletionHandler completionHandler: @escaping (Bool, Date?) -> ()) {
        guard let payloadData = self.payloadData(for: url) else {
            print(validationErrorString + "Payload data error")
            completionHandler(false, nil)
            return
        }
        
        handleReceiptRequest(forURL: RequestURL.appleProduction.rawValue, data: payloadData) { [unowned self] (isSuccess, status, json) in
            guard !isSuccess else {
                print("Receipt validation passed in production mode, unlocking product(s)")
                completionHandler(true, self.subscriptionExpirationDate(from: json))
                return
            }
            
            /// Check if failed production request was due to a test receipt
            guard status == ReceiptStatusCode.testReceipt.rawValue else {
                completionHandler(false, nil)
                print(validationErrorString + "Status = \(status ?? ReceiptStatusCode.unknown.rawValue)")
                return
            }
            
            print(validationErrorString + "Production url used in sandbox mode, trying sandbox url...")
            
            /// Handle request to sandbox server
            self.handleReceiptRequest(forURL: RequestURL.appleSandbox.rawValue, data: payloadData) { (isSuccess, status, json) in
                guard isSuccess else {
                    completionHandler(false, nil)
                    print(validationErrorString + "Status = \(status ?? ReceiptStatusCode.unknown.rawValue)")
                    return
                }
                
                print("Receipt validation passed in sandbox mode, unlocking product(s)")
                completionHandler(true, self.subscriptionExpirationDate(from: json))
            }
        }
    }
    
    ///Tries to get subscription end date from JSON array. If no date is found, subscription is not valid (case for cancelling subscription)
    func subscriptionExpirationDate(from aJson: [String: AnyObject]?) -> Date? {
        guard let json = aJson else {return nil}
        print(json)
        
        var receiptInfo: [AnyObject]?
        receiptInfo = json[JSONResponseKey.latest_receipt_info.rawValue] as! [AnyObject]?
        if receiptInfo == nil {
            receiptInfo = json[JSONResponseKey.receipt.rawValue] as! [AnyObject]?
        }
        
        guard let info = receiptInfo else {return nil}
        
        guard let latestRenewalInfo = info.last as? [String: AnyObject] else {
            return nil
        }
        
        print(latestRenewalInfo)
        
        let dateString = latestRenewalInfo[ReceiptInfoField.InApp.expires_date.rawValue] as! String
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss VV"
        let expirationDate = formatter.date(from: dateString)
        
        return expirationDate
    }
}
