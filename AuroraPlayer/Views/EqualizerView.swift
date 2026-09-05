import SwiftUI

struct EqualizerView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        mainSwitchSection
                        presetsSection
                        bandsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(UIColor.systemBackground).opacity(0.92), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Ecualizador")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .accessibilityLabel("Ecualizador")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    // MARK: - Main Switch Card
    private var mainSwitchSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Ecualizador de 10 Bandas")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)

                Text(audioEngine.isEQEnabled ? "Activo (\(audioEngine.eqPreset.displayName))" : "Desactivado")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { audioEngine.isEQEnabled },
                set: { _ in audioEngine.toggleEQ() }
            ))
            .labelsHidden()
            .tint(.purple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .nativeGlass(cornerRadius: 20)
        .contentShape(Rectangle())
    }

    // MARK: - Presets
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(EQPreset.allCases, id: \.self) { preset in
                        Button {
                            Haptics.light()
                            audioEngine.setEQPreset(preset)
                        } label: {
                            Text(preset.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(audioEngine.eqPreset == preset && audioEngine.isEQEnabled ? .white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(audioEngine.eqPreset == preset && audioEngine.isEQEnabled ? Color.purple : Color.secondary.opacity(0.12))
                                }
                        }
                        .buttonStyle(PressableButtonStyle(scale: 0.92))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Bands Sliders
    private var bandsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Frecuencias")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 16) {
                ForEach(0..<10, id: \.self) { bandIndex in
                    bandSliderRow(bandIndex: bandIndex)
                }
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }

    @ViewBuilder
    private func bandSliderRow(bandIndex: Int) -> some View {
        let frequencyName = bandFrequencyName(bandIndex)
        let currentGain = audioEngine.getEQGain(for: bandIndex)

        VStack(spacing: 6) {
            HStack {
                Text(frequencyName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .monospacedDigit()

                Spacer()

                Text(String(format: "%+.1f dB", currentGain))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(audioEngine.isEQEnabled ? .purple : .secondary)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(currentGain) },
                    set: { newVal in
                        audioEngine.setEQGain(for: bandIndex, gain: Float(newVal))
                    }
                ),
                in: -12...12,
                step: 0.5
            )
            .tint(.purple)
            .disabled(!audioEngine.isEQEnabled)
            .padding(.vertical, 6)
        }
    }

    private func bandFrequencyName(_ index: Int) -> String {
        let names = ["32 Hz", "64 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz"]
        return index < names.count ? names[index] : "\(index)"
    }
}

#Preview {
    EqualizerView(audioEngine: AudioEngine())
}