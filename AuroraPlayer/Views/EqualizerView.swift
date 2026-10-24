import SwiftUI

struct EqualizerView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    // ✅ AURORA DESIGN: header de sheet del sistema en su propia fila
                    // (44pt, exactamente lo que medía la barra) con el título en el
                    // acento de la app y el "Listo" en el slot trailing: el contenido
                    // de abajo no cambia de tamaño ni de spacing.
                    M3ENavigationBar(
                        title: Localization.localized("equalizer.title"),
                        leading: {
                            Button { dismiss() } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(Localization.localized("design.close"))
                        },
                        trailing: { headerDoneButton }
                    )

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
            }
    }

    /// ✅ AURORA DESIGN: el "Listo" que antes vivía en el toolbar, ahora en el slot
    /// trailing del header. Es el MISMO botón y mide 44pt, así que el título sigue
    /// perfectamente centrado.
    private var headerDoneButton: some View {
        Button(Localization.localized("actions.done")) { dismiss() }
            .foregroundStyle(AppTheme.accent)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    // MARK: - Main Switch Card
    private var mainSwitchSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentGradient(opacity: 0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.accentGradient)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(Localization.localized("equalizer.bandTitle"))
                    .font(M3ETypography.titleMediumEmphasized)
                    .foregroundStyle(.primary)

                Text(audioEngine.isEQEnabled ? "\(Localization.localized("equalizer.active")) (\(audioEngine.eqPreset.displayName))" : Localization.localized("equalizer.disabled"))
                    .font(M3ETypography.bodyMedium)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { audioEngine.isEQEnabled },
                set: { _ in audioEngine.toggleEQ() }
            ))
            .labelsHidden()
            .tint(AppTheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .nativeGlass(cornerRadius: 20)
        .contentShape(Rectangle())
    }

    // MARK: - Presets
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Localization.localized("equalizer.presets"))
                .font(M3ETypography.titleMediumEmphasized)
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
                                .font(M3ETypography.labelLargeEmphasized)
                                .foregroundStyle(audioEngine.eqPreset == preset && audioEngine.isEQEnabled ? .white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(AnyShapeStyle(audioEngine.eqPreset == preset && audioEngine.isEQEnabled ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(Color.secondary.opacity(0.12))))
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
            Text(Localization.localized("equalizer.frequencies"))
                .font(M3ETypography.titleMediumEmphasized)
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 16) {
                ForEach(0..<10, id: \.self) { bandIndex in
                    bandSliderRow(bandIndex: bandIndex)
                }
            }
            .padding(18)
            // ✅ AURORA DESIGN: panel de bandas → card del sistema. Radio .lg (22,
            // +2pt desde el 20 original: el token más cercano) y sin sombra (no
            // tenía). Vidrio reactivo a "Reducir transparencia".
            // ✅ M3E: contenedor sólido para la lista de bandas (cero material
            // sobre 10 sliders que se redibujan al arrastrar).
            .auroraCard(radius: AuroraRadius.lg, style: .flat, withBorder: true, withShadow: false)
        }
    }

    @ViewBuilder
    private func bandSliderRow(bandIndex: Int) -> some View {
        let frequencyName = bandFrequencyName(bandIndex)
        let currentGain = audioEngine.getEQGain(for: bandIndex)

        VStack(spacing: 6) {
            HStack {
                Text(frequencyName)
                    .font(M3ETypography.labelLargeNumeric)
                    .foregroundStyle(.primary)
                    .monospacedDigit()

                Spacer()

                Text(String(format: "%+.1f dB", currentGain))
                    .font(M3ETypography.labelLargeNumeric)
                    .foregroundStyle(audioEngine.isEQEnabled ? AppTheme.accent : Color.secondary)
                    .monospacedDigit()
            }

            // ✅ M3E (Bloque 1 aplicado): slider propio. Pista de 10 pt, thumb
            // de 26 pt con rebote elástico al agarrar y relleno DESDE 0 dB
            // (el EQ necesita crecer desde el centro; `Slider` solo rellena
            // desde el mínimo). Ninguna API por encima de iOS 16.
            AuroraM3Slider(
                value: Double(currentGain),
                range: -12...12,
                step: 0.5,
                isEnabled: audioEngine.isEQEnabled,
                fillFromCenter: true,
                accessibilityLabel: frequencyName,
                onChange: { newVal in
                    audioEngine.setEQGain(for: bandIndex, gain: Float(newVal))
                }
            )
            .padding(.vertical, 4)
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