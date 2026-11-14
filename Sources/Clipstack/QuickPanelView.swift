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
            FilterBar(selection: $model.filter, pinnedOnly: model.pinnedOnly)
            PinnedToggle(isOn: $model.pinnedOnly)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Text("↑↓ Navigate")
            Text("←→ Filter")
            Text(PasteService.canPasteDirectly ? "↩ Paste" : "↩ Copy, then ⌘V")
            Text(PasteService.canPasteDirectly ? "⌘1–9 Quick paste" : "⌘1–9 Quick copy")
            Text("⌘P Pin")
            Text("⇧⌘P Pinned")
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
            EmptyHistory(isSearching: !model.query.isEmpty || model.filter != .all || model.pinnedOnly)
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
                // Reopening on the last pasted item may not change the selection, so scroll to it anyway.
                .onChange(of: model.focusToken) {
                    if let id = model.selectedID { proxy.scrollTo(id) }
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
        HStack(spacing: 12) {
            thumbnail
            Text(item.rowText)
                .font(.system(size: 13, design: item.kind == .code ? .monospaced : .default))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .accessibilityLabel("Pinned")
            }
            VStack(alignment: .trailing, spacing: 3) {
                if let index = model.quickIndex(of: item) {
                    Text("⌘\(index)")
                        .font(.system(size: 11).monospacedDigit())
                }
                Text(item.relativeTime(now: model.now))
                    .font(.system(size: 10))
            }
            .lineLimit(1)
            .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.sourceAppName.map { "Copied from \($0)" } ?? "")
        .onTapGesture(count: 2) { model.paste(item) }
        .onTapGesture { model.selectedID = item.id }
        .contextMenu {
            if PasteService.canPasteDirectly {
                Button("Paste") { model.paste(item) }
                Button("Paste as Plain Text") { model.paste(item, plainText: true) }
                Button("Copy") { model.copy(item) }
            } else {
                Button("Copy") { model.paste(item) }
                Button("Copy as Plain Text") { model.paste(item, plainText: true) }
            }
            if item.kind == .image {
                Button("Copy Text from Image") { model.copyText(from: item) }
                    .disabled(item.recognizedText == "")
                Button("Save Image…") { model.saveImage(item) }
            }
            Divider()
            Button(item.isPinned ? "Unpin" : "Pin") { model.togglePin(item) }
            Button("Delete", role: .destructive) { model.delete(item) }
        }
    }
}

