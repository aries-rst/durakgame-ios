import Foundation
import MultipeerConnectivity
import UIKit

final class MultiplayerManager: NSObject, ObservableObject {
    enum Role { case none; case host; case guest }
    enum ConnectionState: Equatable {
        case idle, hosting, browsing, connecting
        case connected(peerName: String)
    }
    @Published var state: ConnectionState = .idle
    @Published var role: Role = .none
    @Published var availablePeers: [MCPeerID] = []
    @Published var errorMessage: String? = nil
    var onReceive: ((Data) -> Void)?
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
    func startHosting() { role = .host; state = .hosting; let a = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType); a.delegate = self; a.startAdvertisingPeer(); advertiser = a }
    func startBrowsing() { role = .guest; state = .browsing; availablePeers = []; let b = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType); b.delegate = self; b.startBrowsingForPeers(); browser = b }
    func invite(_ peer: MCPeerID) { state = .connecting; browser?.invitePeer(peer, to: session, withContext: nil, timeout: 20) }
    func stop() { advertiser?.stopAdvertisingPeer(); advertiser = nil; browser?.stopBrowsingForPeers(); browser = nil; session.disconnect(); state = .idle; role = .none; availablePeers = [] }
    func send<T: Encodable>(_ payload: T) {
        guard !session.connectedPeers.isEmpty else { return }
        do { let data = try JSONEncoder().encode(payload); try session.send(data, toPeers: session.connectedPeers, with: .reliable) }
        catch { errorMessage = error.localizedDescription }
    }
}
extension MultiplayerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange sessionState: MCSessionState) {
        DispatchQueue.main.async {
            switch sessionState {
            case .connected:
                self.state = .connected(peerName: peerID.displayName)
                self.advertiser?.stopAdvertisingPeer(); self.browser?.stopBrowsingForPeers()
                self.onStateChange?(true)
            case .connecting: self.state = .connecting
            case .notConnected:
                let wasConnected = (self.state == .connected(peerName: peerID.displayName))
                self.state = self.role == .host ? .hosting : .browsing
                if wasConnected { self.onStateChange?(false) }
            @unknown default: break
            }
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) { DispatchQueue.main.async { self.onReceive?(data) } }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
extension MultiplayerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) { invitationHandler(true, session) }
}
extension MultiplayerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) { DispatchQueue.main.async { if !self.availablePeers.contains(peerID) { self.availablePeers.append(peerID) } } }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) { DispatchQueue.main.async { self.availablePeers.removeAll { $0 == peerID } } }
}
