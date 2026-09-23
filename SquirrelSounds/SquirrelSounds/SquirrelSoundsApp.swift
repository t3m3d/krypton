import SwiftUI
import AVFoundation

@main
struct SquirrelSoundsApp: App {
    var body: some Scene {
        WindowGroup { LibraryView() }
    }
}

struct LibraryView: View {
    @StateObject private var audio = AudioPlayer()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("favoriteSoundIDs") private var storedFavorites = ""
    @State private var animals: [Animal] = []
    @State private var loadError = false
    @State private var favoritesOnly = false
    @State private var showAbout = false
    private let forest = Color(red: 0.15, green: 0.29, blue: 0.22)
    private var favorites: Set<String> { Set(storedFavorites.split(separator: ",").map(String.init)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    hero
                    Picker("Library filter", selection: $favoritesOnly) {
                        Text("All sounds").tag(false)
                        Text("Favorites").tag(true)
                    }.pickerStyle(.segmented)
                    if loadError {
                        ContentUnavailableView("Library unavailable", systemImage: "exclamationmark.triangle", description: Text("Please close and reopen the app to try again."))
                    } else if favoritesOnly && !animals.flatMap(\.sounds).contains(where: { favorites.contains($0.id) }) {
                        ContentUnavailableView("Your listening collection", systemImage: "heart", description: Text("Tap the heart beside a recording to save it here."))
                    } else {
                        ForEach(animals) { animal in
                            let sounds = animal.sounds.filter { !favoritesOnly || favorites.contains($0.id) }
                            if !sounds.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(animal.name).font(.title2.bold())
                                    Text(animal.scientificName).font(.subheadline.italic()).foregroundStyle(.secondary)
                                    Text(animal.introduction).font(.subheadline).foregroundStyle(.secondary)
                                }
                                ForEach(sounds) { sound in soundCard(sound) }
                            }
                        }
                    }
                    Label("Listen to learn. Give wildlife space.", systemImage: "leaf")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(22)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Squirrel Sounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { showAbout = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("About and listening tips")
            }
            .sheet(isPresented: $showAbout) { about }
            .alert("Playback unavailable", isPresented: Binding(get: { audio.error != nil }, set: { if !$0 { audio.error = nil } })) {
                Button("OK", role: .cancel) { audio.error = nil }
            } message: { Text(audio.error ?? "") }
            .task {
                do { animals = try Catalog.load() }
                catch { loadError = true }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { audio.pause() } }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in audio.pause() }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
                if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { audio.pause() }
            }
        }.tint(forest)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("THE WOODLAND COLLECTION", systemImage: "leaf.fill")
                    .font(.caption.weight(.semibold)).tracking(1)
                Spacer()
                Text("🐿️").font(.system(size: 48)).accessibilityHidden(true)
            }
            Text("A little closer\nto the wild.").font(.system(.largeTitle, design: .serif).weight(.medium))
            Text("Get to know squirrels, one sound at a time.").font(.subheadline)
        }
        .foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(forest.gradient, in: RoundedRectangle(cornerRadius: 28))
    }

    private func soundCard(_ sound: AnimalSound) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "waveform").font(.title).foregroundStyle(forest)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sound.title).font(.headline)
                    Text(sound.localURL == nil ? "Recording not installed" : "Available offline")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    var next = favorites
                    if next.contains(sound.id) { next.remove(sound.id) } else { next.insert(sound.id) }
                    storedFavorites = next.sorted().joined(separator: ",")
                } label: {
                    Image(systemName: favorites.contains(sound.id) ? "heart.fill" : "heart")
                        .frame(width: 44, height: 44)
                }.accessibilityLabel(favorites.contains(sound.id) ? "Remove from favorites" : "Add to favorites")
            }
            Text(sound.description).font(.subheadline).foregroundStyle(.secondary)
            if audio.currentID == sound.id {
                Slider(value: Binding(get: { audio.progress }, set: { audio.seek(to: $0) }), in: 0...max(audio.duration, 1))
                    .accessibilityLabel("Recording position")
                HStack {
                    Text(time(audio.progress))
                    Spacer()
                    Text(time(audio.duration))
                }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button { audio.toggle(sound) } label: {
                Label(audio.currentID == sound.id && audio.isPlaying ? "Pause recording" : "Play recording", systemImage: audio.currentID == sound.id && audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).disabled(sound.localURL == nil)
            DisclosureGroup("Recording credits") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(sound.credit).font(.caption)
                    Link("Original recording & download", destination: sound.sourceURL)
                    Link(sound.license, destination: sound.licenseURL)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
            }.font(.subheadline)
        }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    private var about: some View {
        NavigationStack {
            List {
                Section("Listen with care") {
                    Text("Use headphones to explore recordings without disturbing animals. Watch wildlife from a distance and let animals carry on with their day.")
                    Text("Do not use recordings to lure, touch, or feed wild animals.")
                    Link("Wildlife watching guidance", destination: URL(string: "https://www.nps.gov/subjects/watchingwildlife/7ways.htm")!)
                }
                Section("Your privacy") {
                    Text("Favorites stay on this device. No account, microphone access, location tracking, or analytics. Opening source links takes you to external websites.")
                }
                Section("A growing collection") {
                    Text("Starting with squirrels. More recordings and animals can join this library in future updates.")
                }
            }.navigationTitle("About")
                .toolbar { Button("Done") { showAbout = false } }
        }
    }

    private func time(_ value: Double) -> String {
        let seconds = Int(value)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
