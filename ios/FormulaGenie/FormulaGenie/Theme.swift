//
//  Theme.swift
//  FormulaGenie
//
//  Dark, F1-Manager-inspired palette. The whole app forces dark color scheme
//  (see ContentView) so standard SwiftUI colors (.primary, .secondary,
//  Material) already read correctly against these - only backgrounds and the
//  accent need to be defined here.
//

import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.07, blue: 0.11)
    static let panel = Color(red: 0.09, green: 0.11, blue: 0.16)
    static let panelAlt = Color(red: 0.12, green: 0.145, blue: 0.20)
    static let accent = Color(red: 1.0, green: 0.56, blue: 0.16)
    static let leaderRow = Color(white: 0.93)
}
