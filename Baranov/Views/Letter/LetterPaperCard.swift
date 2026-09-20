//
//  LetterPaperCard.swift
//  Baranov
//
//  What the recipient finds once the seal is broken: the letter itself on
//  the paper the sender chose, and — on its own material card, so the
//  stamps stay legible whatever colour the paper is — the journey
//  passport with the road told in a few sentences when the phone has an
//  on-device model.
//

import SwiftUI
import UIKit

struct LetterPaperCard: View {
    let letter: Letter
    let ram: Ram
    let paper: PaperStyle

    @State private var muse = LetterMuseService()
    @State private var roadNarration: String?

    var body: some View {
        VStack(spacing: 16) {
            letterSheet
            passport
        }
    }

    // MARK: Letter

    private var letterSheet: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("From \(letter.senderName)")
                    .font(.system(.headline, design: .serif))
                Text("To \(letter.recipientName)")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(paper.ink.opacity(0.65))
            }

            Text(letter.messageBody)
                .font(.system(.body, design: .serif))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let data = letter.revealedAttachment, let photo = UIImage(data: data) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Drawing attached to the letter")
            }
        }
        .foregroundStyle(paper.ink)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                paper.color
                PaperGrain()
            }
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 7)
        .shadow(color: .black.opacity(0.1), radius: 1.5, x: 0, y: 1)
    }

    // MARK: Passport

    private var passport: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Journey Passport")
                .font(.headline)

            if let roadNarration {
                Text(roadNarration)
                    .font(.system(.subheadline, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                Divider()
            } else if muse.isThinking {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Reading the stamps…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            PassportStampGrid(stamps: ram.stamps, ramName: ram.name)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            guard roadNarration == nil else { return }
            if let story = await muse.narrate(ram: ram, stamps: ram.stamps) {
                withAnimation(.easeInOut(duration: 0.3)) { roadNarration = story }
            }
        }
    }
}
