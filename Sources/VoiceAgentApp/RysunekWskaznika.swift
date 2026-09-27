import SwiftUI
import VoiceAgentCore

struct DrobinaWskaznika {
    let x: Double
    let dryf: Double
    let narodziny: Double
    let zycie: Double
    let odcien: Int
}

@MainActor
final class ObrazPigulki: ObservableObject {
    @Published var gotowosc: GotowoscDyktowania = .mikrofon
    @Published var poziom: Float = 0
    @Published var widoczna = false
    @Published var styl: StylWskaznikaNagrywania = .iskry
    @Published var czas: Double = 0
    private(set) var drobiny: [DrobinaWskaznika] = []
    private var emisja: Double = 0
    private var numer = 0

    func przygotuj(styl: StylWskaznikaNagrywania, czas: Double) {
        self.styl = styl
        poziom = 0
        drobiny.removeAll(keepingCapacity: true)
        emisja = 0
        self.czas = czas
    }

    /// Uzywa istniejacego rytmu do 20 Hz. Bez nadrabiania klatek po blokadzie main.
    func odswiez(poziom: Float, czas: Double) {
        if styl == .iskry {
            let dt = min(max(czas - self.czas, 0), 0.1)
            drobiny.removeAll { czas - $0.narodziny >= $0.zycie }
            emisja += Double(poziom) * 48 * dt
            let nowe = min(Int(emisja), max(0, 64 - drobiny.count))
            emisja -= Double(Int(emisja))
            for _ in 0..<nowe {
                numer = (numer + 1) % 997
                let rozrzut = Double((numer * 37) % 101) / 100
                drobiny.append(DrobinaWskaznika(
                    x: 0.15 + 0.7 * rozrzut,
                    dryf: Double((numer * 19) % 21) - 10,
                    narodziny: czas,
                    zycie: 0.7 + Double(numer % 7) * 0.08,
                    odcien: numer % 3
                ))
            }
        }
        self.poziom = poziom
        self.czas = czas
    }
}

struct RysunekWskaznika: View {
    @ObservedObject var obraz: ObrazPigulki

    private var kolor: Color {
        switch obraz.gotowosc {
        case .gotowa: .green
        case .blad: .red
        default: .yellow
        }
    }
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: obraz.gotowosc == .gotowa ? "mic.fill" : (obraz.gotowosc == .blad ? "exclamationmark.circle.fill" : "hourglass"))
                    .foregroundStyle(kolor)
                Text(obraz.gotowosc.komunikat)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(.black.opacity(0.86), in: Capsule())
            .overlay(Capsule().stroke(kolor.opacity(0.7), lineWidth: 1))
            Group {
                switch obraz.styl {
                case .slupki: SlupkiNagrywania(poziom: obraz.poziom)
                case .iskry: IskryNagrywania(drobiny: obraz.drobiny, czas: obraz.czas)
                case .nicSwiatla: NicSwiatla(poziom: obraz.poziom)
                }
            }
            .opacity(obraz.gotowosc == .gotowa ? 1 : 0)
        }
        .opacity(obraz.widoczna ? 1 : 0)
        .animation(.easeInOut(duration: 0.14), value: obraz.widoczna)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(obraz.gotowosc.komunikat)
    }
}

private struct SlupkiNagrywania: View {
    let poziom: Float
    private let wagi: [CGFloat] = [0.35, 0.65, 0.85, 1, 0.85, 0.65, 0.35]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(wagi.indices, id: \.self) { i in
                Capsule()
                    .fill(.green.opacity(0.9))
                    .frame(width: 3, height: 3 + 15 * CGFloat(poziom) * wagi[i])
            }
        }
        .frame(width: 76, height: 28)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .animation(.easeOut(duration: 0.08), value: poziom)
    }
}

private struct IskryNagrywania: View {
    let drobiny: [DrobinaWskaznika]
    let czas: Double

    var body: some View {
        Canvas { context, size in
            for drobina in drobiny {
                let wiek = min(max((czas - drobina.narodziny) / drobina.zycie, 0), 1)
                let alfa = min(wiek * 10, 1) * (1 - wiek)
                let x = size.width * drobina.x + drobina.dryf * wiek
                let y = size.height - 3 - wiek * (size.height - 7)
                // Ciemna obwodka pozostaje widoczna na bieli; jasny rdzen na ciemnym tle.
                let obwodka = Path(ellipseIn: CGRect(x: x - 1.65, y: y - 1.65, width: 3.3, height: 3.3))
                context.fill(obwodka, with: .color(.black.opacity(0.7 * alfa)))
                let kolor: Color = drobina.odcien == 0 ? .green : (drobina.odcien == 1 ? .white : .mint)
                let rdzen = Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                context.fill(rdzen, with: .color(kolor.opacity(alfa)))
            }
        }
    }
}

private struct NicSwiatla: View {
    let poziom: Float

    var body: some View {
        Canvas { context, size in
            let y = size.height - 1
            var baza = Path()
            baza.move(to: CGPoint(x: 0, y: y))
            baza.addLine(to: CGPoint(x: size.width, y: y))
            // Dwie cienkie kreski, bez prostokata tla: kontrast na bieli i czerni.
            context.stroke(baza, with: .color(.black.opacity(0.5)), lineWidth: 2)
            context.stroke(baza, with: .color(.white.opacity(0.55)), lineWidth: 0.6)
            let rozpietosc = size.width * (0.12 + 0.88 * CGFloat(poziom))
            let lewy = CGPoint(x: (size.width - rozpietosc) / 2, y: y)
            let prawy = CGPoint(x: (size.width + rozpietosc) / 2, y: y)
            var swiatlo = Path()
            swiatlo.move(to: lewy)
            swiatlo.addLine(to: prawy)
            let jasnosc = 0.2 + 0.8 * Double(poziom)
            let gradient = Gradient(colors: [.clear, .green.opacity(jasnosc), .white.opacity(jasnosc), .mint.opacity(jasnosc), .clear])
            context.stroke(swiatlo, with: .linearGradient(gradient, startPoint: lewy, endPoint: prawy),
                           lineWidth: 0.7 + CGFloat(poziom))
        }
    }
}
