//
//  SafetyGuardianApp.swift
//  SafetyGuardian
//
//  Main app entry point for SafetyGuardian
//

import SwiftUI

@main
struct SafetyGuardianApp: App {
    init() {
        // Load saved settings on app launch
        AppConfiguration.loadSettings()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    requestCameraPermission()
                }
        }
    }

    // MARK: - Permissions

    private func requestCameraPermission() {
        // Camera permission will be requested automatically when
        // CameraManager attempts to access the camera
        // This is handled by Info.plist key: NSCameraUsageDescription
    }
}
