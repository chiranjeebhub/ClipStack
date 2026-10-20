import AppKit
import ClipboardCore
import SwiftUI

@MainActor
struct QuickPanelView: View {
    @Bindable var model: QuickPanelModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                HistoryList(model: model)
                    .frame(width: 400)
                Divider()
                PreviewPane(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .background(VisualEffectBackground(material: .popover).ignoresSafeArea())
        .ignoresSafeArea()
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($searchFocused)
            Picker("Filter", selection: $model.filter) {
                ForEach(HistoryFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Text("↑↓ Navigate")
            Text("↩ Paste")
            Text("⌘1–9 Quick paste")
            Text("⌘P Pin")
            Text("⌘⌫ Delete")
            Spacer()
            Text(countLabel)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var countLabel: String {
        let count = model.store.items.count
        return count == 1 ? "1 item" : "\(count.formatted()) items"
    }
}

@MainActor
private struct HistoryList: View {
    let model: QuickPanelModel

    var body: some View {
        let sections = model.sections
        if sections.isEmpty {
            EmptyHistory(isSearching: !model.query.isEmpty || model.filter != .all)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sections) { section in
                            Text(section.title.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                                .padding(.bottom, 3)
                            ForEach(section.items) { item in
                                HistoryRow(model: model, item: item)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.selectedID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
    }
}

@MainActor
private struct EmptyHistory: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isSearching ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(isSearching ? "No matching items" : "Nothing copied yet")
                .font(.headline)
            Text(isSearching ? "Try a different search or filter." : "Copy something and it will show up here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

@MainActor
private struct HistoryRow: View {
    let model: QuickPanelModel
    let item: ClipItem

    private var selected: Bool { model.selectedID == item.id }

    var body: some View {
        HStack(spacing: 10) {
            KindBadge(item: item, store: model.store, selected: selected)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, design: item.kind == .code ? .monospaced : .default))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 5) {
                    SourceAppIcon(bundleID: item.sourceBundleID, name: item.sourceAppName, size: 13)
                    Text(item.sourceAppName ?? "Unknown app")
                        .fontWeight(.semibold)
                    Text("· \(item.relativeTime(now: model.now))")
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                }
                .font(.system(size: 11))
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .accessibilityLabel("Pinned")
            }
            if let index = model.quickIndex(of: item) {
                Text("⌘\(index)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.paste(item) }
        .onTapGesture { model.selectedID = item.id }
        .contextMenu {
            Button("Paste") { model.paste(item) }
            Button("Paste as Plain Text") { model.paste(item, plainText: true) }
            Button("Copy") { model.copy(item) }
            Divider()
            Button(item.isPinned ? "Unpin" : "Pin") { model.togglePin(item) }
            Button("Delete", role: .destructive) { model.delete(item) }
        }
    }
}

@MainActor
private struct PreviewPane: View {
    @Bindable var model: QuickPanelModel
    @State private var draft = ""

    var body: some View {
        if let item = model.selectedItem {
            VStack(alignment: .leading, spacing: 14) {
                toolbar(for: item)
                content(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                metadata(for: item)
                actions(for: item)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        } else {
            Color.clear
        }
    }

    private func toolbar(for item: ClipItem) -> some View {
        HStack(spacing: 4) {
            Text(item.kind.label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            Spacer()
            Button { model.togglePin(item) } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
            }
            .help(item.isPinned ? "Unpin (⌘P)" : "Pin (⌘P)")
            .accessibilityLabel(item.isPinned ? "Unpin" : "Pin")
            if [.text, .code, .link, .color].contains(item.kind) {
                Button {
                    if model.editingID == item.id {
                        saveDraft(for: item)
                    } else {
                        draft = item.text ?? ""
                        model.editingID = item.id
                    }
                } label: {
                    Image(systemName: model.editingID == item.id ? "checkmark" : "pencil")
                }
                .help(model.editingID == item.id ? "Save" : "Edit (⌘E)")
                .accessibilityLabel(model.editingID == item.id ? "Save" : "Edit")
            }
            Button { model.delete(item) } label: {
                Image(systemName: "trash")
            }
            .help("Delete (⌘⌫)")
            .accessibilityLabel("Delete")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .onChange(of: model.editingID) { _, id in
            if id == item.id { draft = item.text ?? "" }
        }
    }

    private func saveDraft(for item: ClipItem) {
        if draft != item.text { model.store.updateText(id: item.id, text: draft) }
        model.editingID = nil
    }

    @ViewBuilder
    private func content(for item: ClipItem) -> some View {
        let box = RoundedRectangle(cornerRadius: 10)
        if model.editingID == item.id {
            TextEditor(text: $draft)
                .font(.system(size: 12.5, design: item.kind == .code ? .monospaced : .default))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(box.fill(Color(nsColor: .textBackgroundColor).opacity(0.6)))
                .overlay(box.strokeBorder(Color.accentColor))
        } else {
            switch item.kind {
            case .image:
                if let name = item.imageFile, let url = model.store.persistence?.imageURL(for: name), let image = Thumbnails.image(at: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Image is no longer available").foregroundStyle(.secondary)
                }
            case .color:
                VStack(spacing: 12) {
                    box.fill(Color(nsColor: NSColor(hex: item.text ?? "") ?? .gray))
                        .overlay(box.strokeBorder(Color.primary.opacity(0.1)))
                    Text(item.text ?? "").font(.system(size: 15, design: .monospaced)).textSelection(.enabled)
                }
            case .file:
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(item.fileURLs ?? [], id: \.self) { url in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent).lineLimit(1)
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .text, .code, .link:
                ScrollView {
                    Text(item.text ?? "")
                        .font(.system(size: 12.5, design: item.kind == .code ? .monospaced : .default))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                .background(box.fill(Color(nsColor: .textBackgroundColor).opacity(0.5)))
                .overlay(box.strokeBorder(Color.primary.opacity(0.08)))
            }
        }
    }

    private func metadata(for item: ClipItem) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow {
                Text("Copied from").foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    SourceAppIcon(bundleID: item.sourceBundleID, name: item.sourceAppName, size: 16)
                    Text(item.sourceAppName ?? "Unknown app")
                }
            }
            GridRow {
                Text("Copied").foregroundStyle(.secondary)
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            GridRow {
                Text("Size").foregroundStyle(.secondary)
                Text(item.sizeDescription)
            }
            if item.kind == .link, let url = URL(string: item.text ?? "") {
                GridRow {
                    Text("Link").foregroundStyle(.secondary)
                    Button("Open in Browser") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.link)
                }
            }
        }
        .font(.system(size: 12))
    }

    private func actions(for item: ClipItem) -> some View {
        HStack(spacing: 8) {
            Button { model.paste(item) } label: {
                Text("Paste  ↩").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button { model.paste(item, plainText: true) } label: {
                Text("Paste as plain text  ⌥↩").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }
}
