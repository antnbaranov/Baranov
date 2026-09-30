//
//  RamReelScene.swift
//  Baranov
//
//  The reel itself: a 12-second, 9:16 scene that is a pure function of
//  time. Because of that the same view plays live (in a `TimelineView`) and
//  is rendered frame by frame into the shareable video (`RamReelExporter`)
//  — what you preview is exactly what you post.
//
//  Beats: 0–2.4 s the ram runs in and is introduced · 2.4–7.6 s the
//  odometer spins while hills scroll and the fun fact types in · 7.6–10.6 s
//  the latest stamp slams down and the ram's personality is revealed ·
//  10.6–12 s the end card.
//
//  It is content, not app chrome, so it uses its own fixed palette.
//

import SwiftUI

enum RamReelSpec {
    static let duration: Double = 14
    static let size = CGSize(width: 360, height: 640)
}

private enum ReelPalette {
    static let ink = Color(red: 0.20, green: 0.13, blue: 0.08)
    static let orange = Color(red: 0.98, green: 0.55, blue: 0.10)
}

/// A colour theme for a whole reel, so each one looks different too.
struct ReelTheme {
    let sky: Color
    let dusk: Color
    let hillFar: Color
    let hillNear: Color
    let ground: Color

    static let all: [ReelTheme] = [
        // Meadow morning
        ReelTheme(sky: Color(red: 1.00, green: 0.91, blue: 0.75), dusk: Color(red: 0.99, green: 0.80, blue: 0.62),
                  hillFar: Color(red: 0.74, green: 0.83, blue: 0.62), hillNear: Color(red: 0.49, green: 0.68, blue: 0.40),
                  ground: Color(red: 0.36, green: 0.55, blue: 0.31)),
        // Alpine blue
        ReelTheme(sky: Color(red: 0.78, green: 0.90, blue: 1.00), dusk: Color(red: 0.62, green: 0.74, blue: 0.95),
                  hillFar: Color(red: 0.70, green: 0.78, blue: 0.90), hillNear: Color(red: 0.45, green: 0.62, blue: 0.78),
                  ground: Color(red: 0.33, green: 0.48, blue: 0.64)),
        // Bubblegum
        ReelTheme(sky: Color(red: 1.00, green: 0.84, blue: 0.90), dusk: Color(red: 0.96, green: 0.68, blue: 0.82),
                  hillFar: Color(red: 0.90, green: 0.75, blue: 0.88), hillNear: Color(red: 0.75, green: 0.55, blue: 0.80),
                  ground: Color(red: 0.58, green: 0.40, blue: 0.66)),
        // Mint dawn
        ReelTheme(sky: Color(red: 0.84, green: 0.97, blue: 0.90), dusk: Color(red: 0.70, green: 0.90, blue: 0.80),
                  hillFar: Color(red: 0.66, green: 0.85, blue: 0.75), hillNear: Color(red: 0.36, green: 0.70, blue: 0.58),
                  ground: Color(red: 0.24, green: 0.52, blue: 0.44)),
        // Sunset orange
        ReelTheme(sky: Color(red: 1.00, green: 0.80, blue: 0.55), dusk: Color(red: 0.98, green: 0.60, blue: 0.45),
                  hillFar: Color(red: 0.93, green: 0.65, blue: 0.48), hillNear: Color(red: 0.78, green: 0.45, blue: 0.36),
                  ground: Color(red: 0.55, green: 0.30, blue: 0.27)),
    ]
}

// MARK: - Easing

private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
private func phase(_ t: Double, _ start: Double, _ end: Double) -> Double { clamp((t - start) / (end - start)) }
private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
private func easeOutBack(_ x: Double) -> Double {
    let c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
}

