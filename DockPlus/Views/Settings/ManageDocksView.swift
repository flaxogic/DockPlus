import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ManageDocksView: View {
    @ObservedObject var dockManager: DockManager
    @ObservedObject var viewModel: ManageDocksViewModel

    var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedDockID) {
                Section("Docks") {
                    ForEach(dockManager.docks) { dock in
                        HStack(spacing: 10) {
                            Image(systemName: dock.orientation == .horizontal ? "dock.rectangle" : "sidebar.left")
                                .font(.system(size: 14))
                                .foregroundStyle(dock.isVisible ? Color.accentColor : Color.secondary)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(dock.name)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                Text(itemCountLabel(for: dock))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                dockManager.toggleDockVisibility(id: dock.id)
                            } label: {
                                Image(systemName: dock.isVisible ? "eye" : "eye.slash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(dock.isVisible ? .secondary : .tertiary)
                            }
                            .buttonStyle(.borderless)
                            .help(dock.isVisible ? "Hide Dock" : "Show Dock")
                        }
                        .padding(.vertical, 3)
                        .tag(dock.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()

                    // Overall Manage Docks setting: choose which dock shows unpinned open apps
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Apps")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding<UUID?>(
                            get: { dockManager.config.openAppsDockID },
                            set: { dockManager.setOpenAppsDockID($0) }
                        )) {
                            Text("Don't Show").tag(UUID?.none)
                            ForEach(dockManager.docks) { dock in
                                Text(dock.name).tag(UUID?.some(dock.id))
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()

                    HStack(spacing: 6) {
                        Button {
                            let created = dockManager.addDock()
                            viewModel.selectedDockID = created.id
                        } label: {
                            Label("New Dock", systemImage: "plus")
                                .labelStyle(.iconOnly)
                                .frame(width: 24, height: 22)
                        }
                        .help("New Dock")

                        Button {
                            if let id = viewModel.selectedDockID {
                                dockManager.deleteDock(id: id)
                                viewModel.selectedDockID = dockManager.docks.first?.id
                            }
                        } label: {
                            Label("Delete Dock", systemImage: "minus")
                                .labelStyle(.iconOnly)
                                .frame(width: 24, height: 22)
                        }
                        .disabled(viewModel.selectedDockID == nil || dockManager.docks.count <= 1)
                        .help("Delete Dock")

                        Spacer()

                        Button {
                            dockManager.toggleMoveModeForAllDocks()
                        } label: {
                            Text(dockManager.isAnyDockMoving ? "Done Moving" : "Move Docks")
                                .font(.caption)
                        }
                        .controlSize(.small)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
            }
            .navigationSplitViewColumnWidth(min: 195, ideal: 215, max: 250)
        } detail: {
            if let id = viewModel.selectedDockID, let dock = dockManager.dock(for: id) {
                DockDetailView(dock: dock, dockManager: dockManager)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "dock.rectangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Select a Dock")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel.selectedDockID == nil || dockManager.dock(for: viewModel.selectedDockID!) == nil {
                viewModel.selectedDockID = dockManager.docks.first?.id
            }
        }
    }

    private func itemCountLabel(for dock: DockConfig) -> String {
        let count = dock.items.filter { $0.kind != .separator }.count
        if count == 0 { return "Empty" }
        return count == 1 ? "1 item" : "\(count) items"
    }
}

private struct DockDetailView: View {
    let dock: DockConfig
    @ObservedObject var dockManager: DockManager

    @State private var draggedItemID: UUID?

    private func update(_ mutate: (inout DockConfig) -> Void) {
        var copy = dock
        mutate(&copy)
        dockManager.updateDock(copy)
    }

    private var isMovingThisDock: Bool {
        dockManager.movingDockIDs.contains(dock.id)
    }

    var body: some View {
        Form {
            // Interactive items strip: drag left/right to reorder, hover to remove
            Section("Items") {
                VStack(alignment: .leading, spacing: 10) {
                    if dock.items.isEmpty {
                        Text("No pinned items yet. Drag apps onto \"\(dock.name)\" or click Add Items.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(dock.items) { item in
                                    RemovableDockChip(item: item) {
                                        dockManager.removeItem(itemID: item.id, from: dock.id)
                                    }
                                    .opacity(draggedItemID == item.id ? 0.35 : 1.0)
                                    .onDrag {
                                        draggedItemID = item.id
                                        return NSItemProvider(object: item.id.uuidString as NSString)
                                    }
                                    .onDrop(
                                        of: [UTType.text],
                                        delegate: DockChipDropDelegate(
                                            targetItem: item,
                                            dock: dock,
                                            dockManager: dockManager,
                                            draggedItemID: $draggedItemID
                                        )
                                    )
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                            .animation(.spring(response: 0.24, dampingFraction: 0.85), value: dock.items.map(\.id))
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            dockManager.presentAddItemsPanel(for: dock.id)
                        } label: {
                            Label("Add Items…", systemImage: "plus")
                        }

                        Button {
                            dockManager.addSeparator(to: dock.id)
                        } label: {
                            Label("Add Separator", systemImage: "minus")
                        }

                        Spacer()

                        if dockManager.lastRemovalUndo?.dockID == dock.id {
                            Button("Undo") {
                                dockManager.undoLastRemoval()
                            }
                        }
                    }
                }
            }

            Section {
                TextField("Name", text: Binding(
                    get: { dock.name },
                    set: { value in update { $0.name = value } }
                ))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Size")
                        Spacer()
                        Text("\(Int(dock.iconSize)) pt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Text("Small")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { dock.iconSize },
                                set: { value in update { $0.iconSize = round(value) } }
                            ),
                            in: DockConfig.minIconSize...DockConfig.maxIconSize,
                            step: 2
                        )
                        Text("Large")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Magnification", isOn: Binding(
                        get: { dock.magnificationEnabled },
                        set: { value in update { $0.magnificationEnabled = value } }
                    ))
                    if dock.magnificationEnabled {
                        HStack(spacing: 8) {
                            Text("Small")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(
                                value: Binding(
                                    get: { dock.magnificationScale },
                                    set: { value in update { $0.magnificationScale = value } }
                                ),
                                in: DockConfig.minMagnificationScale...DockConfig.maxMagnificationScale
                            )
                            Text("Large")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Appearance") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Transparency")
                        Spacer()
                        Text("\(Int(round(dock.glassTransparency * 100)))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        Text("Opaque")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(
                            value: Binding(
                                get: { dock.glassTransparency },
                                set: { value in update { $0.glassTransparency = value } }
                            ),
                            in: 0.0...1.0
                        )
                        Text("Clear")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DockTintColorRow(
                    tintColor: Binding(
                        get: { dock.tintColor },
                        set: { value in update { $0.tintColor = value } }
                    )
                )
            }

            Section("Position") {
                if dockManager.displayObserver.displays.count > 1 {
                    Picker("Display", selection: Binding<String?>(
                        get: { dock.placement.displayUUID },
                        set: { uuid in dockManager.assignDock(dock.id, toDisplayUUID: uuid) }
                    )) {
                        Text("Primary Display").tag(String?.none)
                        Divider()
                        ForEach(dockManager.displayObserver.displays) { display in
                            Text(display.isMain ? "\(display.name) (Primary)" : display.name)
                                .tag(String?.some(display.uuid))
                        }
                    }
                }

                HStack {
                    Picker("Snap to Edge", selection: Binding<DockConfig.Edge?>(
                        get: { dock.placement.snappedEdge },
                        set: { edge in dockManager.snapDock(dock.id, to: edge) }
                    )) {
                        Text("Bottom").tag(DockConfig.Edge?.some(.bottom))
                        Text("Top").tag(DockConfig.Edge?.some(.top))
                        Text("Left").tag(DockConfig.Edge?.some(.left))
                        Text("Right").tag(DockConfig.Edge?.some(.right))
                        Divider()
                        Text("Floating").tag(DockConfig.Edge?.none)
                    }

                    Button(isMovingThisDock ? "Done Moving" : "Move Dock") {
                        dockManager.setMoveMode(!isMovingThisDock, for: dock.id)
                    }
                }

                Picker("Orientation", selection: Binding(
                    get: { dock.orientation },
                    set: { value in update { $0.orientation = value } }
                )) {
                    Label("Horizontal", systemImage: "rectangle.split.3x1").tag(DockConfig.Orientation.horizontal)
                    Label("Vertical", systemImage: "rectangle.split.1x2").tag(DockConfig.Orientation.vertical)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Automatically hide and show", isOn: Binding(
                        get: { dock.autoHide },
                        set: { value in update { $0.autoHide = value } }
                    ))
                    .disabled(!dock.placement.isSnapped)

                    if !dock.placement.isSnapped {
                        Text("Snap this dock to a screen edge to enable auto-hide.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct RemovableDockChip: View {
    let item: DockItem
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if item.kind == .separator {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0.04))
                        .frame(width: 24, height: 36)
                        .overlay {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.secondary.opacity(0.6))
                                .frame(width: 2, height: 22)
                        }
                        .help("Separator — click × to remove")
                } else if let path = item.path {
                    Image(nsImage: IconCache.shared.icon(for: path, size: 36))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 36, height: 36)
                        .opacity(item.existsOnDisk ? 1.0 : 0.45)
                        .help(item.displayName)
                }
            }

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .secondary)
                }
                .buttonStyle(.borderless)
                .offset(x: 5, y: -5)
                .help("Remove \(item.displayName)")
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

