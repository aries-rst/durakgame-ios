import SwiftUI
import GoogleMobileAds
import UIKit

/// Standard 320×50 banner for the free tier. Renders nothing until the SDK
/// has started, and never for Premium owners.
struct BannerAdView: View {
    @ObservedObject private var state = AdsState.shared

    var body: some View {
        if state.ready && !Ads.isPremium {
            BannerContainer().frame(width: 320, height: 50)
        }
    }
}

private struct BannerContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = AdUnitIds.banner
        banner.rootViewController = Ads.topViewController()
        banner.load(GoogleMobileAds.Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
