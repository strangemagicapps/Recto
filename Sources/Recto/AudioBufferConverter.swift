import AVFoundation
import CoreMedia
import Foundation

/// Converts `AVAudioPCMBuffer` instances produced by `AVAudioEngine`
/// taps into `CMSampleBuffer` instances accepted by
/// ``SpeechService/consume(_:)``.
///
/// The conversion is identical on iOS and macOS, which is why it lives
/// in Recto rather than in the consuming apps. The helper is stateless;
/// every call builds a fresh format description and sample buffer.
///
/// ## When you need it
///
/// ``SpeechService`` accepts audio in exactly one form: `CMSampleBuffer`,
/// Apple's general-purpose container for timed media samples. Some Apple
/// audio APIs already hand you that type; others hand you
/// `AVAudioPCMBuffer`, the container used by Apple's audio-engine APIs.
/// This converter bridges the second case to the first. Which type you
/// get depends only on *which API you used to capture the audio* — so
/// find your capture method in the lists below.
///
/// **If you used one of these, you have `AVAudioPCMBuffer` — convert it.**
/// These are the AVAudioEngine-family APIs, the usual route for recording
/// live microphone input:
///
/// - `AVAudioEngine`: calling
///   `installTap(onBus:bufferSize:format:block:)` on its `inputNode`
///   repeatedly delivers `AVAudioPCMBuffer`s to your callback closure.
///   This is by far the most common source for a live mic feed.
/// - `AVAudioFile`: its `read(into:)` method fills an `AVAudioPCMBuffer`
///   with audio read from a file on disk.
///
/// In these cases, pass each buffer through
/// ``sampleBuffer(from:presentationTime:)`` and hand the result to
/// ``SpeechService/consume(_:)``.
///
/// **If you used one of these, you already have `CMSampleBuffer` — skip
/// this converter** and feed the buffers straight into
/// ``SpeechService/consume(_:)``:
///
/// - `AVCaptureSession` with an `AVCaptureAudioDataOutput` (the same
///   capture stack used for camera/microphone recording): your
///   `captureOutput(_:didOutput:from:)` delegate method receives
///   `CMSampleBuffer`s.
/// - `AVAssetReader` with an `AVAssetReaderTrackOutput` (used to read
///   audio out of an existing movie or audio file):
///   `copyNextSampleBuffer()` returns `CMSampleBuffer`s.
/// - A ReplayKit broadcast extension (used to capture system or app
///   audio): its `processSampleBuffer(_:with:)` callback delivers
///   `CMSampleBuffer`s.
public enum AudioBufferConverter {

    /// Errors that may be thrown by
    /// ``sampleBuffer(from:presentationTime:)``.
    public enum ConversionError: Error, Sendable, Equatable {
        /// `CMAudioFormatDescriptionCreate` failed with the given
        /// `OSStatus`.
        case formatDescriptionCreationFailed(OSStatus)

        /// `CMSampleBufferCreate` failed with the given `OSStatus`.
        case sampleBufferCreationFailed(OSStatus)

        /// `CMSampleBufferSetDataBufferFromAudioBufferList` failed with
        /// the given `OSStatus`.
        case dataBufferAttachmentFailed(OSStatus)
    }

    /// Wraps a PCM audio buffer in a `CMSampleBuffer` carrying the given
    /// presentation timestamp.
    ///
    /// The returned sample buffer shares its audio data with `pcmBuffer`;
    /// the caller must keep `pcmBuffer` alive for as long as the sample
    /// buffer is in use, or copy the data out first.
    ///
    /// - Parameters:
    ///   - pcmBuffer: The PCM audio buffer to wrap. Its `frameLength`
    ///     determines the sample count on the resulting sample buffer.
    ///   - presentationTime: The presentation timestamp to stamp on the
    ///     resulting sample buffer.
    /// - Returns: A new `CMSampleBuffer` describing the same audio.
    /// - Throws: ``ConversionError`` if any of the underlying Core Media
    ///   calls fail.
    public nonisolated static func sampleBuffer(
        from pcmBuffer: AVAudioPCMBuffer,
        presentationTime: CMTime
    ) throws -> CMSampleBuffer {
        var asbd = pcmBuffer.format.streamDescription.pointee

        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw ConversionError.formatDescriptionCreationFailed(formatStatus)
        }

        let frameCount = CMItemCount(pcmBuffer.frameLength)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(asbd.mSampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sampleBuffer else {
            throw ConversionError.sampleBufferCreationFailed(createStatus)
        }

        let attachStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: pcmBuffer.audioBufferList
        )
        guard attachStatus == noErr else {
            throw ConversionError.dataBufferAttachmentFailed(attachStatus)
        }

        return sampleBuffer
    }
}
