import AVFoundation
import CoreMedia
import Foundation
import Speech

/// On-device speech-to-text service backing the Strange Magic page-format
/// apps.
///
/// ``SpeechService`` wraps the iOS 26 / macOS 26 `SpeechAnalyzer` and
/// `SpeechTranscriber` APIs in a single Swift 6.2 actor, accepting audio
/// as `CMSampleBuffer`s and publishing recognised text via the
/// ``transcripts`` stream. Errors that do not terminate recognition are
/// reported on the independent ``errors`` stream.
///
/// Recognition is locked to on-device processing — there is no server
/// fallback under any circumstance.
///
/// ## Lifecycle
///
/// The service is one-shot per session. The expected lifecycle is:
///
/// 1. ``init(locale:)``
/// 2. ``prepare()``
/// 3. Many ``consume(_:)`` calls
/// 4. Optionally ``reset()`` to clear accumulated transcript state
/// 5. ``finish()`` when done — or rely on `deinit` as a safety net
///
/// After ``finish()`` the streams are terminated and the service should
/// be discarded; calling ``prepare()`` again is undefined.
public actor SpeechService {

    /// Lifecycle state of the on-device recognition model.
    public nonisolated enum ModelState: Sendable, Equatable {
        /// The model has not yet been prepared; ``prepare()`` has not
        /// been called, or a previous session has been torn down.
        case notReady

        /// The on-device model is being downloaded. The associated
        /// `progress` value is in the range `0.0 ... 1.0`.
        case downloading(progress: Double)

        /// The model is installed and the analyser is ready to accept
        /// audio buffers.
        case ready

        /// The model or analyser failed terminally. The service will
        /// not accept further buffers until ``prepare()`` is called
        /// again.
        case failed
    }

    /// Errors surfaced by ``SpeechService``.
    ///
    /// Errors of this type are emitted on the ``errors`` stream for
    /// non-fatal conditions (e.g. ``audioConversionFailed``), and
    /// thrown from ``prepare()`` for fatal setup failures.
    public nonisolated enum SpeechServiceError: Error, Sendable, Equatable {
        /// The requested locale is not supported by `SpeechTranscriber`
        /// on this device.
        case unsupportedLocale(Locale)

        /// The on-device model download failed. The associated string
        /// is a human-readable description of the underlying error.
        case modelDownloadFailed(underlying: String)

        /// A single audio buffer could not be converted into a form the
        /// analyser accepts. The buffer was dropped; the service
        /// continues to accept subsequent buffers.
        case audioConversionFailed

        /// The analyser failed mid-session. The associated string is a
        /// human-readable description of the underlying error. The
        /// service has stopped accepting buffers; call ``prepare()`` to
        /// restart.
        case analyserFailed(underlying: String)

        /// A method requiring a prepared analyser (typically
        /// ``consume(_:)``) was called before ``prepare()`` succeeded.
        case notPrepared
    }

    /// Current lifecycle state of the recognition model.
    public private(set) var modelState: ModelState = .notReady

    /// Cumulative recognised text, emitted on every transcription
    /// update.
    ///
    /// The stream remains open across analyser sessions; only
    /// ``finish()`` (or deallocation) terminates it. Consumers may
    /// iterate it on any actor.
    public nonisolated let transcripts: AsyncStream<String>

    /// Non-fatal errors raised during recognition. Independent of
    /// ``transcripts`` — emissions here do not terminate the transcript
    /// stream.
    public nonisolated let errors: AsyncStream<SpeechServiceError>

    private nonisolated let transcriptsContinuation: AsyncStream<String>.Continuation
    private nonisolated let errorsContinuation: AsyncStream<SpeechServiceError>.Continuation

    private let locale: Locale

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    private var finalisedText: String = ""
    private var volatileText: String = ""
    private var isFinished: Bool = false

    /// Creates a new ``SpeechService`` for the given locale.
    ///
    /// The locale is validated by ``prepare()``; construction itself
    /// never fails.
    ///
    /// - Parameter locale: The locale to recognise. Defaults to
    ///   `en-GB`.
    public init(locale: Locale = Locale(identifier: "en-GB")) {
        self.locale = locale

        var transcriptsContinuation: AsyncStream<String>.Continuation!
        self.transcripts = AsyncStream { transcriptsContinuation = $0 }
        self.transcriptsContinuation = transcriptsContinuation

        var errorsContinuation: AsyncStream<SpeechServiceError>.Continuation!
        self.errors = AsyncStream { errorsContinuation = $0 }
        self.errorsContinuation = errorsContinuation
    }

    deinit {
        transcriptsContinuation.finish()
        errorsContinuation.finish()
    }

    /// Validates the locale, downloads the on-device model if needed,
    /// and starts the analyser.
    ///
    /// Calling ``prepare()`` on an already-prepared service tears down
    /// the previous session before starting a new one.
    ///
    /// - Throws: ``SpeechServiceError/unsupportedLocale(_:)`` if the
    ///   locale is not supported,
    ///   ``SpeechServiceError/modelDownloadFailed(underlying:)`` if the
    ///   asset download fails, or
    ///   ``SpeechServiceError/analyserFailed(underlying:)`` if the
    ///   analyser cannot be started.
    public func prepare() async throws {
        guard !isFinished else {
            throw SpeechServiceError.notPrepared
        }

        tearDownAnalyser()
        modelState = .notReady

        let supportedLocales = await SpeechTranscriber.supportedLocales
        let normalisedRequested = locale.identifier(.bcp47).lowercased()
        let isSupported = supportedLocales.contains { candidate in
            candidate.identifier(.bcp47).lowercased() == normalisedRequested
        }
        guard isSupported else {
            throw SpeechServiceError.unsupportedLocale(locale)
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveTranscription
        )

        _ = try? await AssetInventory.reserve(locale: locale)

        if let request = try? await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            modelState = .downloading(progress: request.progress.fractionCompleted)
            progressTask = Task { [weak self] in
                while !Task.isCancelled {
                    let fraction = request.progress.fractionCompleted
                    await self?.updateDownloadProgress(fraction)
                    if request.progress.isFinished || request.progress.isCancelled {
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }

            do {
                try await request.downloadAndInstall()
            } catch {
                progressTask?.cancel()
                progressTask = nil
                modelState = .failed
                let description = String(describing: error)
                errorsContinuation.yield(.modelDownloadFailed(underlying: description))
                throw SpeechServiceError.modelDownloadFailed(underlying: description)
            }

            progressTask?.cancel()
            progressTask = nil
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: nil
        ) else {
            modelState = .failed
            let description = "no compatible audio format available"
            errorsContinuation.yield(.analyserFailed(underlying: description))
            throw SpeechServiceError.analyserFailed(underlying: description)
        }

        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.inputBuilder = inputBuilder
        self.analyzerFormat = format
        self.converter = nil
        self.converterInputFormat = nil
        self.finalisedText = ""
        self.volatileText = ""

        self.resultsTask = Task { [weak self] in
            await self?.consumeResults(from: transcriber)
        }

        do {
            try await analyzer.start(inputSequence: inputSequence)
        } catch {
            tearDownAnalyser()
            modelState = .failed
            let description = String(describing: error)
            errorsContinuation.yield(.analyserFailed(underlying: description))
            throw SpeechServiceError.analyserFailed(underlying: description)
        }

        modelState = .ready
    }

    /// Submits an audio buffer to the analyser.
    ///
    /// If the buffer cannot be converted to the analyser's required
    /// format, ``SpeechServiceError/audioConversionFailed`` is emitted
    /// on the ``errors`` stream and the buffer is dropped; the service
    /// remains usable. Buffers submitted before a successful
    /// ``prepare()`` (or after a fatal failure) are silently ignored.
    ///
    /// Callers driving the service from `AVAudioEngine` should bridge
    /// each `AVAudioPCMBuffer` through
    /// ``AudioBufferConverter/sampleBuffer(from:presentationTime:)``
    /// first.
    ///
    /// - Parameter buffer: A `CMSampleBuffer` of PCM audio.
    public func consume(_ buffer: CMSampleBuffer) async {
        guard !isFinished, modelState == .ready,
              let inputBuilder, let analyzerFormat else {
            return
        }

        guard let pcmBuffer = makePCMBuffer(from: buffer, targetFormat: analyzerFormat) else {
            errorsContinuation.yield(.audioConversionFailed)
            return
        }

        let input = AnalyzerInput(buffer: pcmBuffer)
        inputBuilder.yield(input)
    }

    /// Clears the accumulated transcript state without tearing down the
    /// analyser. Subsequent ``transcripts`` emissions begin from an
    /// empty string.
    public func reset() async {
        finalisedText = ""
        volatileText = ""
        transcriptsContinuation.yield("")
    }

    /// Terminates the analyser, finishes both streams, and releases
    /// resources. Idempotent; subsequent calls are no-ops.
    public func finish() async {
        guard !isFinished else { return }
        isFinished = true

        if let inputBuilder {
            inputBuilder.finish()
        }
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }

        tearDownAnalyser()

        transcriptsContinuation.finish()
        errorsContinuation.finish()
    }

    private func updateDownloadProgress(_ fraction: Double) {
        guard case .downloading(let previous) = modelState, previous != fraction else { return }
        modelState = .downloading(progress: fraction)
    }

    private func consumeResults(from transcriber: SpeechTranscriber) async {
        do {
            for try await result in transcriber.results {
                handleResult(result)
            }
        } catch {
            handleAnalyserFailure(error)
        }
    }

    private func handleResult(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
        if result.isFinal {
            if !finalisedText.isEmpty, !text.isEmpty {
                finalisedText.append(" ")
            }
            finalisedText.append(text)
            volatileText = ""
        } else {
            volatileText = text
        }

        let cumulative: String
        if volatileText.isEmpty {
            cumulative = finalisedText
        } else if finalisedText.isEmpty {
            cumulative = volatileText
        } else {
            cumulative = finalisedText + " " + volatileText
        }
        transcriptsContinuation.yield(cumulative)
    }

    private func handleAnalyserFailure(_ error: any Error) {
        guard !isFinished else { return }
        modelState = .failed
        errorsContinuation.yield(.analyserFailed(underlying: String(describing: error)))
        if let inputBuilder {
            inputBuilder.finish()
        }
        self.inputBuilder = nil
    }

    private func tearDownAnalyser() {
        progressTask?.cancel()
        progressTask = nil
        resultsTask?.cancel()
        resultsTask = nil

        inputBuilder?.finish()
        inputBuilder = nil
        analyzer = nil
        transcriber = nil
        analyzerFormat = nil
        converter = nil
        converterInputFormat = nil
    }

    private func makePCMBuffer(
        from sampleBuffer: CMSampleBuffer,
        targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }
        let inputFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: frameCount
              ) else {
            return nil
        }
        inputBuffer.frameLength = frameCount

        let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: inputBuffer.mutableAudioBufferList
        )
        guard copyStatus == noErr else { return nil }

        if inputFormat.isEqual(targetFormat) {
            return inputBuffer
        }

        if converter == nil || converterInputFormat?.isEqual(inputFormat) != true {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
            converterInputFormat = inputFormat
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(frameCount) * ratio + 1024)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else {
            return nil
        }

        do {
            try converter.convert(to: outputBuffer, from: inputBuffer)
        } catch {
            return nil
        }
        return outputBuffer
    }
}
