import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import Recto

@Suite("AudioBufferConverter")
struct AudioBufferConverterTests {

    @Test func `round-trips frame count, sample rate, and presentation time`() throws {
        let sampleRate: Double = 16_000
        let frameCount: AVAudioFrameCount = 800
        let pcmBuffer = try #require(makeSilenceBuffer(
            sampleRate: sampleRate,
            channels: 1,
            frameCount: frameCount
        ))
        let presentationTime = CMTime(value: 12_345, timescale: CMTimeScale(sampleRate))

        let sampleBuffer = try AudioBufferConverter.sampleBuffer(
            from: pcmBuffer,
            presentationTime: presentationTime
        )

        #expect(CMSampleBufferGetNumSamples(sampleBuffer) == Int(frameCount))
        #expect(CMSampleBufferGetPresentationTimeStamp(sampleBuffer) == presentationTime)

        let formatDescription = try #require(CMSampleBufferGetFormatDescription(sampleBuffer))
        let asbdPointer = try #require(
            CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        )
        let asbd = asbdPointer.pointee
        #expect(asbd.mSampleRate == sampleRate)
        #expect(asbd.mChannelsPerFrame == 1)
    }

    @Test func `preserves channel count for stereo input`() throws {
        let pcmBuffer = try #require(makeSilenceBuffer(
            sampleRate: 44_100,
            channels: 2,
            frameCount: 256
        ))

        let sampleBuffer = try AudioBufferConverter.sampleBuffer(
            from: pcmBuffer,
            presentationTime: .zero
        )

        let formatDescription = try #require(CMSampleBufferGetFormatDescription(sampleBuffer))
        let asbdPointer = try #require(
            CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        )
        #expect(asbdPointer.pointee.mChannelsPerFrame == 2)
        #expect(CMSampleBufferGetNumSamples(sampleBuffer) == 256)
    }

    // MARK: - Helpers

    private func makeSilenceBuffer(
        sampleRate: Double,
        channels: AVAudioChannelCount,
        frameCount: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else {
            return nil
        }
        buffer.frameLength = frameCount
        return buffer
    }
}
