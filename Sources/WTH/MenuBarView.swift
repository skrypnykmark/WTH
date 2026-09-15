import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            toggles
            Divider()
            status
            if let warning = model.accessWarning {
                warningBanner(warning)
            }
            Divider()
            actions
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .background(
            MenuBarWindowAccessor { window in
                model.attachMenuBarWindow(window)
            }
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 24))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("WTH")
                    .font(.headline)
                Text("What the HEIC? · HEIC → JPEG")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var toggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Automatic Conversion",
                isOn: Binding(
                    get: { model.isAutomaticConversionEnabled },
                    set: { model.setAutomaticConversionEnabled($0) }
                )
            )
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLoginEnabled($0) }
                )
            )
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.isAutomaticConversionEnabled ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(model.statusText)
                    .font(.callout)
            }
            if let date = model.lastConversionDate {
                Text("Last conversion: \(date, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No conversions yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func warningBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Check Again") { model.retryAccess() }
                Button("Privacy Settings") { model.openPrivacySettings() }
            }
            .controlSize(.small)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Choose HEIC Files…") {
                model.convertSelectedFiles()
            }
            Button("Convert Existing HEIC Files Now") {
                model.convertExistingNow()
            }
            Button("Open Downloads Folder") {
                model.openDownloads()
            }
        }
        .controlSize(.small)
    }

    private var footer: some View {
        HStack {
            Text("Version \(Self.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { model.quit() }
                .controlSize(.small)
        }
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

/// Reports the hosting window of the menu bar extra so it can be dismissed.
private struct MenuBarWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowReportingView, context: Context) {
        nsView.onWindow = onWindow
    }
}

private final class WindowReportingView: NSView {
    var onWindow: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindow?(window)
    }
}
