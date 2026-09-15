//
//  ContentView.swift
//  FormulaGenie
//
//  Created by Huy Tran on 15/09/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    
    var body: some View {
        Text("Parity check - see console")
            .onAppear {
                LapTimeModel.printInputs()
                LapTimeModel.parityCheck()
            }
    }
}
    
#Preview {
    ContentView()
}
