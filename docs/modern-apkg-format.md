# 新版 .apkg 读取范围

2026-10-15 根据 Ankitects 官方公开格式独立实现读取；未复制 Anki 实现源码。查阅时 main 提交为 `c4852282f3fa43e5eddb5da740b7956602368ba9`。官方代码路径：

- `https://github.com/ankitects/anki/blob/c4852282f3fa43e5eddb5da740b7956602368ba9/proto/anki/import_export.proto`：PackageMetadata、MediaEntries、MediaEntry。
- `https://github.com/ankitects/anki/blob/c4852282f3fa43e5eddb5da740b7956602368ba9/rslib/src/import_export/package/meta.rs`：包版本、集合文件名、导出 schema 18。
- `https://github.com/ankitects/anki/blob/c4852282f3fa43e5eddb5da740b7956602368ba9/rslib/src/import_export/package/media.rs`：媒体逐项压缩、清单及大小／SHA1。
- `https://github.com/ankitects/anki/blob/c4852282f3fa43e5eddb5da740b7956602368ba9/proto/anki/notetypes.proto`：Notetype.Config.kind。
- `https://github.com/ankitects/anki/blob/c4852282f3fa43e5eddb5da740b7956602368ba9/rslib/src/storage/upgrades/schema15_upgrade.sql`：规范化 fields／notetypes／decks 表。
- `https://github.com/ankitects/anki/blob/c4852282f3fa43e5eddb5da740b7956602368ba9/rslib/src/storage/upgrades/schema18_upgrade.sql`：schema 18。
- `https://github.com/ankitects/anki/blob/c4852282f3fa43e5eddb5da740b7956602368ba9/rslib/src/decks/name.rs`：章节名 U+001F 转为 `::`。

## 支持的读取路径

没有 meta 时保留旧版 collection.anki21／collection.anki2 推断；存在 collection.anki21b 却没有有效版本时拒绝，不会误读兼容提示卡。meta 版本 1／2／3 对应 anki2／anki21／anki21b；未知版本拒绝。

版本 3：集合、media 清单、数字媒体文件均为 Zstd 帧。清单为重复 field 1 的 MediaEntry；每项读取名称（field 1）、解压大小（field 2）、20 字节 SHA1（field 3）。媒体按清单顺序映射 ZIP 中 0、1……，解码后同时校验真实长度和 SHA1。容许未知 protobuf 标量字段，拒绝截断／越界长度／错误 wire type。

规范化数据库支持 schema 15–18，读取 notetypes.config 的 kind、按 ord 排序的 fields、decks.name。为 WITHOUT ROWID 表的查询规划注册名为 unicase 的排序函数；只执行按数字 ID／序号排序的只读查询，不比较或更新 Anki 名称。旧版 JSON 元数据路径保持兼容。

转换范围仍为现有标准基础卡、填空卡、可选 Source／来源字段及媒体。不执行自定义模板和脚本，不迁移原 Anki 排程，所有卡片从新卡开始。不支持的笔记按既有导入报告计入跳过。

## 资源与失败处理

- 牌组包最大 512 MiB、ZIP 最多 50,000 项；ZIP 实际输出与后续 Zstd 输出累计最大 512 MiB（包括暂存压缩数据）；清单最大 8 MiB，meta 最大 64 KiB。
- 复用现有 archive 库的流式 Zstd 解码，开启 throwOnError／checksum verification，输出大小受限，窗口最大 128 MiB；不新增依赖。
- 验证 ZIP CRC、路径、重复项、符号链接；原始 ZIP 和解码目录分开，媒体名不能含目录。失败清理本次暂存目录，不把不完整包写入本地牌组。
- 自动测试使用按公开格式构造的含真实 SQLite 索引／unicase／WITHOUT ROWID 的压缩夹具，包含图片及两种笔记；另保留用户提供的操作系统旧格式包验收。新版真实导出包及 Android 真机仍需用户验收，未据合成夹具声称全模板兼容。
