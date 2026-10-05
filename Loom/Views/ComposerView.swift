import SwiftUI

struct ComposerView: View {
    @Bindable var store: LoomStore
    var focus: FocusState<Bool>.Binding
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
            HStack(alignment: .bottom, spacing: 8) {
                TextField("写下问题…", text: $store.draft, axis: .vertical)
                    .lineLimit(1...7)
                    .focused(focus)
                    .padding(.leading, 10).padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("prompt-field")
                Button {
                    if store.isWorking { store.cancelAll() }
                    else { store.send(); if store.notice == nil { focus.wrappedValue = false } }
                } label: {
                    Image(systemName: store.isWorking ? "stop.fill" : "arrow.up")
                        .font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                        .foregroundStyle(.white)
                        .background(store.isWorking || !store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.indigo : Color.secondary.opacity(0.35), in: .circle)
                }
                .buttonStyle(.plain)
                .disabled(!store.isWorking && store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(store.isWorking ? "停止生成" : "发送给所有模型")
                .accessibilityIdentifier("send-button")
            }
            .padding(6)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 4)
        .frame(maxWidth: 1100).frame(maxWidth: .infinity)
    }
}
