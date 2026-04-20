//
//  Item.swift
//  MacroScan
//
//  Created by Ansh Shah on 4/20/26.
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
