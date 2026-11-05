# Omarchy Tablet Lite

**平板上的核心三件事：Omarchy 自己没有的虚拟键盘、Omarchy 听写的触屏入口、
屏幕旋转 —— 其余一概不要。**它是
[omarchy-tablet-experience](https://github.com/gmaxxxie/omarchy-tablet-experience)
的轻量分支，适合只想要这几件事的 2-in-1：笔记本/平板模式切换、手写、窗口管理、
状态栏精简这些都不装。

英文版：[README.md](README.md)

## 功能

- **虚拟键盘** —— `wvkbd-deskintl`，wlroots 原生，带 **Ctrl / Super / Alt /
  Shift / AltGr**、**F1–F12**、**数字行**（中文候选词）和**方向键**。为平板
  编译，并加了一个可见的 **▼ 收起键**，随处都能把键盘折起来。切换方式：
  `SUPER+U`、状态栏 **⌨** 按钮、或
  `omarchy-shell maxt.tablet-lite keyboardToggle`。wvkbd 是**唯一**后端：lite
  构建缺失时 helper 会直接报错，不再悄悄换成按键不同的另一种键盘。状态栏的
  键盘高亮跟着 Hyprland 的 `openlayer` / `closelayer` 事件走，用 **▼** 键收起
  键盘后立即同步。
- **语音输入** —— 状态栏 **🎤** 按钮打开底部的按住说话浮层。按住 →
  `omarchy dictation start`，松开 → `omarchy dictation stop`。这就是 Omarchy
  自己的听写命令（`ALT+SPACE` / `Alt_R` / `F9` 走的是同一套）：后端选谁
  （voxtype、superwhisper…）、它的锁、以及把文字打进当前光标处（终端和各种
  toolkit 都支持中文）都归 Omarchy 管。本插件**不再自建任何听写管线**：没有
  后端探测、没有 state 文件轮询、没有 `voxtype record` 回退。没装或没选后端时
  弹一条 OSD（设置 ▸ 默认 ▸ Dictation）。浮层本身还是完整的语音键盘：
  **Delete / Clear / Enter** 修正或提交这一行（Clear 认终端：终端里走 readline
  `Ctrl+A`+`Ctrl+K`，其它窗口是全选删除），左侧 **← → ↑ ↓** 移光标，展开
  **CLI keys** 网格可发送 `esc` `/` `tab` `⇧tab` `⌃C` `⌃D` `⌃J` `⌃T`，纯触屏
  操作 pi / codex CLI 不用唤出键盘。
- 语音和键盘**互斥**：打开一个会自动关掉另一个。
- **CLI keys + 光标板只在语音模式显示** —— 和按住说话浮层一起出现；键盘打开时
  自动隐藏。
- **屏幕旋转** —— 状态栏只留**一个** **⟳** 按钮，点开是选择面板：
  **自动（传感器）**（默认）+ 0° / 90° / 180° / 270°（这四个角度就是四步
  90°，所以不再另设 ⟲/⟳ 两键）。`SUPER+SHIFT+R` 仍可不开面板直接步进。
  选固定角度会关掉自动；选「自动」交回 `tlit-orient`（读 sysfs 加速度计，
  按 ThinkPad X12 校准），它用一个**常驻读取进程**，只在姿态变化时上报
  （不再每秒起进程）。每次旋转都会**保留当前缩放**并同步 Hyprland 的
  **触摸校准矩阵**（`tlit-rotate`）；选择的角度和自动开关由 `tlit-state`
  存盘，shell 重启后保持。

- **锁屏键盘** —— 锁屏时**自动升起键盘**用于输入密码（指纹仍然可用），
  通过 `above_lock` 渲染在 Omarchy 锁屏界面之上。密码框右侧有一个浮动 **⌨**
  按钮，键盘被 **▼** 收起后可再次调出；解锁时自动放下。shell 启动时会预启动
  键盘并隐藏，锁屏下升起时不需要在已锁定的会话里新建 Wayland 客户端。

- **竖屏时状态栏自动折叠** —— 在 90°/270° 竖屏下，三个触控图标（键盘 /
  语音 / 旋转）折叠成一个**平板按钮**，点开弹窗后以触屏大小提供同样的操作；
  横屏仍保留一键直达的三个图标。这样竖屏窄状态栏里图标不会
  再和时钟挤在一起。

- **Mousehop KVM 开关**（单独的状态栏组件 `maxt.mousehop`，装在本插件
  **旁边**而不是里面）—— 显示软件 KVM 客户端现在有没有「武装」，一下点掉/点开。
  开 = 指针一推到对端边缘，指针和键盘就交给对端（InputCapture 会话，期间本地
  输入全部丢失）；关 = 完全不抓取。和 `SUPER+SHIFT+K` 同一个动作。

- **Folio 触控板抢救** —— X12 Detachable 的键盘（Darfon `17ef:60fe`）把一个
  HID 接口上的两样东西分得很开：真正的触控板（`BTN_TOOL_FINGER` / 
  `DOUBLETAP` / `TRIPLETAP`、`ABS_MT_SLOT`、`ABS_MT_TRACKING_ID`）和一套传统的
  相对「鼠标」通道。把键盘拆下来再吸回去，USB 会重新枚举，`hid-multitouch`
  有时候回来时多点触控报告通道是死的：光标还能动、还能点，但 **tap、按压、
  双指和三指手势全部静默失效**，而且 libinput 连一条 `ABS_MT` 事件都收不到——
  所以 Hyprland 和触控板设置本身都没错，只有重绑驱动能救。`tlit-folio-touchpad`
  就做这件事，一条 udev 规则加一个 oneshot 服务会让它在键盘出现两秒后自动跑，
  拆装键盘自己就好了。手动：`sudo tlit-folio-touchpad`。

有意去掉：笔记本/平板状态机、键盘自动切换、手写、窗口管理、状态栏精简、
多点触控手势（底部上滑调键盘的守护进程已删——▼ 键、`SUPER+U` 和状态栏
按钮已经够用）、SDDM 登录界面改动（锁屏已支持）。

2.0.0 删掉的是「这里本来就有」的重复：听写后端探测和 state 轮询
（`omarchy dictation` 已经有）。语音浮层自己的按键保留 —— 键盘上确实有
Esc / Tab / Ctrl / 方向键，但那些键是为了「收起键盘只靠听写」时用的。

## 依赖

- Omarchy 4.x（Quickshell）+ Hyprland 0.56+（Lua 配置 API），Arch 系。
- 听写后端（Omarchy 4.5 的 `omarchy dictation` 已内置 voxtype 支持：AUR
  `voxtype-bin`、`omarchy-install-dictation-voxtype`）。文字由后端打进光标；
  浮层自己的按键需要 `wtype`。
- 自动旋转需要 `python3` 和可读的 IIO 加速度计（`tlit-orient` 直读 sysfs，
  不需要额外的守护进程）。
- 编译 wvkbd 需要 `cairo pango wayland libxkbcommon`（多数 Omarchy 装机已有）。
- 有触摸屏最好，但没有任何硬件绑定：键鼠同样能用。
- 唯一与硬件绑定的只有 Folio 触控板抢救：它只匹配 X12 Detachable Gen 1 的
  键盘（`17ef:60fe`），其他机器上永远不会触发。

## 安装

```sh
# 1. 插件（QML service + 状态栏组件）：
omarchy plugin add https://github.com/gmaxxxie/omarchy-tablet-experience-lite.git --enable

# 2. 系统侧（helper 脚本、wvkbd 构建、Hyprland 钩子、voxtype 接线）：
~/.config/omarchy/plugins/maxt.tablet-lite/install.sh
```

仓库根目录就是插件目录；第 1 步之后克隆在
`~/.config/omarchy/plugins/maxt.tablet-lite`，`install.sh` 在那里运行。
开发用的克隆里同样可以运行。

`install.sh` 选项：

| 参数 | 作用 |
|---|---|
| *(无)* | helper + wvkbd 构建 + `SUPER+U` 钩子 + voxtype 接线 |
| `--no-packages` | 不调用 pacman（`wtype`） |
| `--no-system` | 不装 Folio 触控板抢救（不用 sudo，全部写入都在 `$HOME` 内） |
| `--no-wvkbd` | 跳过构建（构建完成前键盘不可用） |
| `--dry-run` | 只预览，不改任何东西 |
| `--verify` | 安装后只读自检 |

除 Folio 触控板抢救（helper 在 `/usr/local/bin`、一个 systemd 服务、一条
udev 规则；`--no-system` 可跳过）之外，所有写入都在 `$HOME` 内；只有它和装
`wtype` 那一步需要 sudo。
每个被修改的文件都会先备份成 `*.bak.<时间戳>`。

**重载一次 shell**（或重新登录）让插件重新加载，然后运行
`install.sh --verify`。

## 使用

| 操作 | 方式 |
|---|---|
| 开关虚拟键盘 | `SUPER+U` · 状态栏 **⌨** · `omarchy-shell maxt.tablet-lite keyboardToggle` |
| 收起键盘 | 键盘上的 **▼** 键 |
| 旋转 | 状态栏 **⟳** → 选择面板（自动 / 0° / 90° / 180° / 270°）· `SUPER+SHIFT+R` 步进 · `omarchy-shell maxt.tablet-lite rotationNext` |
| 传感器自动旋转（默认） | 面板里的**自动** · `omarchy-shell maxt.tablet-lite autoRotateToggle` |
| 指定角度 | 面板里的角度行 · `omarchy-shell maxt.tablet-lite setRotation 0|1|2|3|auto` |
| 竖屏状态栏 | 三个图标折叠成一个**平板按钮** → 弹窗里选键盘 / 语音 / 旋转 |
| 锁屏键盘 | 锁屏自动升起；密码框右侧浮动 **⌨** 按钮可重调；**▼** 收起 |
| 开/关语音浮层 | 状态栏 **🎤** · `omarchy-shell maxt.tablet-lite voiceInputToggle` |
| 说话输入 | 按住大麦克风，松开转写 |
| 修正文本 | **Delete**（退格）/ **Clear**（全选删除；终端里是 readline `Ctrl+A`+`Ctrl+K`）/ **Enter** |
| 移动光标 | 左侧 **← → ↑ ↓** |
| Agent 按键（pi / codex） | **CLI keys ▲** → `esc` `/` `tab` `⇧tab` `⌃C` `⌃D` `⌃J` `⌃T` |
| mousehop KVM 开/关 | 状态栏 **⇄**（红色=已开）· `SUPER+SHIFT+K` · `tlit-mousehop-toggle on|off|toggle|status` |
| 拆装键盘后触控板失灵 | 自动（udev 规则 → `tlit-folio-touchpad`）· 手动：`sudo tlit-folio-touchpad` |

IPC：`getState` · `voiceInputToggle|Show|Hide` ·
`keyboardToggle|Show|Hide` · `cliKeysToggle` · `clearNow` ·
`rotationNext|rotationPrev` · `setRotation <auto|0|1|2|3>` · `autoRotateToggle`
（`omarchy-shell maxt.tablet-lite <method>`）。

## 卸载

```sh
~/.config/omarchy/plugins/maxt.tablet-lite/uninstall.sh
omarchy plugin remove maxt.tablet-lite
omarchy plugin remove maxt.mousehop
```

helper 都以 `tlit-*` 装进 `~/.local/bin`，刻意与 full 插件的 `texp-*` 分开：
两个插件可以并存，不会互相覆盖对方的键盘 helper。

`tlit-folio-touchpad` 是例外：udev 和 systemd 以 root 运行它，所以它和它的服务、
udev 规则一起装在 `/usr/local/bin` / `/etc`，`uninstall.sh` 会用 sudo 把它们删掉
（依旧只在字节完全一致时才删）。删掉后键盘照用，但拆装键盘可能让触控板失去
tap / 按压 / 双指三指手势，直到下次重启。

其中 `mousehop`、`rotate`、`vtext` 与 full 插件的 `texp-*` 是**同一份程序**
（只有前缀不同），`vk`、`orient`、`install-wvkbd`、`state`、`mousehop-toggle`
是 lite 独有。
`tools/helper-drift` 会拿这三份和 full 插件检出目录（`$TEXP_UPSTREAM`，默认
`../omarchy-tablet-experience`）比对，`--sync` 把 lite 的版本覆盖过去（改前缀）
——所以同一处只写一次。

## 许可

MIT，见 [LICENSE](LICENSE)。由同一作者的 omarchy-tablet-experience 精简而来。
