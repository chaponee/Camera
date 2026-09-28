import SwiftUI
import AVKit
import PhotosUI
import AudioToolbox

// MARK: - Camera Modes & Aspect Ratio Configuration
enum CameraMode: String, CaseIterable, Identifiable {
    case cinematic = "CINEMATIC"
    case slomo = "SLO-MO"
    case video = "VIDEO"
    case photo = "PHOTO"
    case portrait = "PORTRAIT"
    case pano = "PANO"

    var id: String { rawValue }

    var is4By3: Bool {
        self == .photo || self == .portrait || self == .pano
    }
}

// MARK: - Native Palette
extension Color {
    static let cameraYellow = Color(red: 255/255, green: 204/255, blue: 0/255)
    static let settingsCardBg = Color(white: 0.12)
    static let settingsPurple = Color(red: 130/255, green: 110/255, blue: 255/255)
}

// MARK: - Main Camera View
struct ContentView: View {
    // Hidden Configurations
    @State private var backVideoURL: URL?
    @State private var frontVideoURL: URL?
    @State private var thumbnailImage: UIImage?
    @State private var loopFootage = true
    @State private var restartOnOpen = true
    @State private var showSettings = false
    
    // Viewfinder States
    @State private var isFrontCamera = false
    @State private var selectedMode: CameraMode = .video
    @State private var selectedZoom: String = "1x"
    @State private var isRecording = false
    @State private var recordingTime = 0
    @State private var timer: Timer?

    // Animations
    @State private var modeSwitchingBlur: Double = 0.0
    @State private var shutterFlash: Double = 0.0

    var currentVideoURL: URL? {
        if isFrontCamera {
            return frontVideoURL ?? backVideoURL
        }
        return backVideoURL
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // MARK: 1. Viewfinder Frame
            GeometryReader { geometry in
                ZStack {
                    if let activeURL = currentVideoURL {
                        LoopingVideoPlayer(
                            url: activeURL,
                            shouldLoop: loopFootage,
                            restartOnOpen: restartOnOpen
                        )
                        .aspectRatio(selectedMode.is4By3 ? 3/4 : nil, contentMode: selectedMode.is4By3 ? .fit : .fill)
                        .frame(width: geometry.size.width)
                        .clipped()
                        .blur(radius: modeSwitchingBlur)
                        .scaleEffect(modeSwitchingBlur > 0 ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.22), value: modeSwitchingBlur)
                        .animation(.easeInOut(duration: 0.25), value: selectedMode)
                    } else {
                        Color.black
                            .overlay(
                                VStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 38))
                                    Text("Double-tap screen with 2 fingers to set video")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(.gray)
                            )
                    }

                    Color.black
                        .opacity(shutterFlash)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(edges: selectedMode.is4By3 ? [] : .all)

            // MARK: 2. Camera Overlay HUD
            VStack(spacing: 0) {
                
                // --- TOP CONTROL BAR (Aligned to Dynamic Island) ---
                HStack {
                    Button(action: triggerHaptic) {
                        Image(systemName: "bolt.slash.fill")
                            .font(.system(size: 17, weight: .semibold))
                    }

                    Spacer()

                    // Recording Timer Badge
                    if isRecording {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                            Text(timeFormatted(recordingTime))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(12)
                    }

                    Spacer()

                    Button(action: triggerHaptic) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 14, weight: .bold))
                            .padding(6)
                            .background(Color.black.opacity(0.35))
                            .clipShape(Circle())
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                // --- BOTTOM PANEL ---
                VStack(spacing: 12) {
                    
                    // Zoom Switcher Bubbles (.5x, 1x, 2x, 3x)
                    HStack(spacing: 14) {
                        ForEach([".5", "1x", "2x", "3x"], id: \.self) { zoom in
                            Button(action: {
                                triggerHaptic()
                                withAnimation { selectedZoom = zoom }
                            }) {
                                Text(zoom)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(selectedZoom == zoom ? .cameraYellow : .white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                        }
                    }

                    // Mode Selector Carousel
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                ForEach(CameraMode.allCases) { mode in
                                    Text(mode.rawValue)
                                        .font(.system(size: 13, weight: .bold, design: .default))
                                        .tracking(1.0)
                                        .foregroundColor(selectedMode == mode ? .cameraYellow : .white.opacity(0.65))
                                        .id(mode)
                                        .onTapGesture {
                                            switchMode(to: mode, proxy: proxy)
                                        }
                                }
                            }
                            .padding(.horizontal, UIScreen.main.bounds.width / 2 - 30)
                        }
                    }

