import Foundation
import Combine
import StoreKit
import SwiftUI

#if canImport(StoreKit) && compiler(>=5.5)
@available(iOS 15.0, *)
typealias TransactionAPI = StoreKit.Transaction
#endif
