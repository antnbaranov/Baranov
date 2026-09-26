//
//  AppStoreBadge.swift
//  Baranov
//
//  Apple's "Download on the App Store" mark. Apple's identity guidelines
//  require using their own artwork unmodified, so this shows the real badge
//  the moment it's dropped into Assets.xcassets as `AppStoreBadgeBlack`
//  (download it from https://developer.apple.com/app-store/marketing/guidelines/
//  — "Download on the App Store" badge, black, the localization that
//  matches this app's default language) — same "art drops in later, zero
//  code changes" pattern as the ram sprites and portrait placeholders
//  elsewhere in this project. Until that asset exists, this draws a
//  same-shaped stand-in from system materials only, so the reel never ships
//  a home-made copy of Apple's actual mark.
//

import SwiftUI

struct AppStoreBadge: View {
    private var hasOfficialArtwork: Bool { UIImage(named: "AppStoreBadgeBlack") != nil }

    var body: some View {
        Group {
            if hasOfficialArtwork {
                Image("AppStoreBadgeBlack")
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .frame(height: 44)
        .accessibilityLabel(Text("Download on the App Store"))
        .accessibilityAddTraits(.isImage)
    }

    private var placeholder: some View {
        HStack(spacing: 7) {
            Image(systemName: "apple.logo")
                .font(.system(size: 21, weight: .regular))
            VStack(alignment: .leading, spacing: 0) {
                Text("Download on the")
                    .font(.system(size: 9, weight: .regular))
                Text("App Store")
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