                    // Shutter & Actions
                    HStack {
                        // Dynamic Gallery Photo Thumbnail
                        Group {
                            if let img = thumbnailImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color(white: 0.2)
                            }
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.6), lineWidth: 1)
                        )

                        Spacer()

                        // Shutter Button
                        Button(action: handleShutterTap) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 76, height: 76)

                                if selectedMode == .video || selectedMode == .slomo {
                                    RoundedRectangle(cornerRadius: isRecording ? 6 : 34)
                                        .fill(Color.red)
                                        .frame(
                                            width: isRecording ? 26 : 62,
                                            height: isRecording ? 26 : 62
                                        )
                                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isRecording)
                                } else {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 62, height: 62)
                                }
                            }
                        }

                        Spacer()

                        // Flip Camera Lens Button
                        Button(action: flipCamera) {
                            ZStack {
                                Circle()
                                    .fill(Color(white: 0.18))
                                    .frame(width: 46, height: 46)

                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 34)
                }
                .background(
                    selectedMode.is4By3 ? Color.black : Color.clear
                )
            }
            .ignoresSafeArea(edges: .top) // Allows controls to draw up beside Dynamic Island
        }
        .statusBar(hidden: true) // Hides clock, Wi-Fi, and battery status icons
        .onTapGesture(count: 2) {
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                backVideoURL: $backVideoURL,
                frontVideoURL: $frontVideoURL,
                thumbnailImage: $thumbnailImage,
                loopFootage: $loopFootage,
                restartOnOpen: $restartOnOpen
            )
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Actions

    private func handleShutterTap() {
        triggerHaptic()
        if selectedMode == .video || selectedMode == .slomo {
            toggleRecording()
        } else {
            AudioServicesPlaySystemSound(1108)
            withAnimation(.easeInOut(duration: 0.08)) { shutterFlash = 0.9 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                withAnimation(.easeInOut(duration: 0.12)) { shutterFlash = 0.0 }
            }
        }
    }

    private func switchMode(to mode: CameraMode, proxy: ScrollViewProxy) {
        guard selectedMode != mode else { return }
        triggerHaptic()

        withAnimation {
            modeSwitchingBlur = 10.0
            selectedMode = mode
            proxy.scrollTo(mode, anchor: .center)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation { modeSwitchingBlur = 0.0 }
        }
    }

    private func flipCamera() {
        triggerHaptic()
        withAnimation {
            modeSwitchingBlur = 14.0
            isFrontCamera.toggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation { modeSwitchingBlur = 0.0 }
        }
    }

    private func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            AudioServicesPlaySystemSound(1117)
            recordingTime = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                recordingTime += 1
            }
        } else {
            AudioServicesPlaySystemSound(1118)
            timer?.invalidate()
            timer = nil
        }
    }

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func timeFormatted(_ totalSeconds: Int) -> String {
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// MARK: - Dark Settings Interface
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var backVideoURL: URL?
    @Binding var frontVideoURL: URL?
    @Binding var thumbnailImage: UIImage?
    @Binding var loopFootage: Bool
    @Binding var restartOnOpen: Bool

    @State private var backPickerItem: PhotosPickerItem?
    @State private var frontPickerItem: PhotosPickerItem?
    @State private var thumbnailPickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Privacy Note
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.gray)
                        Text("Footage never leaves your device. It is stored on this phone only.")[span_0](start_span)[span_0](end_span)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.settingsCardBg)
                    .cornerRadius(12)

                    // Back Camera Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BACK CAMERA")[span_1](start_span)[span_1](end_span)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .bold()

                        Text("Plays where the live view would be when the camera opens.")[span_2](start_span)[span_2](end_span)
                            .font(.caption2)
                            .foregroundColor(.gray)

                        PhotosPicker(selection: $backPickerItem, matching: .videos) {
                            FootageCardView(
                                title: backVideoURL == nil ? "Add footage" : "Change footage",[span_3](start_span)[span_3](end_span)
                                subtitle: "Videos from your photo library",[span_4](start_span)[span_4](end_span)
                                isLoaded: backVideoURL != nil
                            )
                        }
                    }

                    // Front Camera Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FRONT CAMERA")[span_5](start_span)[span_5](end_span)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .bold()

                        Text("Plays after you tap the flip button. Leave it empty to keep showing the back camera footage.")[span_6](start_span)[span_6](end_span)
                            .font(.caption2)
                            .foregroundColor(.gray)

                        PhotosPicker(selection: $frontPickerItem, matching: .videos) {
                            FootageCardView(
                                title: frontVideoURL == nil ? "Add footage" : "Change footage",[span_7](start_span)[span_7](end_span)
                                subtitle: "Videos from your photo library",[span_8](start_span)[span_8](end_span)
                                isLoaded: frontVideoURL != nil
                            )
                        }
                    }

                    // Gallery Thumbnail Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GALLERY THUMBNAIL")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .bold()

                        Text("Displays as the small recent photo preview in the bottom left corner.")
                            .font(.caption2)
                            .foregroundColor(.gray)

                        PhotosPicker(selection: $thumbnailPickerItem, matching: .images) {
                            FootageCardView(
                                title: thumbnailImage == nil ? "Add photo thumbnail" : "Change photo thumbnail",
                                subtitle: "Photos from your photo library",
                                isLoaded: thumbnailImage != nil
                            )
                        }
                    }

                    // Playback Settings
                    VStack(alignment: .leading, spacing: 14) {
                        Text("PLAYBACK")[span_9](start_span)[span_9](end_span)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .bold()

                        VStack(spacing: 16) {
                            Toggle("Loop footage", isOn: $loopFootage)[span_10](start_span)[span_10](end_span)
                                .tint(.green)

                            Divider().background(Color.gray.opacity(0.3))

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Restart on open", isOn: $restartOnOpen)[span_11](start_span)[span_11](end_span)
                                    .tint(.green)
                                Text("Plays from the start every time you open the app. Off, it carries on where it left off.")[span_12](start_span)[span_12](end_span)
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(Color.settingsCardBg)
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {[span_13](start_span)[span_13](end_span)
                        dismiss()
                    }
                    .bold()
                    .foregroundColor(.settingsPurple)
                }
            }
        }
        .onChange(of: backPickerItem) { newItem in
            saveVideo(from: newItem) { url in backVideoURL = url }
        }
        .onChange(of: frontPickerItem) { newItem in
            saveVideo(from: newItem) { url in frontVideoURL = url }
        }
        .onChange(of: thumbnailPickerItem) { newItem in
            saveImage(from: newItem) { img in thumbnailImage = img }
        }
    }

    private func saveVideo(from item: PhotosPickerItem?, completion: @escaping (URL) -> Void) {
        Task {
            if let data = try? await item?.loadTransferable(type: Data.self) {
                let filename = UUID().uuidString + ".mp4"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try? data.write(to: tempURL)
                await MainActor.run { completion(tempURL) }
            }
        }
    }

    private func saveImage(from item: PhotosPickerItem?, completion: @escaping (UIImage) -> Void) {
        Task {
            if let data = try? await item?.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run { completion(image) }
            }
        }
    }
}

struct FootageCardView: View {
    let title: String
    let subtitle: String
    let isLoaded: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isLoaded ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.title)
                .foregroundColor(isLoaded ? .green : .settingsPurple)

            Text(title)
                .font(.callout)
                .bold()
                .foregroundColor(.white)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color.settingsCardBg)
        .cornerRadius(12)
    }
}

// MARK: - Native Video Engine
struct LoopingVideoPlayer: UIViewRepresentable {
    let url: URL
    let shouldLoop: Bool
    let restartOnOpen: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let player = AVQueuePlayer()
        let playerLayer = AVPlayerLayer(player: player)

        playerLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(playerLayer)

        let item = AVPlayerItem(url: url)

        if shouldLoop {
            let looper = AVPlayerLooper(player: player, templateItem: item)
            context.coordinator.looper = looper
        } else {
            player.replaceCurrentItem(with: item)
        }

        if restartOnOpen {
            player.seek(to: .zero)
        }

        player.play()
        context.coordinator.playerLayer = playerLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.playerLayer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var looper: AVPlayerLooper?
        var playerLayer: AVPlayerLayer?
    }
}
