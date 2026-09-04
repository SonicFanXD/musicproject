import SwiftUI

struct EqualizerView: View {
    @ObservedObject var audioEngine: AudioEngine
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBand: Int = 0
    @State private var currentGain: Float = 0

    let frequencies: [String] = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    let bandDescriptions: [String] = ["Sub-bass", "Bass", "Low-mid", "Mid", "Upper-mid", "Presence", "High-mid", "Treble", "High", "Ultra-high"]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 28) {
                        headerSection

                        if audioEngine.isEQEnabled {
                            VStack(spacing: 24) {
                                presetSelector
                                equalizerSliders
                                customBandControl
                            }
                        } else {
                            disabledEQView
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Equalizador")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        audioEngine.toggleEQ()
                    } label: {
                        Image(systemName: audioEngine.isEQEnabled ? "power.circle.fill" : "power.circle")
                            .foregroundStyle(audioEngine.isEQEnabled ? Color.accentColor : .secondary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 75, height: 75)

                Image(systemName: audioEngine.isEQEnabled ? "slider.horizontal.3" : "power")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(audioEngine.isEQEnabled ? Color.accentColor : .secondary)
            }

            Text("Equalizador")
                .font(.system(size: 24, weight: .bold))

            Text(audioEngine.isEQEnabled ? "Personaliza el sonido de tu música" : "Activa el equalizador para personalizar el sonido")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .opaqueGlass(cornerRadius: 26, tint: .accentColor)
    }

    private var presetSelector: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "music.note.list")
                    .foregroundStyle(Color.accentColor)

                Text("Presets")
                    .font(.system(size: 18, weight: .semibold))
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(EQPreset.allCases, id: \.self) { preset in
                        Button {
                            audioEngine.setEQPreset(preset)
                            updateCurrentGain()
                        } label: {
                            Text(preset.displayName)
                                .font(.system(size: 14, weight: audioEngine.eqPreset == preset ? .semibold : .regular))
                                .foregroundStyle(audioEngine.eqPreset == preset ? .white : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background {
                                    if audioEngine.eqPreset == preset {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.accentColor)
                                    } else {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.secondary.opacity(0.12))
                                    }
                                }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var equalizerSliders: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "slider.horizontal.below.rectangle")
                    .foregroundStyle(Color.accentColor)

                Text("Bandas de frecuencia")
                    .font(.system(size: 18, weight: .semibold))
            }
            .padding(.horizontal, 4)

            VStack(spacing: 16) {
                ForEach(0..<10, id: \.self) { index in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(frequencies[index])
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(bandDescriptions[index])
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 60, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: { audioEngine.getEQGain(for: index) },
                                set: { audioEngine.setEQGain(for: index, gain: $0) }
                            ),
                            in: -12...12,
                            step: 1
                        )
                        .tint(Color.accentColor)

                        Text(String(format: "%.0f dB", audioEngine.getEQGain(for: index)))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var customBandControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "tuningfork")
                    .foregroundStyle(Color.accentColor)

                Text("Control personalizado")
                    .font(.system(size: 18, weight: .semibold))
            }
            .padding(.horizontal, 4)

            VStack(spacing: 16) {
                HStack {
                    Text("Banda seleccionada")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Picker("Banda", selection: $selectedBand) {
                        ForEach(0..<10, id: \.self) { index in
                            Text("\(frequencies[index]) Hz")
                                .tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                VStack(spacing: 8) {
                    Text("Ganancia: \(String(format: "%.1f dB", currentGain))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    Slider(
                        value: $currentGain,
                        in: -12...12,
                        step: 0.5
                    ) { _ in
                        audioEngine.setEQGain(for: selectedBand, gain: currentGain)
                    }
                    .tint(Color.accentColor)

                    HStack {
                        Text("-12 dB")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)

                        Spacer()

                        Text("0 dB")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)

                        Spacer()

                        Text("+12 dB")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .onAppear {
            updateCurrentGain()
        }
        .onChange(of: selectedBand) { _ in
            updateCurrentGain()
        }
    }

    private var disabledEQView: some View {
        VStack(spacing: 16) {
            Image(systemName: "power.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("Equalizador desactivado")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Activa el equalizador desde el botón en la esquina superior izquierda para personalizar el sonido.")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 32)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private func updateCurrentGain() {
        currentGain = audioEngine.getEQGain(for: selectedBand)
    }
}