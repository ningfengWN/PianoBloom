import SwiftUI

struct TextbookLibrary: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("我的教材书架").font(.largeTitle.bold()).foregroundStyle(Bloom.ink)
                Text("按你提供的教材版本整理。曲目目录已核对；原谱音符录入后才能进行跟谱评分。")
                    .font(.subheadline).foregroundStyle(Bloom.lilac)
                ForEach(PianoTextbook.all) { book in
                    NavigationLink { TextbookContents(book: book) } label: {
                        HStack(spacing: 16) {
                            Text(book.symbol).font(.system(size: 38)).frame(width: 64, height: 80).background(Bloom.blush, in: RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(book.title).font(.headline).foregroundStyle(Bloom.ink)
                                Text(book.edition).font(.caption).foregroundStyle(Bloom.lilac)
                                Text(book.entries.isEmpty ? "版本已确认 · 等待目录与谱页" : "\(book.entries.count)项目录 · 待录入曲谱").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(Bloom.pink)
                        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 24))
                    }.buttonStyle(.plain)
                }
            }.padding(22).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(Bloom.blush).navigationTitle("教材").navigationBarTitleDisplayMode(.inline)
    }
}

private struct TextbookContents: View {
    let book: PianoTextbook
    @State private var query = ""
    @State private var level = 3
    private var visible: [TextbookEntry] {
        book.entries.filter { item in
            (book.id != "ccm-piano-1-6" || item.group.hasPrefix("\(level)级")) &&
            (query.isEmpty || (item.title + item.credit + item.group).localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(book.title).font(.title.bold()).foregroundStyle(Bloom.ink)
                Text(book.edition + "\n" + book.publisher).font(.caption).foregroundStyle(.secondary)
                if book.id == "ccm-piano-1-6" {
                    Picker("考级级别", selection: $level) {
                        ForEach(1...6, id: \.self) { Text("\($0)级").tag($0) }
                    }.pickerStyle(.segmented)
                }
                if !book.entries.isEmpty {
                    TextField("搜索曲名或作曲家", text: $query).textFieldStyle(.roundedBorder)
                }
                Label(book.entries.isEmpty ? "待补充目录和曲谱页" : "当前为教材目录，尚未录入原谱音符", systemImage: "book.closed")
                    .font(.subheadline).foregroundStyle(Bloom.lilac).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                ForEach(book.groups.filter { group in visible.contains(where: { $0.group == group }) }, id: \.self) { group in
                    Text(group).font(.headline).foregroundStyle(Bloom.pink)
                    ForEach(visible.filter { $0.group == group }) { entry in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.title).font(.headline).foregroundStyle(Bloom.ink)
                                if !entry.credit.isEmpty { Text(entry.credit).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 5) {
                                Text("第\(entry.page)页").font(.caption.bold()).foregroundStyle(Bloom.lilac)
                                Text("待录入曲谱").font(.caption2).foregroundStyle(.secondary)
                            }
                        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                if book.entries.isEmpty {
                    Text("已确认《孩子们的哈农》修订版。补充目录和正在练习的谱页后，可以按书中顺序加入练习。").font(.subheadline).foregroundStyle(Bloom.ink)
                } else if visible.isEmpty { Text("没有找到这首曲子，试试其他关键词。").foregroundStyle(.secondary) }
            }.padding(22).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(Bloom.blush).navigationTitle("教材目录").navigationBarTitleDisplayMode(.inline)
    }
}
