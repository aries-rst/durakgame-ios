import Foundation
import SwiftUI
import UIKit
import GoogleMobileAds
import AppTrackingTransparency

// Google AdMob for the free tier: a banner, an interstitial between finished
// games (every 2nd game, at most once a minute), and a rewarded ad that
// unlocks a hint. Premium owners (StoreManager persists `isPremium` in
// UserDefaults) never see ads and get hints instantly.
//
// AdMob App ID (Info.plist `GADApplicationIdentifier`): ca-app-pub-9638598348702189~7781925624
enum AdUnitIds {
    static let banner = "ca-app-pub-9638598348702189/1847072660"
    static let interstitial = "ca-app-pub-9638598348702189/2468008861"
    static let rewarded = "ca-app-pub-9638598348702189/2202742997"
}

@MainActor
final class AdsState: ObservableObject {
    static let shared = AdsState()
    @Published var ready = false
}

@MainActor
enum Ads {
    static var isPremium: Bool { UserDefaults.standard.bool(forKey: "isPremium") }

    private static var startRequested = false
    private static var interstitial: InterstitialAd?
    private static var rewarded: RewardedAd?
    private static var loadingInterstitial = false
    private static var loadingRewarded = false
    private static var interstitialDelegate: AdDismissDelegate?
    private static var rewardedDelegate: AdDismissDelegate?
    private static var gamesSinceAd = 0
    private static var lastFullScreenAd = Date.distantPast

    /// Call from the root view's `.onAppear`. Asks for App Tracking
    /// Transparency once the UI is on screen, then starts the SDK.
    static func start() {
        guard !startRequested, !isPremium else { return }
        startRequested = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ATTrackingManager.requestTrackingAuthorization { _ in
                DispatchQueue.main.async { startSDK() }
            }
        }
    }

    private static func startSDK() {
        MobileAds.shared.start { _ in
            Task { @MainActor in
                AdsState.shared.ready = true
                preloadInterstitial()
                preloadRewarded()
            }
        }
    }

    // MARK: Interstitial

    static func preloadInterstitial() {
        guard AdsState.shared.ready, !isPremium, interstitial == nil, !loadingInterstitial else { return }
        loadingInterstitial = true
        Task { @MainActor in
            interstitial = try? await InterstitialAd.load(with: AdUnitIds.interstitial, request: GoogleMobileAds.Request())
            loadingInterstitial = false
        }
    }

    /// Call when the player leaves a finished game ("play again" / "menu").
    /// Shows an interstitial every 2nd finished game (and never more than once
    /// a minute); `then` always runs exactly once, after the ad is closed.
    static func afterGame(then: @escaping () -> Void) {
        gamesSinceAd += 1
        guard !isPremium, gamesSinceAd >= 2,
              Date().timeIntervalSince(lastFullScreenAd) > 60,
              let ad = interstitial, let vc = topViewController() else {
            then()
            preloadInterstitial()
            return
        }
        interstitial = nil
        gamesSinceAd = 0
        lastFullScreenAd = Date()
        let d = AdDismissDelegate { then(); preloadInterstitial() }
        interstitialDelegate = d
        ad.fullScreenContentDelegate = d
        ad.present(from: vc)
    }

    // MARK: Rewarded (hint)

    static func preloadRewarded() {
        guard AdsState.shared.ready, !isPremium, rewarded == nil, !loadingRewarded else { return }
        loadingRewarded = true
        Task { @MainActor in
            rewarded = try? await RewardedAd.load(with: AdUnitIds.rewarded, request: GoogleMobileAds.Request())
            loadingRewarded = false
        }
    }

    /// Hint behind a rewarded ad. Premium owners — and anyone when no ad is
    /// available — get the hint instantly, so the player is never blocked.
    static func rewardedHint(_ grant: @escaping () -> Void) {
        guard !isPremium, let ad = rewarded, let vc = topViewController() else {
            grant()
            preloadRewarded()
            return
        }
        rewarded = nil
        lastFullScreenAd = Date()
        var earned = false
        let d = AdDismissDelegate {
            if earned { grant() }
            preloadRewarded()
        }
        rewardedDelegate = d
        ad.fullScreenContentDelegate = d
        ad.present(from: vc) { earned = true }
    }

    static func topViewController() -> UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

private final class AdDismissDelegate: NSObject, FullScreenContentDelegate {
    private var fired = false
    private let onDone: () -> Void
    init(_ onDone: @escaping () -> Void) { self.onDone = onDone }
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) { fire() }
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) { fire() }
    private func fire() {
        guard !fired else { return }
        fired = true
        DispatchQueue.main.async { self.onDone() }
    }
}
