//
//  TeklaApp.swift
//  Tekla
//
//  Created by Alejandro on 22/3/26.
//

import SwiftUI

@main
struct TeklaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The keyboard lives in a floating NSPanel managed by AppDelegate.
        // Settings window can be added here later.
        Settings {
            EmptyView()
        }
    }
}