private struct DockChipDropDelegate: DropDelegate {
    let targetItem: DockItem
    let dock: DockConfig
    let dockManager: DockManager
    @Binding var draggedItemID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedItemID,
              draggedID != targetItem.id,
              let fromIndex = dock.items.firstIndex(where: { $0.id == draggedID }),
              let toIndex = dock.items.firstIndex(where: { $0.id == targetItem.id }) else {
            return
        }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            dockManager.reorderItem(in: dock.id, from: fromIndex, to: toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemID = nil
        return true
    }
}

private struct DockTintColorRow: View {
    @Binding var tintColor: DockConfig.TintColor?

    private struct Swatch: Identifiable {
        let id: String
        let name: String
        let tint: DockConfig.TintColor?
    }

    private static let presets: [Swatch] = [
        Swatch(id: "none", name: "Clear (No Tint)", tint: nil),
        Swatch(id: "blue", name: "Blue", tint: DockConfig.TintColor(red: 0.04, green: 0.52, blue: 1.0)),
        Swatch(id: "purple", name: "Purple", tint: DockConfig.TintColor(red: 0.69, green: 0.32, blue: 0.87)),
        Swatch(id: "pink", name: "Pink", tint: DockConfig.TintColor(red: 1.0, green: 0.22, blue: 0.45)),
        Swatch(id: "red", name: "Red", tint: DockConfig.TintColor(red: 1.0, green: 0.27, blue: 0.23)),
        Swatch(id: "orange", name: "Orange", tint: DockConfig.TintColor(red: 1.0, green: 0.58, blue: 0.0)),
        Swatch(id: "yellow", name: "Yellow", tint: DockConfig.TintColor(red: 1.0, green: 0.84, blue: 0.04)),
        Swatch(id: "green", name: "Green", tint: DockConfig.TintColor(red: 0.19, green: 0.82, blue: 0.35)),
        Swatch(id: "graphite", name: "Graphite", tint: DockConfig.TintColor(red: 0.42, green: 0.44, blue: 0.48))
    ]

