import Foundation

struct TextbookEntry: Identifiable {
    let id: String
    let title: String
    let page: Int
    let group: String
    let credit: String
}

struct PianoTextbook: Identifiable {
    let id: String
    let title: String
    let edition: String
    let publisher: String
    let symbol: String
    let entries: [TextbookEntry]
    var groups: [String] { entries.reduce(into: []) { if !$0.contains($1.group) { $0.append($1.group) } } }
    static let all = [thompson, examination, childrenHanon]
    static let childrenHanon = PianoTextbook(id: "children-hanon", title: "孩子们的哈农", edition: "修订版 · 榕树编", publisher: "上海音乐出版社 / 上海文艺音像电子出版社", symbol: "🌻", entries: [])
    static let thompson: PianoTextbook = {
        let items: [(String, Int, String)] = [
            ("旋律",4,"乐句"),("蜜蜂",5,"三个乐句"),("无事生非",6,"四个乐句"),("有些人",7,"手腕断奏"),
            ("动物展览会",8,"手腕断奏练习"),("在堤岸上",10,"变换手的位置"),("日出",11,"新的表情记号"),
            ("黄鼠狼逃跑了",13,"二音连线"),("布吉乌吉舞曲",14,"左手二音连线"),("知更鸟罗宾",15,"右手二音连线"),
            ("曳步舞",18,"三音连线"),("影子舞",19,"双手交叉"),("玩杂耍的人",21,"四四拍子的新记号"),
            ("杂技演员",22,"F大调音阶"),("我喜欢“节奏”",23,"切分音"),("部落舞",24,"重音和连线"),("步态舞",26,"教师和学生四手联弹"),
            ("跳跃的和弦",30,"左右手的三和弦"),("分解和弦练习曲",31,"分解和弦"),("古老的曲调",32,"和弦的形式"),
            ("双手交叉练习曲",33,"分解和弦"),("中国大戏院",34,"不协和音"),("农民舞曲",35,"D大调"),
            ("降B大调练习曲",36,"降B大调"),("我的太阳",37,"左手分解和弦"),("牛仔之歌",38,"复习"),
            ("小雷格泰姆",39,"切分音"),("假日之歌",40,"A大调"),("嚓，嚓，嚓",41,"六八拍子"),("月光下",42,"降E大调"),("你好吗？",43,"六八拍子")
        ]
        return PianoTextbook(id: "thompson-3", title: "小汤三", edition: "约翰·汤普森简易钢琴教程3 · 全媒体升级版", publisher: "上海音乐出版社 / 上海文艺音像电子出版社", symbol: "🎀",
            entries: items.enumerated().map { index, item in TextbookEntry(id: "thompson-3-\(index)", title: item.0, page: item.1, group: "乐曲目录", credit: item.2) })
    }()
    static let examination: PianoTextbook = {
        // Transcribed from the user's photographed contents, not a different exam edition.
        let grades: [(Int, Int, [(String, Int, String)], [(String, Int, String)], [(String, Int, String)])] = [
            (1,1,[("练习曲",3,"希尔克"),("沂蒙山小调",4,"山东民歌 · 王震亚改编"),("德国舞曲",5,"海顿")],[("练习曲",6,"李重光"),("F大调小步舞曲",7,"J.S.巴赫"),("在花园里",8,"玛伊卡帕尔")],[("行板（选自《惊愕交响曲》）",9,"海顿"),("猫主题（选自《彼得与狼》）",10,"普罗科菲耶夫"),("新疆舞曲",11,"蒋祖馨")]),
            (2,12,[("练习曲",14,"古里特"),("吉格舞曲",15,"爱尔兰民谣 · 弗雷德·科恩改编"),("渴望春天",16,"莫扎特")],[("铃之歌",17,"德利布"),("小步舞曲",19,"普莱耶尔"),("天真烂漫",21,"布格缪勒")],[("谐谑曲",22,"海顿"),("士兵进行曲",23,"舒曼"),("爵士小练习",25,"赛贝尔")]),
            (3,26,[("练习曲",30,"舒曼"),("京剧小段",32,"朱晓宇"),("快活的猎人",34,"默克尔")],[("练习曲",36,"斯迈伍德"),("咏叹调",39,"亨德尔"),("F大调小奏鸣曲",41,"万哈尔")],[("假日的时光",43,"格迪克"),("野玫瑰",45,"舒伯特"),("滑稽的舞蹈",47,"蒋祖馨")]),
            (4,48,[("练习曲",52,"车尔尼"),("萨拉班德",56,"亨德尔"),("紫竹调",58,"江南民歌 · 孙云鹰编曲")],[("练习曲",59,"莱蒙"),("d小调小前奏曲",61,"J.S.巴赫"),("圆舞曲",63,"肖邦")],[("F大调旋律",66,"鲁宾斯坦"),("巴姆巴姆将军",69,"波尔迪尼"),("小风车",72,"葛德月")]),
            (5,74,[("练习曲",78,"杜维诺依"),("二部创意曲",81,"J.S.巴赫"),("西班牙舞曲",83,"肖斯塔科维奇")],[("练习曲",89,"卡巴列夫斯基"),("二部创意曲",93,"J.S.巴赫"),("河边邂逅",95,"葛德月")],[("小圆舞曲",99,"柴科夫斯基"),("游行进行曲",103,"利希纳"),("第一号塞北舞曲——社火（选自《塞北小曲三十首》）",107,"黄安伦")]),
            (6,110,[("练习曲",114,"车尔尼"),("三部创意曲",117,"J.S.巴赫"),("持续的行板",120,"门德尔松")],[("练习曲",123,"拉克"),("布列舞曲",126,"泰勒曼"),("蝴蝶",129,"默克尔")],[("小夜曲",134,"奥尔森"),("恰空",137,"亨德尔"),("太阳雨",142,"谭盾")])
        ]
        var entries: [TextbookEntry] = []
        for (level, page, a, b, optional) in grades {
            entries.append(TextbookEntry(id: "ccm-\(level)-basic", title: "基本练习", page: page, group: "\(level)级 · 基本练习", credit: ""))
            for (name, pieces) in [("A组",a),("B组",b),("自选曲目",optional)] {
                for (index, piece) in pieces.enumerated() {
                    entries.append(TextbookEntry(id: "ccm-\(level)-\(name)-\(index)", title: piece.0, page: piece.1, group: "\(level)级 · \(name)", credit: piece.2))
                }
            }
        }
        return PianoTextbook(id: "ccm-piano-1-6", title: "中国音乐学院钢琴考级", edition: "社会艺术水平考级精品教材 · 一级～六级", publisher: "中国青年出版社 · 中国音乐学院考级委员会主编", symbol: "🏅", entries: entries)
    }()
}
