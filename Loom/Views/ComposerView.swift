import SwiftUI

struct ComposerView: View {
    @Bindable var store: LoomStore
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 10) {
            if !store.current.quotes.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(store.current.quotes) { quote in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(quote.modelName + " · 第 \(quote.round) 轮").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                                    Text(quote.text).font(.caption).lineLimit(2).frame(maxWidth: 220, alignment: .leading)
                                }
                                Button { store.removeQuote(quote.id) } label: { Image(systemName: "xmark.circle.fill") }
                                    .foregroundStyle(.secondary).accessibilityLabel("移除引用：\(quote.text)")
                            }.padding(10).background(.yellow.opacity(0.16), in: .rect(cornerRadius: 14))
                        }
                    }.padding(.horizontal, 4)
                }.scrollIndicators(.hidden).accessibilityIdentifier("quote-tray")
            }
            GlassEffectContainer(spacing: 12) {
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("写下问题，让观点交织…", text: $store.draft, axis: .vertical)
                        .lineLimit(1...5).padding(.horizontal, 18).padding(.vertical, 14)
                        .focused($focused)
                        .glassEffect(.regular, in: .rect(cornerRadius: 26))
                        .accessibilityIdentifier("prompt-field")
                    Button {
                        if store.isWorking { store.cancelAll() }
                        else { store.send(); if store.notice == nil { focused = false } }
                    } label: {
                        Image(systemName: store.isWorking ? "stop.fill" : "arrow.up")
                            .font(.system(size: 19, weight: .semibold)).frame(width: 52, height: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .disabled(!store.isWorking && store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(store.isWorking ? "停止生成" : "发送给所有模型")
                    .accessibilityIdentifier("send-button")
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "highlighter")
                Text(store.current.quotes.isEmpty ? "选中文字，自动高亮并加入下一轮引用" : "\(store.current.quotes.count) 段引用将发送给所有模型")
            }.font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("selection-hint")
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10)
        .frame(maxWidth: 1100).frame(maxWidth: .infinity)
    }
}
