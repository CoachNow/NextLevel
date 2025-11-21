//
//  EdufiiAudioConfiguration.swift
//  NextLevel
//
//  Created by Chinara Kuzekeeva on 17/9/25.
//  Copyright © 2025 NextLevel. All rights reserved.
//

import Foundation
import AudioToolbox
import AVFoundation

final class EdufiiAudioConfiguration: NextLevelAudioConfiguration {
    private func printIfDebug(_ string: String) {
#if DEBUG
        print(string)
#endif
    }
    
    // Validates the input and returns sample rate and channel count
    // only if both values are greater than zero.
    private func extractAudioFormatInfo(from sampleBuffer: CMSampleBuffer)
    -> (formatDescr: CMFormatDescription, sampleRate: Float64, channelsCount: Int)? {
        guard CMSampleBufferIsValid(sampleBuffer) else {
            printIfDebug("⚠️ extractAudioFormatInfo: sampleBuffer is not valid")
            return nil
        }
        
        guard CMSampleBufferGetNumSamples(sampleBuffer) > 0 else {
            printIfDebug("⚠️ extractAudioFormatInfo: sampleBuffer has no samples")
            return nil
        }

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            printIfDebug("⚠️ makeAudioOutputSettings: no formatDesc")
            return nil
        }
        
        guard let sbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            printIfDebug("⚠️ makeAudioOutputSettings: no SBD")
            return nil
        }
        
        let sbd = sbdPtr.pointee
        let sampleRate = sbd.mSampleRate
        let channels = Int(sbd.mChannelsPerFrame)
        
        guard sampleRate > 0, channels > 0 else {
            printIfDebug("⚠️ makeAudioOutputSettings: invalid sampleRate (\(sampleRate)) or channels (\(channels))")
            return nil
        }
        
        return (formatDesc, sampleRate, channels)
    }
    
    private func shouldUsePCMConfig(formatDescription: CMFormatDescription, channelsCount: Int) -> Bool {
        guard channelsCount <= 2 else {
            return true
        }
        
        var layoutSize: Int = 0
        let layoutPtr =
        CMAudioFormatDescriptionGetChannelLayout(formatDescription, sizeOut: &layoutSize)
        var layoutTag: AudioChannelLayoutTag? = nil
        if let layoutPtr {
            layoutTag = layoutPtr.pointee.mChannelLayoutTag
        }
        
        let tag = layoutTag ?? kAudioChannelLayoutTag_Unknown
        
        let isExoticLayout =
        (tag == kAudioChannelLayoutTag_UseChannelDescriptions ||
         tag == kAudioChannelLayoutTag_UseChannelBitmap ||
         tag == kAudioChannelLayoutTag_Unknown)
        
        return isExoticLayout
    }
    
    private func aacSettings(sampleRate: Float64, channels: Int) -> [String: Any] {
        var settings: [String: Any] = [:]
        
        settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
        settings[AVSampleRateKey] = sampleRate
        settings[AVNumberOfChannelsKey] = channels
        
        // VBR Bitraite
        settings[AVEncoderBitRateStrategyKey] = AVAudioBitRateStrategy_VariableConstrained
        settings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
        
        return settings
    }
    
    private func pcmSettings(sampleRate: Float64, channels: Int) -> [String: Any] {
        var settings: [String: Any] = [:]
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVSampleRateKey] = sampleRate
        settings[AVNumberOfChannelsKey] = channels
        
        // 16-bit signed integer, little-endian, interleaved
        settings[AVLinearPCMBitDepthKey] = 16
        settings[AVLinearPCMIsNonInterleaved] = false
        settings[AVLinearPCMIsFloatKey] = false
        settings[AVLinearPCMIsBigEndianKey] = false
        
        return settings
    }
    
    /// Universal configuration builder for AVAssetWriterInput (audio)
    ///
    /// - Returns:
    ///   - AAC (kAudioFormatMPEG4AAC) for "normal" layouts (1–2 channels, without exotic tags)
    ///   - PCM (kAudioFormatLinearPCM) for exotic layouts or more than 2 channels
    ///
    /// - Important:
    ///   - Does not set AVChannelLayoutKey to avoid crashes due to mismatched layouts.
    private func makeAudioOutputSettings(from sampleBuffer: CMSampleBuffer) -> [String: Any]? {
        guard let result = extractAudioFormatInfo(from: sampleBuffer) else {
            return nil
        }
        
        let sampleRate = result.sampleRate
        let channels = result.channelsCount
        
        let usePCM =
        shouldUsePCMConfig(formatDescription: result.formatDescr, channelsCount: channels)
        
        let settings = usePCM
        ? pcmSettings(sampleRate: sampleRate, channels: channels)
        : aacSettings(sampleRate: sampleRate, channels: channels)
        
#if DEBUG
        let usedFormat: String = usePCM ? "PCM" : "AAC"
        print("🔔 Final audio settings: using \(usedFormat), \(settings)")
#endif
        
        return settings
    }
    
    public override func avcaptureSettingsDictionary(sampleBuffer: CMSampleBuffer? = nil,
                                                     pixelBuffer: CVPixelBuffer? = nil) -> [String: Any]? {
        guard let sampleBuffer,
                let settings = makeAudioOutputSettings(from: sampleBuffer) else {
            return nil
        }
        
        self.options = settings
     
        return settings
    }
}

