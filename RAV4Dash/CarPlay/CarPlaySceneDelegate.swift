import CarPlay
import SwiftUI
import UIKit

/// CarPlay version built from Apple's standard screens (driving task category):
/// a Gauges grid, a Live Data list and a Trouble Codes page, plus pop-up warnings.
/// Layout editing happens on the iPhone; CarPlay shows the first 8 tiles of the current layout.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var gridTemplate: CPGridTemplate?
    private var listTemplate: CPListTemplate?
    private var codesTemplate: CPInformationTemplate?
    private var listItems: [MetricID: CPListItem] = [:]
    private var listMetrics: [MetricID] = []
    private var refreshTask: Task<Void, Never>?
    private var lastAlertID: UUID?
    private var lastCodes: DTCReport?

    private var model: AppModel { AppModel.shared }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        let grid = CPGridTemplate(title: "Gauges", gridButtons: makeGridButtons())
        grid.tabTitle = "Gauges"
        grid.tabImage = UIImage(systemName: "gauge.with.dots.needle.67percent")
        gridTemplate = grid

        let list = CPListTemplate(title: "Live Data", sections: makeListSections())
        list.tabTitle = "Live Data"
        list.tabImage = UIImage(systemName: "list.bullet")
        listTemplate = list

        let codes = CPInformationTemplate(title: "Trouble Codes", layout: .twoColumn,
                                          items: makeCodeItems(), actions: makeCodeActions())
        codes.tabTitle = "Codes"
        codes.tabImage = UIImage(systemName: "stethoscope")
        codesTemplate = codes

        let tabs = CPTabBarTemplate(templates: [grid, list, codes])
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)

        if model.source == .obd { model.refreshCodes() }
        startRefreshing()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        refreshTask?.cancel()
        refreshTask = nil
        self.interfaceController = nil
        gridTemplate = nil
        listTemplate = nil
        codesTemplate = nil
        listItems = [:]
    }

    // MARK: - Refresh (about once a second)

    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                self.refresh()
            }
        }
    }

    private func refresh() {
        gridTemplate?.updateGridButtons(makeGridButtons())

        let metrics = listMetricIDs()
        if metrics != listMetrics {
            listTemplate?.updateSections(makeListSections())
        } else {
            for id in metrics {
                guard let item = listItems[id] else { continue }
                item.setDetailText(detailText(for: id))
                item.setImage(CarPlayImages.listIcon(metric: id, value: model.values[id]))
            }
        }

        if model.codes != lastCodes {
            lastCodes = model.codes
            codesTemplate?.items = makeCodeItems()
        }

        if let alert = model.latestAlert, alert.id != lastAlertID {
            lastAlertID = alert.id
            presentAlert(alert)
        }
    }

    // MARK: - Gauges grid

    private func makeGridButtons() -> [CPGridButton] {
        let tiles = Array(model.currentLayout.tiles.prefix(8))
        return tiles.map { tile in
            let image = CarPlayImages.gauge(metric: tile.metric,
                                            value: model.values[tile.metric],
                                            alerting: model.activeAlerts.contains(tile.metric))
            return CPGridButton(titleVariants: [tile.metric.info.name], image: image) { [weak self] _ in
                self?.showDetail(for: tile.metric)
            }
        }
    }

    private func showDetail(for metric: MetricID) {
        let info = metric.info
        let points = model.history[metric] ?? []
        var items = [
            CPInformationItem(title: "Now", detail: "\(info.format(model.values[metric])) \(info.unit)")
        ]
        if let lo = points.min(), let hi = points.max() {
            items.append(CPInformationItem(title: "Low", detail: "\(info.format(lo)) \(info.unit)"))
            items.append(CPInformationItem(title: "High", detail: "\(info.format(hi)) \(info.unit)"))
        }
        items.append(CPInformationItem(title: "About", detail: info.detail))
        let template = CPInformationTemplate(title: info.name, layout: .leading, items: items, actions: [])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    // MARK: - Live data list

    private func listMetricIDs() -> [MetricID] {
        var seen = Set<MetricID>()
        return model.currentLayout.tiles.map(\.metric).filter { seen.insert($0).inserted }
    }

    private func makeListSections() -> [CPListSection] {
        listMetrics = listMetricIDs()
        listItems = [:]
        let items: [CPListItem] = listMetrics.map { id in
            let item = CPListItem(text: id.info.name,
                                  detailText: detailText(for: id),
                                  image: CarPlayImages.listIcon(metric: id, value: model.values[id]))
            item.handler = { [weak self] _, completion in
                self?.showDetail(for: id)
                completion()
            }
            listItems[id] = item
            return item
        }
        return [CPListSection(items: items)]
    }

    private func detailText(for id: MetricID) -> String {
        let info = id.info
        let value = info.format(model.values[id])
        return info.unit.isEmpty ? value : "\(value) \(info.unit)"
    }

    // MARK: - Trouble codes

    private func makeCodeItems() -> [CPInformationItem] {
        guard model.source != .none else {
            return [CPInformationItem(title: "Status", detail: "Connect the adapter on your iPhone")]
        }
        guard let codes = model.codes else {
            return [CPInformationItem(title: "Status", detail: "Reading codes…")]
        }
        var items = [
            CPInformationItem(title: "Check engine light", detail: codes.milOn ? "On" : "Off"),
            CPInformationItem(title: "Stored codes", detail: codes.stored.isEmpty ? "None" : codes.stored.joined(separator: ", ")),
            CPInformationItem(title: "Pending codes", detail: codes.pending.isEmpty ? "None" : codes.pending.joined(separator: ", ")),
            CPInformationItem(title: "Last scan", detail: codes.date.formatted(date: .omitted, time: .shortened))
        ]
        if model.source == .demo {
            items.append(CPInformationItem(title: "Note", detail: "Demo mode"))
        }
        return items
    }

    private func makeCodeActions() -> [CPTextButton] {
        let rescan = CPTextButton(title: "Re-scan", textStyle: .normal) { [weak self] _ in
            self?.model.refreshCodes()
        }
        let clear = CPTextButton(title: "Clear Codes", textStyle: .cancel) { [weak self] _ in
            self?.confirmClear()
        }
        return [rescan, clear]
    }

    private func confirmClear() {
        let clear = CPAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            self?.model.clearCodes()
            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        }
        let cancel = CPAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(titleVariants: ["Clear all trouble codes?"], actions: [clear, cancel])
        interfaceController?.presentTemplate(alert, animated: true, completion: nil)
    }

    // MARK: - Warnings

    private func presentAlert(_ event: AlertEvent) {
        guard let controller = interfaceController, controller.presentedTemplate == nil else { return }
        let dismiss = CPAlertAction(title: "Dismiss", style: .cancel) { [weak self] _ in
            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(titleVariants: [event.message], actions: [dismiss])
        controller.presentTemplate(alert, animated: true, completion: nil)
    }
}
