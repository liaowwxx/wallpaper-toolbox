import Accelerate
import AVFoundation
import Combine
import Foundation
import ScreenCaptureKit

@MainActor
final class SystemAudioCaptureService: NSObject {
    static let shared = SystemAudioCaptureService()

    private(set) var spectrum64: [Float] = .init(repeating: 0, count: 64)
    let spectrum64Publisher = CurrentValueSubject<[Float], Never>(Array(repeating: 0, count: 64))

    private var stream: SCStream?
    private let fftQueue = DispatchQueue(label: "com.wallpaper.gallery.audio-fft", qos: .userInitiated)
    private let fftSize = 2048
    private let fftSizeLog2 = 11
    private let smoothFactor: Float = 0.30
    private var lastSpectrum64: [Float] = .init(repeating: 0, count: 64)
    private var isRunning = false

    nonisolated(unsafe) private var fftSetup: FFTSetup?
    nonisolated(unsafe) private var hannWindow: [Float] = []
    nonisolated(unsafe) private var lastUpdateTime: UInt64 = 0
    nonisolated private static let updateIntervalNs: UInt64 = 33_000_000

    private override init() {
        super.init()
    }

    func start() {
        guard !isRunning else { return }
        Task { await requestPermissionAndStart() }
    }

    func stop() {
        guard isRunning else { return }
        stream?.stopCapture()
        stream = nil
        isRunning = false
        resetSpectrum()
    }

    private func requestPermissionAndStart() async {
        if !CGPreflightScreenCaptureAccess() {
            let granted = await MainActor.run { CGRequestScreenCaptureAccess() }
            guard granted else { return }
        }
        await startStream()
    }

    private func startStream() async {
        if fftSetup == nil {
            fftSetup = vDSP_create_fftsetup(vDSP_Length(fftSizeLog2), FFTRadix(kFFTRadix2))
        }
        if hannWindow.isEmpty {
            hannWindow = [Float](repeating: 0, count: fftSize)
            vDSP_hann_window(&hannWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }

            let filter = SCContentFilter(display: display, including: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = false
            config.showsCursor = false
            config.width = 1
            config.height = 1
            config.minimumFrameInterval = CMTime(value: 1, timescale: 10)

            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            self.stream = stream
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: fftQueue)
            try await stream.startCapture()
            isRunning = true
        } catch {
            stream = nil
            isRunning = false
        }
    }

    private func resetSpectrum() {
        lastSpectrum64 = .init(repeating: 0, count: 64)
        spectrum64 = .init(repeating: 0, count: 64)
        spectrum64Publisher.send(spectrum64)
    }
}

extension SystemAudioCaptureService: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio,
              let blockBuffer = sampleBuffer.dataBuffer,
              let audioFormat = sampleBuffer.formatDescription,
              audioFormat.mediaType == .audio else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard let dataPointer, length > fftSize * MemoryLayout<Float>.size else { return }
        let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat)
        let channels = Int(asbd?.pointee.mChannelsPerFrame ?? 2)
        let frameLength = length / (MemoryLayout<Float>.size * channels)
        guard frameLength >= fftSize else { return }

        let floatPointer = UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Float.self)
        let samples = UnsafeBufferPointer(start: floatPointer, count: frameLength * channels)
        var monoData = [Float](repeating: 0, count: fftSize)
        for index in 0..<fftSize {
            var sum: Float = 0
            for channel in 0..<channels {
                let sampleIndex = index * channels + channel
                if sampleIndex < samples.count {
                    sum += samples[sampleIndex]
                }
            }
            monoData[index] = sum / Float(channels)
        }

        performFFT(samples: monoData)
    }

    nonisolated private func performFFT(samples: [Float]) {
        guard let fftSetup, hannWindow.count == fftSize else { return }

        var realPart = [Float](repeating: 0, count: fftSize / 2)
        var imagPart = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        var scalar: Float = 1.0 / Float(fftSize)

        realPart.withUnsafeMutableBufferPointer { realBuffer in
            imagPart.withUnsafeMutableBufferPointer { imagBuffer in
                var splitComplex = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                var windowedSamples = [Float](repeating: 0, count: fftSize)
                vDSP_vmul(samples, 1, hannWindow, 1, &windowedSamples, 1, vDSP_Length(fftSize))
                windowedSamples.withUnsafeMutableBufferPointer { pointer in
                    pointer.baseAddress?.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPointer in
                        vDSP_ctoz(complexPointer, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, vDSP_Length(fftSizeLog2), FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        vDSP_vsmul(magnitudes, 1, &scalar, &magnitudes, 1, vDSP_Length(fftSize / 2))

        var dbValues = [Float](repeating: 0, count: fftSize / 2)
        for index in 0..<(fftSize / 2) {
            let magnitude = magnitudes[index]
            dbValues[index] = magnitude > 0 ? max(0, min(1, 20 * log10(magnitude * 10) / 80 + 0.5)) : 0
        }

        let downsampled = downsample(dbValues, targetCount: 64)
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastUpdateTime >= Self.updateIntervalNs else { return }
        lastUpdateTime = now

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.spectrum64 = self.smooth(downsampled, last: self.lastSpectrum64)
            self.lastSpectrum64 = self.spectrum64
            self.spectrum64Publisher.send(self.spectrum64)
        }
    }

    nonisolated private func downsample(_ data: [Float], targetCount: Int) -> [Float] {
        guard targetCount > 0, data.count >= targetCount else { return data }
        var result = [Float](repeating: 0, count: targetCount)
        let binSize = data.count / targetCount
        for index in 0..<targetCount {
            let start = index * binSize
            let end = min(start + binSize, data.count)
            guard start < end else { continue }
            result[index] = data[start..<end].reduce(0, +) / Float(end - start)
        }
        return result
    }

    nonisolated private func smooth(_ new: [Float], last: [Float]) -> [Float] {
        guard new.count == last.count else { return new }
        return zip(new, last).map { previous, current in
            current + (previous - current) * smoothFactor
        }
    }
}
