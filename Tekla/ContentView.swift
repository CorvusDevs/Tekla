//
//  ContentView.swift
//  Tekla
//
//  Created by Alejandro on 22/3/26.
//

import SwiftUI

/// Placeholder — the main keyboard UI is in KeyboardContentView,
/// hosted by the floating NSPanel in AppDelegate.
struct ContentView: View {
    var body: some View {
        KeyboardContentView()
    }
}

#Preview {
    ContentView()
        .frame(width: 920, height: 320)
}
