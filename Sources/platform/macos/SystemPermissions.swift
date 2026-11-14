import AppKit
import AVFoundation
import CoreLocation

@MainActor
final class SystemPermissions: NSObject, CLLocationManagerDelegate {
    private let location = CLLocationManager()
    var onChange: (() -> Void)?
    override init() { super.init(); location.delegate = self }
    func status(_ kind: SiteSettingKind) -> String {
        switch kind {
        case .camera, .microphone:
            switch AVCaptureDevice.authorizationStatus(for: kind == .camera ? .video : .audio) {
            case .authorized: return "macOS 허용"
            case .denied: return "macOS 거부"
            case .restricted: return "macOS 제한됨"
            case .notDetermined: return "macOS 미결정"
            @unknown default: return "macOS 상태 미확인"
            }
        case .geolocation:
            guard CLLocationManager.locationServicesEnabled() else { return "macOS 위치 서비스 꺼짐" }
            switch location.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: return "macOS 허용"
            case .denied: return "macOS 거부"
            case .restricted: return "macOS 제한됨"
            case .notDetermined: return "macOS 미결정"
            @unknown default: return "macOS 상태 미확인"
            }
        case .notifications: return "macOS 설정에서 확인"
        case .cookies, .popups: return "macOS 권한 없음"
        }
    }
    func request(_ kind: SiteSettingKind) async {
        switch kind {
        case .camera, .microphone:
            let media: AVMediaType = kind == .camera ? .video : .audio
            if AVCaptureDevice.authorizationStatus(for: media) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: media)
            } else { openSettings(kind) }
        case .geolocation:
            if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
            else { openSettings(kind) }
        case .notifications: openSettings(kind)
        case .cookies, .popups: break
        }
        onChange?()
    }
    func openSettings(_ kind: SiteSettingKind) {
        let destination: String
        switch kind {
        case .camera: destination = "com.apple.preference.security?Privacy_Camera"
        case .microphone: destination = "com.apple.preference.security?Privacy_Microphone"
        case .geolocation: destination = "com.apple.preference.security?Privacy_LocationServices"
        case .notifications: destination = "com.apple.Notifications-Settings.extension"
        case .cookies, .popups: return
        }
        if let url = URL(string: "x-apple.systempreferences:" + destination) { NSWorkspace.shared.open(url) }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.onChange?() }
    }
}
