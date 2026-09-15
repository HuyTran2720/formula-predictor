//
//  Item.swift
//  FormulaGenie
//
//  Created by Huy Tran on 15/09/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
