import Foundation
import MultipeerConnectivity
import UIKit

/// Shared local multiplayer transport (Wi-Fi/Bluetooth via MultipeerConnectivity).
/// Identical across all games in this portfolio -- only the `serviceType`
/// passed at init differs per game. One side hosts (advertises), the other
/// browses and invites; once connected, both sides just exchange small
/// Codable payloads describing game moves through `send`/`onReceive`.
///
/// `session.connectedPeers` already supports more than one simultaneous
/// guest — nothing here ever filters it down to one. The only thing that
/// used to cap a host at a single guest was `startHosting()` stopping the
/// advertiser the instant the *first* peer connected; that is now gated to
/// the guest side only (a guest should stop browsing once connected to its
/// one host), so a host keeps advertising — and keeps accepting more
/// invitations — until it explicitly calls `stopHostDiscovery()`.
final class MultiplayerManager: NSObject, ObservableObject {
enum Role {
case none
case host
case guest
}

enum ConnectionState: Equatable {
case idle
case hosting
case browsing
case connecting
case connected(peerName: String)
}

@Published var state: ConnectionState = .idle
@Published var role: Role = .none
@Published var availablePeers: [MCPeerID] = []
@Published var errorMessage: String? = nil

/// Host side: every peer currently connected to this session, in the
/// order they connected — seat 1, 2, 3, 4, 5 (seat 0 is always the host)
/// are assigned from this order.
@Published private(set) var connectedPeers: [MCPeerID] = []

/// Guest side: the `discoveryInfo` dictionary each found host advertised
/// (host nickname / variant / target player count), keyed by peer, so the
/// browse screen can show a real game card instead of a bare device name.
@Published private(set) var discoveredGames: [MCPeerID: [String: String]] = [:]

/// Called on the main thread whenever a full message arrives from any
/// connected peer.
var onReceive: ((Data) -> Void)?
/// Called with `true` right after a peer connects, `false` on disconnect.
var onStateChange: ((Bool) -> Void)?

private let serviceType: String
private let myPeerId: MCPeerID
private var session: MCSession!
private var advertiser: MCNearbyServiceAdvertiser?
private var browser: MCNearbyServiceBrowser?

init(serviceType: String) {
self.serviceType = serviceType
self.myPeerId = MCPeerID(displayName: UIDevice.current.name)
super.init()
session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
session.delegate = self
}

/// This device's own display name, as it will appear to peers — used to
/// resolve "which seat am I" out of a broadcast seat-name list.
var myDisplayName: String { myPeerId.displayName }

/// - Parameter info: broadcast via `discoveryInfo` so browsing peers can
///   show a real game card (host name / variant / player count) instead of
///   a bare device name. `discoveryInfo` is static for the lifetime of one
///   `startAdvertisingPeer()` call, so "seats filled so far" won't live-update
///   unless advertising is restarted — callers can live with host+variant+
///   target-count as the minimum info shown.
func startHosting(info: [String: String] = [:]) {
role = .host
state = .hosting
connectedPeers = []
let advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: info, serviceType: serviceType)
advertiser.delegate = self
advertiser.startAdvertisingPeer()
self.advertiser = advertiser
}

func startBrowsing() {
role = .guest
state = .browsing
availablePeers = []
discoveredGames = [:]
let browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
browser.delegate = self
browser.startBrowsingForPeers()
self.browser = browser
}

func invite(_ peer: MCPeerID) {
state = .connecting
browser?.invitePeer(peer, to: session, withContext: nil, timeout: 20)
}

/// Host only: stop accepting new invitations (e.g. once the room is full
/// and the match has started) without disconnecting guests already in the
/// session.
func stopHostDiscovery() {
advertiser?.stopAdvertisingPeer()
advertiser = nil
}

func stop() {
advertiser?.stopAdvertisingPeer()
advertiser = nil
browser?.stopBrowsingForPeers()
browser = nil
session.disconnect()
state = .idle
role = .none
availablePeers = []
discoveredGames = [:]
connectedPeers = []
}

func send<T: Encodable>(_ payload: T) {
guard !session.connectedPeers.isEmpty else { return }
do {
let data = try JSONEncoder().encode(payload)
try session.send(data, toPeers: session.connectedPeers, with: .reliable)
} catch {
errorMessage = error.localizedDescription
}
}
}

extension MultiplayerManager: MCSessionDelegate {
func session(_ session: MCSession, peer peerID: MCPeerID, didChange sessionState: MCSessionState) {
DispatchQueue.main.async {
switch sessionState {
case .connected:
self.state = .connected(peerName: peerID.displayName)
if !self.connectedPeers.contains(peerID) {
self.connectedPeers.append(peerID)
}
// Only a guest (always exactly one host) should stop browsing once
// connected; a host keeps advertising so more guests can still join
// until it explicitly calls `stopHostDiscovery()`.
if self.role == .guest {
self.browser?.stopBrowsingForPeers()
}
self.onStateChange?(true)
case .connecting:
self.state = .connecting
case .notConnected:
let wasConnected = self.connectedPeers.contains(peerID)
self.connectedPeers.removeAll { $0 == peerID }
self.state = self.role == .host ? .hosting : .browsing
if wasConnected {
self.onStateChange?(false)
}
@unknown default:
break
}
}
}

func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
DispatchQueue.main.async {
self.onReceive?(data)
}
}

func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultiplayerManager: MCNearbyServiceAdvertiserDelegate {
func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
invitationHandler(true, session)
}
}

extension MultiplayerManager: MCNearbyServiceBrowserDelegate {
func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
DispatchQueue.main.async {
if !self.availablePeers.contains(peerID) {
self.availablePeers.append(peerID)
}
self.discoveredGames[peerID] = info ?? [:]
}
}

func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
DispatchQueue.main.async {
self.availablePeers.removeAll { $0 == peerID }
self.discoveredGames.removeValue(forKey: peerID)
}
}
}
