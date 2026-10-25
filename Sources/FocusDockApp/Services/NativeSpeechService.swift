import AVFoundation
import Speech
import Combine
import Foundation
import FocusDockCore

@MainActor
final class NativeSpeechService: ObservableObject, SpeechService {
    enum State { case idle, requesting, listening, finishing }
    @Published private(set) var state = State.idle
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var modeDescription = "Apple 系统语音识别；部分语言可能需要联网。"
    var isBusy: Bool { state != .idle }
    private var speechRecognizer: SFSpeechRecognizer?
    private var transcriptBuffer = SpeechTranscriptBuffer()
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()

    func start() async throws {
        guard state == .idle && !Task.isCancelled else { return }
        let session = UUID(); generation = session
        transcriptBuffer = SpeechTranscriptBuffer()
        transcript = ""; errorMessage = nil; state = .requesting
        do {
            let authorization = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard generation == session else { return }
            guard authorization == .authorized else { throw SpeechError.denied }
            let microphone = await AVCaptureDevice.requestAccess(for: .audio)
            guard generation == session else { return }
            guard microphone else { throw SpeechError.microphone }
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else { throw SpeechError.unavailable }
            speechRecognizer = recognizer
            let engine = AVAudioEngine()
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0 && format.channelCount > 0 else { throw SpeechError.noInput }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            request.taskHint = .dictation
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            modeDescription = recognizer.supportsOnDeviceRecognition ? "本次使用本机语音识别" : "本次使用 Apple 在线语音识别"
            self.engine = engine; self.request = request
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                Task { @MainActor in
                    guard let self, self.generation == session else { return }
                    if self.transcriptBuffer.accept(text) { self.transcript = self.transcriptBuffer.text }
                    if final || error != nil {
                        self.endRecognition(isFinal: final, error: error)
                    }
                }
            }
            engine.prepare(); try engine.start(); state = .listening
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(55)) } catch { return }
                guard self?.generation == session else { return }
                self?.finish()
            }
        } catch {
            guard generation == session else { return }
            cleanup(); state = .idle; errorMessage = error.localizedDescription
            throw error
        }
    }
    func finish() {
        guard state == .listening else { return }
        state = .finishing
        timeout?.cancel()
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        request?.endAudio()
        let session = generation
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.generation == session else { return }
            self.endRecognition(isFinal: false, timedOut: true)
        }
    }
    private func endRecognition(isFinal: Bool, error: Error? = nil, timedOut: Bool = false) {
        switch transcriptBuffer.ending(isFinal: isFinal, hasError: error != nil) {
        case .complete:
            errorMessage = nil
        case .partial:
            errorMessage = timedOut ? "最终结果等待超时，已保留录音时识别出的文字，请核对后解析。" : "识别已结束，已保留现有文字，请核对后解析。"
        case .empty:
            if let error {
                errorMessage = "没有识别到文字：\(error.localizedDescription)。请检查麦克风输入后重试，也可手动输入。"
            } else {
                errorMessage = timedOut ? "等待识别结果超时，没有识别到文字。请检查麦克风输入后重新录音，或手动输入。" : "没有识别到文字。请靠近麦克风说话，并在结束录音前确认文字出现；也可手动输入。"
            }
        }
        // Invalidate the callback before cancelling the provider, which can itself emit a callback.
        generation = UUID(); cleanup(); state = .idle
    }
    func cancel() {
        generation = UUID(); cleanup(); state = .idle; transcript = ""; errorMessage = nil
    }
    private func cleanup() {
        timeout?.cancel(); timeout = nil
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil; speechRecognizer = nil
    }
    private enum SpeechError: LocalizedError {
        case denied, microphone, unavailable, noInput
        var errorDescription: String? {
            switch self {
            case .denied: return "语音识别权限未开启。可在系统设置 → 隐私与安全性 → 语音识别中开启，或直接输入文字。"
            case .microphone: return "麦克风权限未开启。可在系统设置 → 隐私与安全性 → 麦克风中开启，或直接输入文字。"
            case .unavailable: return "当前中文语音识别不可用，请检查网络或稍后重试。仍可输入文字。"
            case .noInput: return "没有可用的麦克风，请连接输入设备或直接输入文字。"
            }
        }
    }
}
