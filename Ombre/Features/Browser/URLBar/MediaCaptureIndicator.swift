import SwiftUI

/// Camera and microphone buttons shown in the address bar while the page uses
/// them, like Safari: red while capturing, slashed while paused. Clicking one
/// pauses or resumes that device without reloading the page.
struct MediaCaptureIndicator: View {
    let state: BrowserMediaCaptureState
    let foregroundColor: Color
    let onToggle: (BrowserCaptureDevice) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(BrowserCaptureDevice.allCases, id: \.self) { device in
                if state[device] != .none {
                    button(for: device, isPaused: state[device] == .muted)
                }
            }
        }
    }

    private func button(for device: BrowserCaptureDevice, isPaused: Bool) -> some View {
        Button {
            onToggle(device)
        } label: {
            Image(systemName: device.symbolName(isPaused: isPaused))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isPaused ? foregroundColor.opacity(0.6) : Color.red)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(device.toggleTitle(isPaused: isPaused))
        .accessibilityLabel(Text(device.toggleTitle(isPaused: isPaused)))
    }
}

extension BrowserCaptureDevice {
    func symbolName(isPaused: Bool) -> String {
        switch self {
        case .camera: isPaused ? "video.slash.fill" : "video.fill"
        case .microphone: isPaused ? "mic.slash.fill" : "mic.fill"
        }
    }

    func toggleTitle(isPaused: Bool) -> String {
        switch self {
        case .camera: isPaused ? "Resume Camera" : "Pause Camera"
        case .microphone: isPaused ? "Resume Microphone" : "Pause Microphone"
        }
    }
}
