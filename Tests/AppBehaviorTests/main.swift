// autor: Codex, gadula-stabilnosc-20260927
import AppKit
import AVFoundation
import VoiceAgentCore

@main enum ProbyAdapterow {
    @MainActor static func main() async throws {
        var bledy = 0
        func sprawdz(_ warunek: Bool, _ nazwa: String) {
            print("\(warunek ? "PASS" : "FAIL") \(nazwa)")
            if !warunek { bledy += 1 }
        }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let adapter = SchowekTextInserting(schowek: board, maDostep: { true }, wklej: { false })
        _ = await adapter.insert(tekst: "Niewklejony transkrypt")
        sprawdz(board.string(forType: .string) == "Niewklejony transkrypt", "brak celu nie usuwa transkryptu")

        let kopiowanie = SchowekTextInserting(schowek: board, maDostep: { true }, wklej: {
            board.clearContents()
            board.setString("Nowe kopiowanie", forType: .string)
            return true
        })
        _ = await kopiowanie.insert(tekst: "Dyktowanie")
        sprawdz(board.string(forType: .string) == "Nowe kopiowanie", "aplikacja nie cofa nowego kopiowania")
        let bezZgody = SchowekTextInserting(schowek: board, maDostep: { false }, wklej: { fatalError("Bez Dostępności nie wysyłamy klawiszy") })
        let wynik = await bezZgody.insert(tekst: "Zażółć gęślą jaźń")
        sprawdz(wynik == .tylkoSchowek && board.string(forType: .string) == "Zażółć gęślą jaźń", "bez Dostępności pozostaje schowek")

        // Artefakty testowe zostają w .build, nie dotykamy prawdziwego cache modeli.
        let folder = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("AudioEncoder.mlmodelc"), withIntermediateDirectories: true)
        sprawdz(!WagiModeluNaDysku.saKompletne(folder: folder), "jeden komponent nie jest gotowym modelem")
        for nazwa in ["MelSpectrogram", "TextDecoder"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(nazwa + ".mlmodelc"), withIntermediateDirectories: true)
        }
        sprawdz(WagiModeluNaDysku.saKompletne(folder: folder), "trzy komponenty stanowią komplet strukturalny")
        let lockURL = folder.appendingPathComponent("instance.lock")
        var pierwsza: BlokadaInstancji? = try BlokadaInstancji(url: lockURL)
        let druga = try BlokadaInstancji(url: lockURL)
        sprawdz(pierwsza!.przejmij(), "pierwsza instancja może działać")
        sprawdz(!druga.przejmij(), "druga instancja nie przejmuje mikrofonu i skrótu")
        pierwsza = nil
        sprawdz(druga.przejmij(), "po zamknięciu pierwszej można uruchomić aplikację ponownie")

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let bufor = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)!
        bufor.frameLength = 4
        bufor.floatChannelData![0][0] = 0.75
        let kopia = skopiujBuforAudio(bufor)
        bufor.floatChannelData![0][0] = 0
        sprawdz(kopia?.floatChannelData?[0][0] == 0.75, "kolejny callback audio nie zmienia oczekujących próbek")
        exit(bledy == 0 ? 0 : 1)
    }
}
