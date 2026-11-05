# maxt.mousehop — Mousehop KVM 状态栏开关

`maxt.tablet-lite` 的**邻居插件**：状态栏上一个小开关，显示 mousehop（软件
KVM）现在开没开，点一下切换。装在 `~/.config/omarchy/plugins/maxt.mousehop`
而不是并进 tablet-lite —— KVM 不是平板功能，两个插件可以各自装卸。

| 图标 | 含义 |
|---|---|
| 关着的拨动开关（`fa-toggle-off`） | mousehop **关**：不抓取，指针和键盘全留本机 |
| 红色 ⇄（`fa-arrows-left-right`） | mousehop **开**：指针推到对端边缘就跨过去，指针+键盘交给对端 |
| 变暗 | daemon 没在跑，读不到状态 |

点击 = `tlit-mousehop-toggle toggle`，和 `SUPER + SHIFT + K`
（`config/hypr/mousehop.lua`）同一个动作。

## 为什么要它

mousehop 走 InputCapture（libei/EIS）。会话一旦建立，Hyprland 就把**所有**
指针和键盘事件转发给对端、本地不处理 —— 表现就是「触控板没反应」
「鼠标指针不见了」。它释放捕获时又算不出 `warp_target`
（日志里 `release-warp … → warp_target=None`），指针会留在 x≈0 那一条上，
稍微一动就又跨过去。所以需要一个一眼看到、一按就断开的地方。

`off` 会先 `tlit-mousehop release` 释放已存在的捕获，再 deactivate 客户端 ——
所以这个按钮也能把已经卡在对端的指针救回来。

## 实现

`BarWidget.qml` 每 3 秒跑一次 `mousehop cli list`（Rust 二进制，约 5 ms，
不启 python、不过 shell），正则读 `active: true|false`；点击后 350 ms 再补
一次轮询。所以用快捷键或 mousehop GUI 改的状态，图标最多 3 秒跟上。

## 装

```sh
./install.sh                       # 从仓库根目录：装 helper + 本组件 + hypr 钩子
./install.sh --verify              # 自检
omarchy plugin remove maxt.mousehop # 只卸这个组件
```

改完 QML 若没热更新（编辑器保存会自动重载，`sed -i` 有时抓不到）：
`omarchy restart shell`。
