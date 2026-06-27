// App/Dashboard/Panes/HistoryPaneView.swift
//
// The History pane — reuses the existing, crash-fixed `HistoryView` (P9) inside the
// dashboard's detail column. We deliberately reuse rather than reimplement so the
// macOS-26 List/diffRows crash fix (see HistoryView header) is preserved.
//
// The pane owns the `HistoryViewModel` lifetime via `@State` so the list survives
// section switches within a single dashboard window.

import SpeakCore
import SwiftUI

// MARK: - HistoryPaneView

struct HistoryPaneView: View {
    let context: DashboardContext

    @State private var viewModel: HistoryViewModel

    init(context: DashboardContext) {
        self.context = context
        _viewModel = State(initialValue: HistoryViewModel(store: context.historyStore))
    }

    var body: some View {
        HistoryView(viewModel: viewModel)
    }
}
