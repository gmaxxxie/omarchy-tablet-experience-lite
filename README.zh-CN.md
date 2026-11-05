# Omarchy Tablet Lite

**平板体验的精简版：只保留触屏真正需要的虚拟键盘、语音输入和屏幕旋转。**
它是 [omarchy-tablet-experience](https://github.com/gmaxxxie/omarchy-tablet-experience)
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
- **语音输入** —— 状态栏 **🎤** 按钮打开底部的按住说话浮层。按住开始，
  松开后由 `omarchy dictation start|stop` 完成转写：这就是 `ALT+SPACE` /
  `Alt_R` / `F9` 快捷键走的那套命令，后端（voxtype、superwhisper…）由
  Omarchy 4.5 统一管理，触屏按钮和键盘快捷键不会各走一套。没有配置后端时
  回退到 `voxtype record start|stop`。转写结果用 `wtype` 打进当前光标处
  （终端和各种 toolkit 都支持中文）。
  **Delete / Clear / Enter** 修正或提交这一行；左侧 **← → ↑ ↓** 移动光标；
  展开 **CLI keys** 网格可发送 `esc` `/` `tab` `⇧tab` `⌃C` `⌃D` `⌃J` `⌃T`，
  方便在纯触屏上操作 pi / codex CLI。
- 语音和键盘**互斥**：打开一个会自动关掉另一个。
- **CLI keys + 光标板只在语音模式显示** —— 和按住说话浮层一起出现；键盘打开时
  自动隐藏，因为键盘本身已经有 Esc / Tab / Ctrl / 方向键，不再遮住键盘上方的
  内容。
- **屏幕旋转** —— 状态栏 **⟳** 按钮和 **`SUPER+SHIFT+R`** 在 0° / 90° /
  180° / 270° 之间旋转。旁边的 **🧭** 按钮开关**传感器自动旋转**
  （`tlit-orient` 读 sysfs 加速度计，按 ThinkPad X12 校准），开启时高亮。
  自动旋转用**一个常驻读取进程**，只在姿态变化时上报（不再每秒起进程）。
  每次旋转都会**保留当前缩放**并同步 Hyprland 的**触摸校准矩阵**
  （`tlit-rotate`），最后一个角度会持久化，shell 重启不会悄悄转回横屏。

- **锁屏键盘** —— 锁屏时**自动升起键盘**用于输入密码（指纹仍然可用），
  通过 `above_lock` 渲染在 Omarchy 锁屏界面之上。密码框右侧有一个浮动 **⌨**
  按钮，键盘被 **▼** 收起后可再次调出；解锁时自动放下。shell 启动时会预启动
  键盘并隐藏，锁屏下升起时不需要在已锁定的会话里新建 Wayland 客户端。

- **竖屏时状态栏自动折叠** —— 在 90°/270° 竖屏下，四个触控图标（键盘 /
  语音 / 旋转 / 自动旋转）折叠成一个**平板按钮**，点开弹窗后以触屏大小提供
  同样四个操作；横屏仍保留一键直达的四个图标。这样竖屏窄状态栏里图标不会
  再和时钟挤在一起。

有意去掉：笔记本/平板状态机、键盘自动切换、手写、窗口管理、状态栏精简、
多点触控手势（底部上滑调键盘的守护进程已删——▼ 键、`SUPER+U` 和状态栏
按钮已经够用）、SDDM 登录界面改动（锁屏已支持）。

## 依赖

- Omarchy 4.x（Quickshell）+ Hyprland 0.56+（Lua 配置 API），Arch 系。
- 语音需要 `wtype` 和一个听写后端（Omarchy 4.5 的 `omarchy dictation`
  已内置 voxtype 支持：AUR `voxtype-bin`、`omarchy-install-dictation-voxtype`）。
- 自动旋转需要 `python3` 和可读的 IIO 加速度计（`tlit-orient` 直读 sysfs，
  不需要额外的守护进程）。
- 编译 wvkbd 需要 `cairo pango wayland libxkbcommon`（多数 Omarchy 装机已有）。
- 有触摸屏最好，但没有任何硬件绑定：键鼠同样能用。

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
| `--no-packages` | 不调用 pacman |
| `--no-wvkbd` | 跳过构建（构建完成前键盘不可用） |
| `--dry-run` | 只预览，不改任何东西 |
| `--verify` | 安装后只读自检 |
| `--clean-legacy` | 清掉已被取代的 full 插件残留（它的 `texp-*` helper、约 90 MB 手写模型、已禁用的 hypr 文件） |

所有写入都在 `$HOME` 内；`wtype` 已装时不需要 sudo。
每个被修改的文件都会先备份成 `*.bak.<时间戳>`。

**重载一次 shell**（或重新登录）让插件重新加载，然后运行
`install.sh --verify`。

## 使用

| 操作 | 方式 |
|---|---|
| 开关虚拟键盘 | `SUPER+U` · 状态栏 **⌨** · `omarchy-shell maxt.tablet-lite keyboardToggle` |
| 收起键盘 | 键盘上的 **▼** 键 |
| 旋转 90° | `SUPER+SHIFT+R` · 状态栏 **⟳** · `omarchy-shell maxt.tablet-lite rotationNext` |
| 传感器自动旋转 | 状态栏 **🧭** · `omarchy-shell maxt.tablet-lite autoRotateToggle` |
| 指定角度 | `omarchy-shell maxt.tablet-lite setRotation 0|1|2|3|auto` |
| 竖屏状态栏 | 四个图标折叠成一个**平板按钮** → 弹窗里选键盘 / 语音 / 旋转 / 自动 |
| 锁屏键盘 | 锁屏自动升起；密码框右侧浮动 **⌨** 按钮可重调；**▼** 收起 |
| 开/关语音浮层 | 状态栏 **🎤** · `omarchy-shell maxt.tablet-lite voiceInputToggle` |
| 说话输入 | 按住大麦克风，松开转写 |
| 修正文本 | **Delete**（退格）/ **Clear**（全选删除；终端里是 readline `Ctrl+A`+`Ctrl+K`）/ **Enter** |
| 移动光标 | 左侧 **← → ↑ ↓** |
| Agent 按键（pi / codex） | **CLI keys ▲** → `esc` `/` `tab` `⇧tab` `⌃C` `⌃D` `⌃J` `⌃T` |

IPC：`getState` · `voiceInputToggle|Show|Hide` ·
`keyboardToggle|Show|Hide` · `cliKeysToggle` · `clearNow` ·
`rotationNext|rotateLeft|rotateRight` · `setRotation <auto|0|1|2|3>` ·
`autoRotateToggle` · `setAutoOrient <on|off>`
（`omarchy-shell maxt.tablet-lite <method>`）。

## 卸载

```sh
~/.config/omarchy/plugins/maxt.tablet-lite/uninstall.sh
omarchy plugin remove maxt.tablet-lite
```

helper 都以 `tlit-*` 装进 `~/.local/bin`，刻意与 full 插件的 `texp-*` 分开：
两个插件可以并存，不会互相覆盖对方的键盘 helper。

## 许可

MIT，见 [LICENSE](LICENSE)。由同一作者的 omarchy-tablet-experience 精简而来。
