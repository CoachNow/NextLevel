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
    private(set) var isBluetoothHFPConnected: Bool = false
    
    fileprivate struct AudioFormatCache {
        static var tagsCache = [String: [AudioChannelLayoutTag]]()
        static var channelsCache = [AudioFormatID: [UInt32]]()
    }
    
    fileprivate func availableEncodeChannelLayoutTags(formatID: AudioFormatID, channels: UInt32) -> [AudioChannelLayoutTag] {
        let key = "\(formatID)-\(channels)"
        if let cached = AudioFormatCache.tagsCache[key] { return cached }
        var asbd = AudioStreamBasicDescription(mSampleRate: 44100,
                                               mFormatID: formatID,
                                               mFormatFlags: 0,
                                               mBytesPerPacket: 0,
                                               mFramesPerPacket: 0,
                                               mBytesPerFrame: 0,
                                               mChannelsPerFrame: channels,
                                               mBitsPerChannel: 0,
                                               mReserved: 0)
        var propertySize: UInt32 = 0
        let propID = kAudioFormatProperty_AvailableEncodeChannelLayoutTags
        var status = AudioFormatGetPropertyInfo(propID,
                                                UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
                                                &asbd,
                                                &propertySize)
        guard status == noErr, propertySize > 0 else {
            AudioFormatCache.tagsCache[key] = []
            return []
        }
        let count = Int(propertySize / UInt32(MemoryLayout<AudioChannelLayoutTag>.size))
        var tags = [AudioChannelLayoutTag](repeating: 0, count: count)
        status = AudioFormatGetProperty(propID,
                                        UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
                                        &asbd,
                                        &propertySize,
                                        &tags)
        if status != noErr { tags = [] }
        AudioFormatCache.tagsCache[key] = tags
        return tags
    }
    
    fileprivate func availableEncodeNumberOfChannels(formatID: AudioFormatID) -> [UInt32] {
        if let cached = AudioFormatCache.channelsCache[formatID] { return cached }
        var propSize: UInt32 = 0
        let propID = kAudioFormatProperty_AvailableEncodeNumberChannels
        var status = AudioFormatGetPropertyInfo(propID, 0, nil, &propSize)
        guard status == noErr, propSize > 0 else {
            AudioFormatCache.channelsCache[formatID] = []
            return []
        }
        let count = Int(propSize / UInt32(MemoryLayout<UInt32>.size))
        var values = [UInt32](repeating: 0, count: count)
        status = AudioFormatGetProperty(propID, 0, nil, &propSize, &values)
        if status != noErr { values = [] }
        AudioFormatCache.channelsCache[formatID] = values
        return values
    }
    
    fileprivate func audioChannelLayoutData(for tag: AudioChannelLayoutTag) -> Data {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = tag
        layout.mChannelBitmap = AudioChannelBitmap(rawValue: 0)
        layout.mNumberChannelDescriptions = 0
        
        return withUnsafePointer(to: &layout) { ptr in
            Data(bytes: ptr, count: MemoryLayout<AudioChannelLayout>.size)
        }
    }
    
    fileprivate func monoChannelLayoutData() -> Data {
        return audioChannelLayoutData(for: kAudioChannelLayoutTag_Mono)
    }
    
    private func isChannelLayoutValidForFormat(_ layoutTag: AudioChannelLayoutTag,
                                               channels: UInt32,
                                               format: AudioFormatID) -> Bool {
        // 1) Check if the format supports the requested number of channels
        let supportedChannels = availableEncodeNumberOfChannels(formatID: format)
        if !supportedChannels.isEmpty && !supportedChannels.contains(channels) {
            print("⚠️ Requested \(channels) channels not supported by format \(format). Supported: \(supportedChannels)")
            return false
        }
        // 2) Check supported layout tags for this combination
        let supportedTags =
        availableEncodeChannelLayoutTags(formatID: format, channels: channels)
        if !supportedTags.isEmpty {
            return supportedTags.contains(layoutTag)
        }
        
        // 3) If there is no concrete data from AudioFormatGetProperty, for safety do not return true by default.
        // It's better to return false so that the fallback path (mono/PCM) is used.
        return false
    }
    
    // Helper to fallback to mono layout and update config accordingly
    private func fallbackToMono(_ config: inout [String: Any]) {
        print("🔁 Fallback to mono layout used")
        self.channelsCount = 1
        config[AVNumberOfChannelsKey] = NSNumber(value: 1)
        config[AVChannelLayoutKey] = monoChannelLayoutData()
        invalidateOptionsCache()
    }
    
    // Invalidate cached options when configuration changes
    private func invalidateOptionsCache() {
        self.options = nil
    }
    
    @inline(__always)
    private func setSampleRate(formatDescription: CMFormatDescription?,
                               config: inout [String : Any]) {
        var customSampleRate: Float64 = NextLevelAudioConfiguration.AudioSampleRateDefault
        if let sampleRate = self.sampleRate, sampleRate > 0 {
            customSampleRate = sampleRate
        }
        
        guard let description = formatDescription,
              let streamBasicDescription =
                CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            let rate = min(44100, customSampleRate)
            config[AVSampleRateKey] = NSNumber(value: rate)
            return
        }
        
        let mSampleRate = streamBasicDescription.pointee.mSampleRate
        config[AVSampleRateKey] = min(customSampleRate, mSampleRate)
    }
    
    @inline(__always)
    private func setChannelsCount(formatDescription: CMFormatDescription?,
                                  config: inout [String : Any]) {
        var customCount: Int = NextLevelAudioConfiguration.AudioChannelsCountDefault
        if let count = self.channelsCount, count > 0 {
            customCount = count
        }
        
        guard let description = formatDescription,
              let streamBasicDescription =
                CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            config[AVNumberOfChannelsKey] = NSNumber(value: 1)
            return
        }
        
        let mChannelsCount: Int = Int(streamBasicDescription.pointee.mChannelsPerFrame)
        config[AVNumberOfChannelsKey] = min(mChannelsCount, customCount)
    }
    
    private func fallbackAudioOptions() -> [String: Any] {
        return [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVLinearPCMBitDepthKey: 16,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
    }
    
    public override func avcaptureSettingsDictionary(sampleBuffer: CMSampleBuffer? = nil,
                                                     pixelBuffer: CVPixelBuffer? = nil) -> [String: Any]? {
        
        guard let sb = sampleBuffer else {
            return fallbackAudioOptions()
        }
        
        let session = AVAudioSession.sharedInstance()
        let isBluetoothHFP = session.currentRoute.inputs.contains {
            $0.portType == .bluetoothHFP
        }
        
        if let opts = self.options, opts.count > 0 {
            if self.isBluetoothHFPConnected == isBluetoothHFP {
                return opts
            } else {
                // Invalidate cache if bluetooth state changed
                invalidateOptionsCache()
            }
        }
        
        self.isBluetoothHFPConnected = isBluetoothHFP
        
        var config: [String : Any] = [:]
        
        if self.isBluetoothHFPConnected {
            print("⚠️ Detected Bluetooth HFP input — using PCM for compatibility")
            
            config = fallbackAudioOptions()
            
            let formatDescription: CMFormatDescription? = CMSampleBufferGetFormatDescription(sb)
            setChannelsCount(formatDescription: formatDescription, config: &config)
            
            self.options = config
            
            return config
        }

        config = [AVEncoderBitRateKey : NSNumber(integerLiteral: self.bitRate),
                         AVFormatIDKey: NSNumber(value: self.format as UInt32)]
        
        if let formatDescription: CMFormatDescription = CMSampleBufferGetFormatDescription(sb) {
            setSampleRate(formatDescription: formatDescription, config: &config)
            setChannelsCount(formatDescription: formatDescription, config: &config)
            
            var layoutSize: Int = 0
            if let currentChannelLayout = CMAudioFormatDescriptionGetChannelLayout(formatDescription, sizeOut: &layoutSize),
               layoutSize > 0 {
                let channelsCountToUse = (config[AVNumberOfChannelsKey] as? NSNumber)?.uint32Value ?? 0
                
                let layoutTag = currentChannelLayout.pointee.mChannelLayoutTag
                // Safety check for UseChannelDescriptions with no descriptions
                if layoutTag == kAudioChannelLayoutTag_UseChannelDescriptions &&
                    currentChannelLayout.pointee.mNumberChannelDescriptions == 0 {
                    print("⚠️ LayoutTag is 'UseChannelDescriptions' but no actual descriptions present")
                    fallbackToMono(&config)
                    self.options = config
                    return config
                }
                
                let isValidFormat =
                isChannelLayoutValidForFormat(layoutTag,
                                              channels: channelsCountToUse,
                                              format: self.format)
                if isValidFormat {
                    // CRITICAL: Only check for UseChannelDescriptions case which is the main crash cause
                    if layoutTag == kAudioChannelLayoutTag_UseChannelDescriptions {
                        let layoutChannelCount =
                        currentChannelLayout.pointee.mNumberChannelDescriptions
                        if layoutChannelCount != channelsCountToUse {
                            print("⚠️ UseChannelDescriptions layout channel count mismatch: layout=\(layoutChannelCount), config=\(channelsCountToUse)")
                            fallbackToMono(&config)
                            
                        } else {
                            let data = Data(bytes: currentChannelLayout, count: layoutSize)
                            config[AVChannelLayoutKey] = data
                        }
                    } else {
                        // For standard layout tags, trust the validation and use as-is
                        let data = Data(bytes: currentChannelLayout, count: layoutSize)
                        config[AVChannelLayoutKey] = data
                    }
                } else {
                    // invalid layout for chosen format -> log and force mono
                    print("🛡 Channel layout not compatible with format \(self.format). Forcing mono")
                    fallbackToMono(&config)
                }
            } else {
                // sampleBuffer has no channel layout — for AAC it's better to explicitly set mono layout
                fallbackToMono(&config)
            }
        } else {
            // sampleBuffer or formatDescription is nil, fallback to mono
            setSampleRate(formatDescription: nil, config: &config)
            setChannelsCount(formatDescription: nil, config: &config)
            fallbackToMono(&config)
        }
        
        // Assert required audio config keys are present
        let isFormatIDKeyExist = config[AVFormatIDKey] != nil
        if !isFormatIDKeyExist {
            config[AVFormatIDKey] = kAudioFormatLinearPCM
        }
        
        let isSampleRateKeyExist = config[AVSampleRateKey] != nil
        if !isSampleRateKeyExist {
            config[AVSampleRateKey] = 44100
        }
        
        let isNumberOfChannelsKeyExist = config[AVNumberOfChannelsKey] != nil
        if !isNumberOfChannelsKeyExist {
            fallbackToMono(&config)
        }
        
        print("🔔 Final audio settings: \(config)")
        
        self.options = config
        
        return config
    }
}