extension HistoryRow {
    /// The kind thumbnail with the source app's icon as a badge on its bottom-right corner.
    private var thumbnail: some View {
        KindBadge(item: item, store: model.store, selected: selected, size: 34)
            .overlay(alignment: .bottomTrailing) {
                if item.sourceBundleID != nil || item.sourceAppName != nil {
                    SourceAppIcon(bundleID: item.sourceBundleID, name: item.sourceAppName, size: 16)
                        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                        .offset(x: 5, y: 5)
                        .help(item.sourceAppName ?? "")
                }
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
        let hasItemActions = item.kind == .image || item.isEditable
        return HStack(spacing: 6) {
            Text(item.kind.label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            Spacer()
            // What this kind of item can do, spelled out, then pin and delete as icons.
            if item.kind == .image {
                let reading = model.readingTextID == item.id
                Button { model.copyText(from: item) } label: {
                    PreviewActionLabel(
                        title: reading ? "Reading…" : item.recognizedText == "" ? "No Text" : "Copy Text",
                        systemImage: "text.viewfinder", isBusy: reading
                    )
                }
                .disabled(item.recognizedText == "" || reading)
                .help(item.recognizedText == "" ? "No text found in this image" : "Copy the text in this image")
                Button { model.saveImage(item) } label: {
                    PreviewActionLabel(title: "Save", systemImage: "square.and.arrow.down")
                }
                .help("Save Image…")
            }
            if item.isEditable {
                let editing = model.editingID == item.id
                Button {
                    if editing {
                        saveDraft(for: item)
                    } else {
                        draft = item.text ?? ""
                        model.editingID = item.id
                    }
                } label: {
                    PreviewActionLabel(title: editing ? "Done" : "Edit", systemImage: editing ? "checkmark" : "pencil")
                }
                .help(editing ? "Save changes" : "Edit (⌘E)")
            }
            if hasItemActions {
                Divider().frame(height: 16).padding(.horizontal, 2)
            }
            Button { model.togglePin(item) } label: {
                PreviewActionLabel(systemImage: item.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(PreviewActionStyle(tone: item.isPinned ? .active : .normal))
            .help(item.isPinned ? "Unpin (⌘P)" : "Pin (⌘P)")
            .accessibilityLabel(item.isPinned ? "Unpin" : "Pin")
            Button { model.delete(item) } label: {
                PreviewActionLabel(systemImage: "trash")
            }
            .buttonStyle(PreviewActionStyle(tone: .destructive))
            .help("Delete (⌘⌫)")
            .accessibilityLabel("Delete")
        }
        .buttonStyle(PreviewActionStyle())
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
                if let name = item.imageFile, let url = model.store.persistence?.imageURL(for: name), let image = Thumbnails.image(at: url, maxPixels: Thumbnails.previewSize) {
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
                Text("\(PasteService.actionVerb)  ↩").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button { model.paste(item, plainText: true) } label: {
                Text("\(PasteService.actionVerb) as plain text  ⌥↩").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }
}

/// Type filters as one rounded track with a soft pill behind the selected item, matching the
/// mockup; the system segmented control draws separators and a blue selection instead.
@MainActor
private struct FilterBar: View {
    @Binding var selection: HistoryFilter
    /// With pinned-only on and no type chosen, the pin button is the selected stop, not All.
    let pinnedOnly: Bool
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(HistoryFilter.allCases) { filter in
                let isSelected = filter == selection && !(pinnedOnly && filter == .all)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = filter }
                } label: {
                    Text(filter.label)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.16))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        .fixedSize()
    }
}

/// Shows only pinned items. Separate from the type filters so it combines with them.
@MainActor
private struct PinnedToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: isOn ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isOn ? 0.16 : 0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Showing pinned items only (⇧⌘P)" : "Show pinned items only (⇧⌘P)")
        .accessibilityLabel("Pinned only")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A preview action: an icon with an optional label, sized to sit in a row of others.
private struct PreviewActionLabel: View {
    var title: String?
    let systemImage: String
    var isBusy = false

    var body: some View {
        HStack(spacing: 5) {
            if isBusy {
                ProgressView().controlSize(.mini).frame(width: 14)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 14)
            }
            if let title {
                Text(title).font(.system(size: 12, weight: .medium))
            }
        }
        .padding(.horizontal, title == nil ? 0 : 9)
        .frame(minWidth: 28, minHeight: 26)
    }
}

/// Soft rounded buttons for the preview's actions. Pinned shows in the accent colour, and delete
/// turns red under the pointer.
private struct PreviewActionStyle: ButtonStyle {
    enum Tone { case normal, active, destructive }
    var tone: Tone = .normal

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, tone: tone)
    }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        let tone: Tone
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let danger = tone == .destructive && hovering && isEnabled
            let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
            configuration.label
                .foregroundStyle(danger ? Color.red : tone == .active ? Color.accentColor : Color.primary.opacity(0.85))
                .background(shape.fill(fill(danger: danger)))
                .overlay(shape.strokeBorder(danger ? Color.red.opacity(0.35) : Color.primary.opacity(0.08)))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }

        private func fill(danger: Bool) -> Color {
            if danger { return Color.red.opacity(0.15) }
            if tone == .active { return Color.accentColor.opacity(0.18) }
            let base = hovering && isEnabled ? 0.12 : 0.06
            return Color.primary.opacity(configuration.isPressed ? base + 0.06 : base)
        }
    }
}

private extension ClipItem {
    /// Items whose text can be edited in place.
    var isEditable: Bool { [.text, .code, .link, .color].contains(kind) }
}
