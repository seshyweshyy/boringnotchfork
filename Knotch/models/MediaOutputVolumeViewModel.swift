//
//  MediaOutputVolumeViewModel.swift
//  Knotch
//

import CoreAudio
import Combine
import Foundation

final class MediaOutputVolumeViewModel: ObservableObject {
    @Published var level: Float = 0.5
    @Published var isMuted: Bool = false

    init() {
        syncFromSystem()
        listenForChanges()
    }

    func setVolume(_ value: Float) {
        level = value
        if value > 0 { isMuted = false }
        writeVolume(value)
    }

    func toggleMute() {
        isMuted.toggle()
        setSystemMute(isMuted)
    }

    // MARK: - Private

    private func syncFromSystem() {
        level = readVolume() ?? 0.5
        isMuted = readMute()
    }

    private func listenForChanges() {
        let deviceID = defaultOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }

        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &volAddr, DispatchQueue.main) { [weak self] _, _ in
            self?.syncFromSystem()
        }

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddr, DispatchQueue.main) { [weak self] _, _ in
            self?.syncFromSystem()
        }

        // Re-sync when output device changes
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, DispatchQueue.main) { [weak self] _, _ in
            self?.syncFromSystem()
        }
    }

    private func defaultOutputDeviceID() -> AudioDeviceID {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func readVolume() -> Float? {
        let deviceID = defaultOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    private func writeVolume(_ value: Float) {
        let deviceID = defaultOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var v = max(0, min(1, value))
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &v)
    }

    private func readMute() -> Bool {
        let deviceID = defaultOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted) == noErr else { return false }
        return muted != 0
    }

    private func setSystemMute(_ muted: Bool) {
        let deviceID = defaultOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}
