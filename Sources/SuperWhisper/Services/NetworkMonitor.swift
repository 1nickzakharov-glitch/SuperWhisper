import Foundation
import Network
import Combine

@MainActor
public final class NetworkMonitor: ObservableObject {
    public static let shared = NetworkMonitor()
    
    @Published public private(set) var isConnected: Bool = true
    @Published public private(set) var isExpensive: Bool = false
    
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "SuperWhisper.NetworkMonitor", qos: .utility)
    
    private init() {
        self.monitor = NWPathMonitor()
        
        self.monitor.pathUpdateHandler = { [weak self] path in
            let status = (path.status == .satisfied)
            let expensive = path.isExpensive
            Task { @MainActor in
                self?.isConnected = status
                self?.isExpensive = expensive
            }
        }
        
        self.monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}
