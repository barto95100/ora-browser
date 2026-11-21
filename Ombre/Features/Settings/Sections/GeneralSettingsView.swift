import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var appearanceManager: AppearanceManager
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @EnvironmentObject var updateService: UpdateService
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var defaultBrowserManager = DefaultBrowserManager.shared

    /// Shown off where glass can't be drawn; the choice itself is kept.
    private var glassEffectsBinding: Binding<Bool> {
        Binding(
            get: {
                GlassEffects.isActive(isEnabled: settings.glassEffectsEnabled, reducesTransparency: reducesTransparency)
            },
            set: { settings.glassEffectsEnabled = $0 }
        )
    }

    var body: some View {
        SettingsSection {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ombre")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Fast, secure, and beautiful browser built for macOS")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(getAppVersion())
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .settingsCardBackground()

            if !defaultBrowserManager.isDefault {
                SettingsCard {
                    SettingsRow(title: String(localized: "Born for your Mac. Make Ombre your default browser.")) {
                        Button("Set as Default") { defaultBrowserManager.requestSetAsDefault() }
                    }
                }
            }

            SettingsCard(header: String(localized: "Appearance")) {
                AppearanceSelector(selection: $appearanceManager.appearance)
                Divider()
                SettingsRow(
                    title: String(localized: "Glass Effects (Liquid Glass)"),
                    detail: GlassEffects.detail(reducesTransparency: reducesTransparency)
                ) {
                    Toggle("", isOn: glassEffectsBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!GlassEffects.isSupported || reducesTransparency)
                }
            }

            SettingsCard(header: String(localized: "Tab Management")) {
                SettingsRow(title: String(localized: "Suspend inactive tabs after:")) {
                    Picker("", selection: $settings.tabAliveTimeout) { durationChoices }
                        .labelsHidden()
                        .fixedSize()
                }
                Divider()
                SettingsRow(title: String(localized: "Remove tabs after:")) {
                    ClosingDelayPicker(seconds: Binding(
                        get: { settings.tabRemovalTimeout },
                        set: { settings.tabRemovalTimeout = $0 ?? TabClosingDelay.defaultDelay }
                    ))
                }
                Divider()
                SettingsRow(title: String(localized: "Max recent tabs:")) {
                    Picker("", selection: $settings.maxRecentTabs) {
                        ForEach(1 ... 10, id: \.self) { num in
                            Text("\(num)").tag(num)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                SettingsRow(title: String(localized: "Links from pinned tabs to other sites")) {
                    Picker("", selection: $settings.pinnedLinkBehavior) {
                        ForEach(PinnedLinkBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                SettingsRow(title: String(localized: "Auto Picture-in-Picture on tab switch")) {
                    Toggle("", isOn: $settings.autoPiPEnabled).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsRow(title: String(localized: "Open links from other apps in Little Ombre")) {
                    Toggle("", isOn: $settings.opensLinksInLittleOmbre).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsRow(
                    title: String(localized: "To Quit"),
                    detail: String(localized: "With ⌘Q. Ombre › Quit Ombre always quits at once.")
                ) {
                    Picker("", selection: $settings.quitBehavior) {
                        ForEach(QuitBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsCard(header: String(localized: "Downloads")) {
                SettingsRow(
                    title: String(localized: "Downloads from websites"),
                    detail: String(localized: "For sites set to Default in each space's site permissions.")
                ) {
                    Picker("", selection: $settings.allowsDownloadsByDefault) {
                        Text("Ask").tag(false)
                        Text("Allow").tag(true)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsCard(header: String(localized: "Developer")) {
                SettingsRow(
                    title: String(localized: "Allow Web Inspector"),
                    detail: String(
                        localized: "Inspect pages from Safari's Develop menu (Safari › Settings › Advanced)."
                    )
                ) {
                    Toggle("", isOn: $settings.developerToolsEnabled).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsRow(
                    title: String(localized: "Allow agents to control Ombre"),
                    detail: String(
                        // swiftlint:disable:next line_length
                        localized: "Apps and scripts (the ombre command) can list, open, show, close, reload, read and capture tabs, and move through their history. Each app asks first, once per session. Never private windows, Little Ombre or passwords."
                    )
                ) {
                    Toggle("", isOn: $settings.allowsAgentControl).labelsHidden().toggleStyle(.switch)
                        .onChange(of: settings.allowsAgentControl) { _, isOn in
                            if !isOn { AgentControl.shared.stop() }
                        }
                }
                Divider()
                SettingsRow(
                    title: String(localized: "Allow agents to act in pages"),
                    detail: String(
                        // swiftlint:disable:next line_length
                        localized: "They can also click, fill in fields (never password fields) and run JavaScript in web pages. JavaScript sees everything a page holds, what you type or autofill in it included: turn this on only for agents you trust."
                    )
                ) {
                    Toggle("", isOn: $settings.allowsAgentPageActions).labelsHidden().toggleStyle(.switch)
                        .disabled(!settings.allowsAgentControl)
                        .onChange(of: settings.allowsAgentPageActions) { _, isOn in
                            // Each app asks again, told what it may now do.
                            if isOn { AgentControl.shared.stop() }
                        }
                }
            }

            if UpdateService.isAvailable {
                SettingsCard(header: String(localized: "Updates")) {
                    Toggle("Auto-check for updates", isOn: $settings.autoUpdateEnabled)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("Check for Updates") {
                                updateService.checkForUpdates()
                            }

                            if updateService.isCheckingForUpdates {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 16, height: 16)
                            }

                            if updateService.updateAvailable {
                                Text("Update available!")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }

                        if let result = updateService.lastCheckResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(updateService.updateAvailable ? .green : .secondary)
                        }

                        if let lastCheck = updateService.lastCheckDate {
                            Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear { defaultBrowserManager.refresh() }
    }

    @ViewBuilder private var durationChoices: some View {
        Text("1 hour").tag(TimeInterval(60 * 60))
        Text("6 hours").tag(TimeInterval(6 * 60 * 60))
        Text("12 hours").tag(TimeInterval(12 * 60 * 60))
        Text("1 day").tag(TimeInterval(24 * 60 * 60))
        Text("2 days").tag(TimeInterval(2 * 24 * 60 * 60))
        Text("Never").tag(TimeInterval(365 * 24 * 60 * 60))
    }

    private func getAppVersion() -> String {
        let version = Bundle.main
            .infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown" // no translation
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown" // no translation
        return "v\(version) (\(build))"
    }
}