    private var customColorBinding: Binding<Color> {
        Binding<Color>(
            get: {
                if let t = tintColor {
                    return Color(.sRGB, red: t.red, green: t.green, blue: t.blue, opacity: 1.0)
                }
                return Color(.sRGB, red: 0.04, green: 0.52, blue: 1.0, opacity: 1.0)
            },
            set: { newColor in
                let nsColor = NSColor(newColor).usingColorSpace(.sRGB) ?? NSColor(newColor)
                tintColor = DockConfig.TintColor(
                    red: Double(nsColor.redComponent),
                    green: Double(nsColor.greenComponent),
                    blue: Double(nsColor.blueComponent)
                )
            }
        )
    }

    private func matches(_ a: DockConfig.TintColor?, _ b: DockConfig.TintColor?) -> Bool {
        switch (a, b) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return abs(lhs.red - rhs.red) < 0.02 &&
                   abs(lhs.green - rhs.green) < 0.02 &&
                   abs(lhs.blue - rhs.blue) < 0.02
        default:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tint Color")
                Spacer()
                if tintColor != nil {
                    Button("Clear") {
                        tintColor = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(Self.presets) { preset in
                    let isSelected = matches(tintColor, preset.tint)
                    Button {
                        tintColor = preset.tint
                    } label: {
                        ZStack {
                            if let t = preset.tint {
                                Circle()
                                    .fill(Color(.sRGB, red: t.red, green: t.green, blue: t.blue, opacity: 1.0))
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.75)
                                    )
                            } else {
                                Circle()
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Image(systemName: "nosign")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    )
                            }

                            if isSelected {
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }

                Spacer()

                ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .help("Custom Tint Color")
            }
        }
    }
}