private struct Hills: Shape {
    var offset: Double
    var amplitude: Double
    var wavelength: Double
    var baseline: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        var x: Double = 0
        while x <= rect.width {
            let y = baseline + amplitude * sin((x + offset) / wavelength * 2 * .pi)
            path.addLine(to: CGPoint(x: x, y: y))
            x += 6
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Scene

struct RamReelScene: View {
    let data: RamReelData
    let time: Double

    private var t: Double { min(max(time, 0), RamReelSpec.duration) }

    private var theme: ReelTheme { ReelTheme.all[data.variant % ReelTheme.all.count] }

    private var frameName: String {
        let frames = RamSpriteFrameSets.gallopRunningStride
        let index = Int(t / 0.07) % max(frames.count, 1)
        return frames[index]
    }

    var body: some View {
        ZStack {
            background
            hills
            mapLayer
            content
            storyBar
        }
        .frame(width: RamReelSpec.size.width, height: RamReelSpec.size.height)
        .clipped()
    }

    // MARK: Layers

    private var background: some View {
        // Flat colour that warms toward dusk as the reel goes on.
        ZStack {
            // Warms toward dusk as the reel goes on, lit from the top.
            let base = mix(theme.sky, theme.dusk, phase(t, 6.4, 8.4))
            Rectangle().fill(LinearGradient(colors: [mix(base, .white, 0.35), base],
                                            startPoint: .top, endPoint: .bottom))
            clouds
        }
    }

    private var clouds: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let speed = 8.0 + Double(i) * 5
                let span = 520.0
                let x = (Double(i) * 190 - t * speed).truncatingRemainder(dividingBy: span)
                Capsule()
                    .fill(.white.opacity(0.5))
                    .frame(width: 110 + Double(i) * 30, height: 30 + Double(i) * 6)
                    .position(x: x < -80 ? x + span : x, y: 120 + Double(i) * 70)
            }
        }
        .opacity(1 - phase(t, 7.2, 8.4) * 0.6)
    }

    private func mix(_ a: Color, _ b: Color, _ f: Double) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(a).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(b).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(red: r1 + (r2 - r1) * f, green: g1 + (g2 - g1) * f, blue: b1 + (b2 - b1) * f)
    }

    private var mapAlpha: Double {
        guard data.map != nil else { return 0 }
        return phase(t, 2.0, 2.8) * (1 - phase(t, 7.2, 7.8))
    }

    private var hills: some View {
        let speed = 26.0 + 70.0 * easeOut(phase(t, 0.4, 2.4))
        let scroll = t * speed
        return ZStack {
            Hills(offset: scroll * 0.35, amplitude: 22, wavelength: 300, baseline: 470)
                .fill(theme.hillFar)
            Hills(offset: scroll * 0.7, amplitude: 16, wavelength: 210, baseline: 520)
                .fill(theme.hillNear)
            Rectangle()
                .fill(theme.ground)
                .frame(height: 96)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .opacity(1 - mapAlpha)
    }

    // MARK: Map beat

    @ViewBuilder private var mapLayer: some View {
        if let map = data.map, mapAlpha > 0 {
            let progress = easeOut(phase(t, 2.8, 7.2) * 0.9 + phase(t, 2.8, 7.2) * 0.1)
            let route = routePath(map.points)
            ZStack {
                Image(uiImage: map.image)
                    .resizable()
                    .frame(width: 360, height: 640)

                route.trimmedPath(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                route.trimmedPath(from: 0, to: progress)
                    .stroke(ReelPalette.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

                ForEach(Array(map.pins.enumerated()), id: \.element.id) { index, pin in
                    pinView(pin, index: index, progress: progress)
                }

                marker(at: map.point(at: progress))
            }
            .frame(width: 360, height: 640)
            .scaleEffect(1 + 0.06 * phase(t, 2.0, 7.6))
            .opacity(mapAlpha)
        }
    }

    private func routePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func pinView(_ pin: RamReelMap.Pin, index: Int, progress: Double) -> some View {
        let appear = clamp((progress - pin.fraction) / 0.07 + (pin.fraction == 0 ? 1 : 0))
        let pop = easeOutBack(appear)
        let above = index % 2 == 0
        return ZStack {
            Circle().fill(.white).frame(width: 16, height: 16)
            Circle().fill(ReelPalette.orange).frame(width: 9, height: 9)
            Text(pin.name)
                .scaledFont(size: 12, weight: .heavy, design: .rounded)
                .foregroundStyle(ReelPalette.ink)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.white, in: Capsule())
                .offset(y: above ? -22 : 22)
        }
        .scaleEffect(max(0.001, pop))
        .opacity(appear > 0 ? 1 : 0)
        .position(x: min(max(pin.point.x, 60), 300), y: pin.point.y)
    }

    private func marker(at point: CGPoint) -> some View {
        Group {
            if RamSpriteFrameSets.assetExists(frameName) {
                Image(frameName).resizable().scaledToFit()
            } else {
                Image(systemName: "hare.fill").resizable().scaledToFit().foregroundStyle(ReelPalette.ink)
            }
        }
        .frame(width: 84, height: 66)
        .position(x: point.x, y: point.y - 26)
    }

    private var storyBar: some View {
        VStack {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    let start = [0.0, 2.4, 7.6, 10.6][index]
                    let end = [2.4, 7.6, 10.6, 14.0][index]
                    ZStack(alignment: .leading) {
                        Capsule().fill(ReelPalette.ink.opacity(0.18))
                        Capsule().fill(ReelPalette.ink.opacity(0.7))
                            .scaleEffect(x: max(0.001, phase(t, start, end)), y: 1, anchor: .leading)
                    }
                    .frame(height: 3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            Spacer()
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        ZStack {
            intro
            odometer
            reveal
            endCard
            ram
        }
    }

    private var ram: some View {
        // Runs in from the left, holds the middle, then hops off during the reveal.
        let runIn = easeOut(phase(t, 0, 1.6))
        let exit = easeOut(phase(t, 7.2, 8.2))
        let x = -200 + 380 * runIn + 260 * exit
        let bob = sin(t * 14) * 3
        return Group {
            if RamSpriteFrameSets.assetExists(frameName) {
                Image(frameName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "hare.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(ReelPalette.ink)
            }
        }
        .frame(width: 190, height: 150)
        .offset(x: x - 20, y: 218 + bob)
        .opacity(ramOpacity)
    }

    private var ramOpacity: Double {
        guard data.map != nil else { return t < 8.4 ? 1 : 0 }
        if t < 2.6 { return 1 - phase(t, 2.2, 2.6) }
        if t > 7.4 && t < 8.4 { return phase(t, 7.4, 7.8) }
        return 0
    }

    private var intro: some View {
        let pop = easeOutBack(phase(t, 0.3, 1.1))
        let fade = 1 - phase(t, 2.0, 2.6)
        let headerText: String = {
            if data.goal != nil {
                return data.goalDone
                    ? String(localized: "Mission complete", bundle: .appLanguage, locale: .appLanguage)
                    : String(localized: "On a mission", bundle: .appLanguage, locale: .appLanguage)
            } else {
                return data.voice?.name ?? String(localized: "Meet", bundle: .appLanguage, locale: .appLanguage)
            }
        }()
        return VStack(spacing: 6) {
            Text(headerText)
                .scaledFont(size: 15, weight: .semibold, design: .rounded)
                .foregroundStyle(ReelPalette.ink.opacity(0.6))
            Text(data.ramName)
                .scaledFont(size: 64, weight: .black, design: .rounded)
                .foregroundStyle(ReelPalette.ink)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .scaleEffect(max(0.01, pop))
            Text(data.goal.map { "“\($0)”" } ?? data.intro)
                .lineLimit(data.goal == nil ? 3 : 4)
                .minimumScaleFactor(0.7)
                .scaledFont(size: 18, weight: .semibold, design: .serif)
                .italic()
                .foregroundStyle(ReelPalette.ink.opacity(0.75))
                .multilineTextAlignment(.center)
                .opacity(phase(t, 1.0, 1.6))
        }
        .padding(.horizontal, 24)
        .offset(y: -150)
        .opacity(fade)
    }

    private var odometer: some View {
        let appear = phase(t, 2.4, 3.0)
        let count = easeOut(phase(t, 2.6, 5.6))
        let meters = Int(Double(data.totalMeters) * count)
        let factChars = Int(Double(data.comparison.count) * phase(t, 5.2, 7.0))
        let fade = 1 - phase(t, 7.2, 7.8)
        return VStack(spacing: 10) {
            Text(DistanceFormatter.string(forMeters: meters))
                .scaledFont(size: 60, weight: .black, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(ReelPalette.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(String(localized: "walked on four hooves", bundle: .appLanguage, locale: .appLanguage))
                .scaledFont(size: 16, weight: .semibold, design: .rounded)
                .foregroundStyle(ReelPalette.ink.opacity(0.7))
            Text(String(data.comparison.prefix(factChars)))
                .scaledFont(size: 19, weight: .semibold, design: .serif)
                .italic()
                .foregroundStyle(ReelPalette.ink)
                .multilineTextAlignment(.center)
                .frame(minHeight: 90, alignment: .top)
                .padding(.horizontal, 28)
        }
        .padding(.vertical, data.map == nil ? 0 : 12)
        .background(data.map == nil ? Color.clear : Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, data.map == nil ? 0 : 14)
        .offset(y: data.map == nil ? -120 : -212)
        .opacity(appear * fade)
    }

    /// The stamp lands, then the personality is simply written across the
    /// scene: an eyebrow, the title, the tagline. No card, no icon badge.
    private var reveal: some View {
        let personality = data.personality
        let slam = phase(t, 7.6, 8.1)
        let slamScale = 2.6 - 1.6 * easeOutBack(slam)
        let eyebrow = easeOut(phase(t, 8.5, 9.0))
        let title = easeOut(phase(t, 8.7, 9.5))
        let tagline = easeOut(phase(t, 9.3, 10.0))
        let fade = 1 - phase(t, 10.3, 10.9)
        return VStack(spacing: 28) {
            if let stamp = data.latestStamp {
                InkStampView(stamp: stamp)
                    .scaleEffect(slamScale)
                    .opacity(slam)
                    .shadow(color: .black.opacity(0.12 * slam), radius: 4, y: 3)
            }

            VStack(spacing: 8) {
                Text(String(localized: "This ram is", bundle: .appLanguage, locale: .appLanguage))
                    .scaledFont(size: 15, weight: .semibold, design: .rounded)
                    .foregroundStyle(ReelPalette.ink.opacity(0.6))
                    .opacity(eyebrow)
                Text(personality.title)
                    .scaledFont(size: 44, weight: .black, design: .rounded)
                    .foregroundStyle(ReelPalette.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .offset(y: 16 * (1 - title))
                    .opacity(title)
                Text(personality.tagline)
                    .scaledFont(size: 18, weight: .medium, design: .serif)
                    .italic()
                    .foregroundStyle(ReelPalette.ink.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .offset(y: 10 * (1 - tagline))
                    .opacity(tagline)
            }
            .padding(.horizontal, 32)
        }
        .offset(y: -70)
        .opacity(t >= 7.6 ? fade : 0)
    }

    /// The app's real icon, HIG-rounded to match how it sits on the Home
    /// Screen. Falls back to a tinted glyph only if the icon can't be read
    /// (e.g. a stripped preview target) — the end card never ships without
    /// something recognizable there.
    private var appIcon: some View {
        Group {
            if let icon = Bundle.main.appIconImage {
                Image(uiImage: icon).resizable()
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ReelPalette.orange.gradient)
                    .overlay {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ReelPalette.ink.opacity(0.08), lineWidth: 1)
        }
    }

    /// Type on the scene, and the app icon + Apple's own "download" mark at
    /// the bottom, on the last page. The numbers are the picture; the
    /// closing mark is what turns a proud parent's replay into an install.
    private var endCard: some View {
        let appear = easeOut(phase(t, 10.6, 11.4))
        let detail = easeOut(phase(t, 11.2, 12.0))
        let mark = easeOut(phase(t, 11.8, 12.6))
        let places = Set(data.places.map { $0.lowercased() }).count
        let placesText = places == 1
            ? String(localized: "1 place", bundle: .appLanguage, locale: .appLanguage)
            : String(localized: "\(places) places", bundle: .appLanguage, locale: .appLanguage)
        let stats = String(localized: "\(placesText) · \(data.personality.title)", bundle: .appLanguage, locale: .appLanguage)
        return ZStack {
            VStack(spacing: 6) {
                Text(data.ramName)
                    .scaledFont(size: 24, weight: .bold, design: .rounded)
                    .foregroundStyle(ReelPalette.ink.opacity(0.7))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(DistanceFormatter.string(forMeters: data.totalMeters))
                    .scaledFont(size: 72, weight: .black, design: .rounded)
                    .foregroundStyle(ReelPalette.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(String(localized: "on foot, one step at a time", bundle: .appLanguage, locale: .appLanguage))
                    .scaledFont(size: 17, weight: .semibold, design: .serif)
                    .italic()
                    .foregroundStyle(ReelPalette.ink.opacity(0.75))
                Text(stats)
                    .scaledFont(size: 15, weight: .semibold, design: .rounded)
                    .foregroundStyle(ReelPalette.ink.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 14)
                    .opacity(detail)
                Text(data.closer)
                    .scaledFont(size: 14, weight: .medium, design: .serif)
                    .italic()
                    .foregroundStyle(ReelPalette.ink.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 36)
                    .padding(.top, 4)
                    .opacity(detail)
            }
            .offset(y: -30)
            .opacity(appear)

            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    appIcon
                    Text("Baranov")
                        .scaledFont(size: 15, weight: .heavy, design: .rounded)
                        .foregroundStyle(ReelPalette.ink)
                }
                AppStoreBadge()
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 34)
            .opacity(mark)
        }
    }

}
