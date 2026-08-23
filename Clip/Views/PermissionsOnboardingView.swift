import SwiftUI
import AppKit

struct PermissionsOnboardingView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Enable Accessibility Access")
                    .font(.title2.bold())
                Text("Clip needs Accessibility access to detect when you select text in other apps and show the action popup.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                step(number: "1", text: "Open System Settings → Privacy & Security → Accessibility")
                step(number: "2", text: "Add Clip to the list and enable it")
                step(number: "3", text: "Relaunch Clip")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(10)

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }
                .buttonStyle(.borderedProminent)

                Button("Skip for Now") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(width: 440)
    }

    private func step(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.callout)
            Spacer()
        }
    }
}
