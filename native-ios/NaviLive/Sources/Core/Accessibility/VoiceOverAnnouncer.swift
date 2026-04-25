import AVFoundation
import UIKit

enum NavigationSoundCue {
  case countdown
  case turnNow
  case warning
  case success
  case arrival
}

@MainActor
final class VoiceOverAnnouncer: NSObject {
  private let synthesizer = AVSpeechSynthesizer()
  private var cuePlayers: [AVAudioPlayer] = []
  private var navigationSpeechSessionActive = false

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func announce(_ message: String, settings: AppSettings) {
    guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    let shouldUseVoiceOver: Bool
    switch settings.speechMode {
    case .automatic:
      shouldUseVoiceOver = UIAccessibility.isVoiceOverRunning
    case .voiceOver:
      shouldUseVoiceOver = true
    case .speechSynthesizer:
      shouldUseVoiceOver = false
    }

    if shouldUseVoiceOver {
      UIAccessibility.post(notification: .announcement, argument: message)
      return
    }

    speakWithSynthesizer(message, settings: settings, usesNavigationAudioSession: false)
  }

  func announceNavigation(_ message: String, settings: AppSettings) {
    guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    speakWithSynthesizer(message, settings: settings, usesNavigationAudioSession: true)
  }

  func previewSynthesizer(_ message: String, settings: AppSettings) {
    guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    speakWithSynthesizer(message, settings: settings, usesNavigationAudioSession: false)
  }

  func stopSpeech() {
    synthesizer.stopSpeaking(at: .immediate)
    deactivateNavigationAudioSession()
  }

  private func speakWithSynthesizer(
    _ message: String,
    settings: AppSettings,
    usesNavigationAudioSession: Bool
  ) {
    if usesNavigationAudioSession {
      prepareNavigationAudioSession()
    }

    let utterance = AVSpeechUtterance(string: message)
    utterance.rate = Float(max(0.35, min(settings.speechRate, 1.6)))
    utterance.volume = Float(max(0.1, min(settings.speechVolume, 1.0)))
    utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
    synthesizer.stopSpeaking(at: .immediate)
    synthesizer.speak(utterance)
  }

  private func prepareNavigationAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
      try session.setActive(true)
      navigationSpeechSessionActive = true
    } catch {
      navigationSpeechSessionActive = false
    }
  }

  private func deactivateNavigationAudioSession() {
    guard navigationSpeechSessionActive else { return }
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      // Leave audio session as-is when deactivation fails.
    }
    navigationSpeechSessionActive = false
  }

  func hapticSuccess() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
  }

  func hapticWarning() {
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
  }

  func playSoundCue(_ cue: NavigationSoundCue) {
    prepareNavigationAudioSession()
    guard let player = try? AVAudioPlayer(data: cue.wavData()) else { return }
    player.volume = 0.18
    player.prepareToPlay()
    cuePlayers.append(player)
    player.play()

    Task { @MainActor [weak self, weak player] in
      let cleanupDelay = UInt64((cue.durationSeconds + 0.35) * 1_000_000_000)
      try? await Task.sleep(nanoseconds: cleanupDelay)
      guard let player else { return }
      self?.cuePlayers.removeAll { $0 === player }
    }
  }
}

private extension NavigationSoundCue {
  var tones: [ToneSpec] {
    switch self {
    case .countdown:
      return [ToneSpec(frequency: 620, duration: 0.065)]
    case .turnNow:
      return [
        ToneSpec(frequency: 720, duration: 0.075, gapAfter: 0.022),
        ToneSpec(frequency: 880, duration: 0.085)
      ]
    case .warning:
      return [
        ToneSpec(frequency: 520, duration: 0.080, gapAfter: 0.026, amplitude: 0.14),
        ToneSpec(frequency: 420, duration: 0.090, amplitude: 0.14)
      ]
    case .success:
      return [
        ToneSpec(frequency: 660, duration: 0.070, gapAfter: 0.022),
        ToneSpec(frequency: 880, duration: 0.085)
      ]
    case .arrival:
      return [
        ToneSpec(frequency: 660, duration: 0.075, gapAfter: 0.024),
        ToneSpec(frequency: 830, duration: 0.085, gapAfter: 0.024),
        ToneSpec(frequency: 1040, duration: 0.100)
      ]
    }
  }

  var durationSeconds: TimeInterval {
    tones.reduce(0) { $0 + $1.duration + $1.gapAfter }
  }

  func wavData(sampleRate: Int = 44_100) -> Data {
    var samples: [Int16] = []
    tones.forEach { tone in
      let toneSampleCount = Int(Double(sampleRate) * tone.duration)
      for index in 0..<toneSampleCount {
        let progress = Double(index) / Double(max(toneSampleCount, 1))
        let envelope: Double
        if progress < 0.12 {
          envelope = progress / 0.12
        } else if progress > 0.82 {
          envelope = (1.0 - progress) / 0.18
        } else {
          envelope = 1.0
        }
        let value = sin(2.0 * .pi * tone.frequency * Double(index) / Double(sampleRate))
        let clampedEnvelope = max(0.0, min(envelope, 1.0))
        let sample = Int16(value * clampedEnvelope * tone.amplitude * Double(Int16.max))
        samples.append(sample)
      }
      samples.append(contentsOf: Array(repeating: 0, count: Int(Double(sampleRate) * tone.gapAfter)))
    }
    return WavDataBuilder.makeMonoPcm16(samples: samples, sampleRate: sampleRate)
  }
}

private struct ToneSpec {
  let frequency: Double
  let duration: TimeInterval
  let gapAfter: TimeInterval
  let amplitude: Double

  init(
    frequency: Double,
    duration: TimeInterval,
    gapAfter: TimeInterval = 0,
    amplitude: Double = 0.13
  ) {
    self.frequency = frequency
    self.duration = duration
    self.gapAfter = gapAfter
    self.amplitude = amplitude
  }
}

private enum WavDataBuilder {
  static func makeMonoPcm16(samples: [Int16], sampleRate: Int) -> Data {
    let bytesPerSample = 2
    let dataSize = UInt32(samples.count * bytesPerSample)
    var data = Data()

    data.appendAscii("RIFF")
    data.appendLittleEndian(UInt32(36) + dataSize)
    data.appendAscii("WAVE")
    data.appendAscii("fmt ")
    data.appendLittleEndian(UInt32(16))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(UInt16(1))
    data.appendLittleEndian(UInt32(sampleRate))
    data.appendLittleEndian(UInt32(sampleRate * bytesPerSample))
    data.appendLittleEndian(UInt16(bytesPerSample))
    data.appendLittleEndian(UInt16(16))
    data.appendAscii("data")
    data.appendLittleEndian(dataSize)
    samples.forEach { data.appendLittleEndian($0) }

    return data
  }
}

private extension Data {
  mutating func appendAscii(_ string: String) {
    if let value = string.data(using: .ascii) {
      append(value)
    }
  }

  mutating func appendLittleEndian(_ value: UInt16) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
  }

  mutating func appendLittleEndian(_ value: UInt32) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
  }

  mutating func appendLittleEndian(_ value: Int16) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
  }
}

extension VoiceOverAnnouncer: AVSpeechSynthesizerDelegate {
  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in
      deactivateNavigationAudioSession()
    }
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    Task { @MainActor in
      deactivateNavigationAudioSession()
    }
  }
}
