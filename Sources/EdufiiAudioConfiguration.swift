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
    /// Универсальный сборщик настроек для AVAssetWriterInput (audio)
    ///
    /// - Возвращает:
    ///   - AAC (kAudioFormatMPEG4AAC) при "нормальном" layout (1–2 канала, без exotic tag)
    ///   - PCM (kAudioFormatLinearPCM) при экзотическом layout или >2 каналов
    ///
    /// - Важно:
    ///   - Не ставит AVChannelLayoutKey, чтобы не ловить крэши из-за несоответствия.
    private func makeAudioOutputSettings(from sampleBuffer: CMSampleBuffer) -> [String: Any]? {
        // format description
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            print("⚠️ makeAudioOutputSettings: no formatDesc")
            return nil
        }
        
        // StreamBasicDescription
        guard let sbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            print("⚠️ makeAudioOutputSettings: no SBD")
            return nil
        }
        
        let sbd = sbdPtr.pointee
        let sampleRate = sbd.mSampleRate
        let channels = Int(sbd.mChannelsPerFrame)
        
        guard sampleRate > 0, channels > 0 else {
            print("⚠️ makeAudioOutputSettings: invalid sampleRate (\(sampleRate)) or channels (\(channels))")
            return nil
        }
        
        // Channel layout (can be nil)
        var layoutSize: Int = 0
        let layoutPtr = CMAudioFormatDescriptionGetChannelLayout(formatDesc, sizeOut: &layoutSize)
        var layoutTag: AudioChannelLayoutTag? = nil
        if let layoutPtr {
            layoutTag = layoutPtr.pointee.mChannelLayoutTag
        }
        
        let tag = layoutTag ?? kAudioChannelLayoutTag_Unknown
        
        // Exotic layout = UseChannelDescriptions / UseChannelBitmap или >2 каналов
        let isExoticLayout =
        (channels > 2 ||
         tag == kAudioChannelLayoutTag_UseChannelDescriptions ||
         tag == kAudioChannelLayoutTag_UseChannelBitmap ||
         tag == kAudioChannelLayoutTag_Unknown)
        
        // MARK: An attempt to congigure AAC
        if !isExoticLayout {
            var settings: [String: Any] = [:]
            
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVSampleRateKey] = sampleRate
            settings[AVNumberOfChannelsKey] = channels
            
            // VBR Bitraite
            settings[AVEncoderBitRateStrategyKey] = AVAudioBitRateStrategy_VariableConstrained
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
            
            print("🎧 makeAudioOutputSettings: using AAC, sr=\(sampleRate), ch=\(channels), tag=\(tag)")
            return settings
        }
        
        // MARK: PCM fallback (exotic layout / multichanel)
        var pcmSettings: [String: Any] = [:]
        pcmSettings[AVFormatIDKey] = kAudioFormatLinearPCM
        pcmSettings[AVSampleRateKey] = sampleRate
        pcmSettings[AVNumberOfChannelsKey] = channels
        
        // 16-bit signed integer, little-endian, interleaved
        pcmSettings[AVLinearPCMBitDepthKey] = 16
        pcmSettings[AVLinearPCMIsNonInterleaved] = false
        pcmSettings[AVLinearPCMIsFloatKey] = false
        pcmSettings[AVLinearPCMIsBigEndianKey] = false
        
        print("🎧 makeAudioOutputSettings: using PCM, sr=\(sampleRate), ch=\(channels), tag=\(tag)")
        return pcmSettings
    }
    
    public override func avcaptureSettingsDictionary(sampleBuffer: CMSampleBuffer? = nil,
                                                     pixelBuffer: CVPixelBuffer? = nil) -> [String: Any]? {
        if let settings = self.options, settings.count > 0 {
            return settings
        }
        
        guard let sampleBuffer,
                let settings = makeAudioOutputSettings(from: sampleBuffer) else {
            return nil
        }
        
        self.options = settings
 
        print("🔔 Final audio settings: \(settings)")
    
        return settings
    }
}

