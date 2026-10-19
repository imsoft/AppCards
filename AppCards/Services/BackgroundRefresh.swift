import Foundation
import BackgroundTasks
import SwiftData

/// Programa el refresco diario con BGAppRefreshTask. iOS decide la hora exacta; suele correr una vez al día si usas la app seguido.
enum BackgroundRefresh {
    static func register(container: ModelContainer, model: AppModel) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: PriceRefreshService.backgroundTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            schedule()
            let work = Task { @MainActor in
                let service = PriceRefreshService(model: model, context: container.mainContext)
                await service.runDaily()
                refreshTask.setTaskCompleted(success: true)
            }
            refreshTask.expirationHandler = {
                work.cancel()
                refreshTask.setTaskCompleted(success: false)
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: PriceRefreshService.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
