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
  `omarchy-shell maxt.tablet-lite keyboardToggle`。没有 lite 构建时回退到
  `squeekboard`。
- **语音输入** —— 状态栏 **🎤** 按钮打开底部的按住说话浮层。按住开始录音，
  松开后本地转写，用 `wtype` 打进当前光标处（终端和各种 toolkit 都支持中文）。
  **Delete / Clear / Enter** 修正或提交这一行；左侧 **← → ↑ ↓** 移动光标；
  展开 **CLI keys** 网格可发送 `esc` `/` `tab` `⇧tab` `⌃C` `⌃D` `⌃J` `⌃T`，
  方便在纯触屏上操作 pi / codex CLI。
- 语音和键盘**互斥**：打开一个会自动关掉另一个。
- **CLI keys + 光标板也会跟着键盘走**，停在真实 wvkbd 面板上方，手打时
  `esc` / `⌃C` 仍然够得着。
- **屏幕旋转** —— 状态栏 **⟳** 按钮和 **`SUPER+SHIFT+R`** 在 0° / 90° /
  180° / 270° 之间旋转。左键点图标 = 下一个 90°，右键 = 开关**传感器自动旋转**
  （`texp-orient` 读 sysfs 加速度计，按 ThinkPad X12 校准）。每次旋转都会
  **保留当前缩放**并同步 Hyprland 的**触摸校准矩阵**（`texp-rotate`），
  最后一个角度会持久化，shell 重启不会悄悄转回横屏。

有意去掉：笔记本/平板状态机、键盘自动切换、手写、窗口管理、状态栏精简、
多点触控手势、锁屏/登录屏集成。

## 依赖

- Omarchy 4.x（Quickshell）+ Hyprland 0.56+（Lua 配置 API），Arch 系。
- 语音需要 `wtype` 和 **voxtype**（AUR：`voxtype-bin`）。
- 自动旋转需要 `python3` 和可读的 IIO 加速度计（`texp-orient` 直读 sysfs，
  不需要额外的守护进程）。
- `squeekboard`（回退键盘）；编译 wvkbd 需要 `cairo pango wayland
  libxkbcommon`（多数 Omarchy 装机已有）。
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
| `--no-wvkbd` | 跳过构建，直接用 squeekboard 回退 |
| `--dry-run` | 只预览，不改任何东西 |
| `--verify` | 安装后只读自检 |

所有写入都在 `$HOME` 内；`squeekboard` 和 `wtype` 已装时不需要 sudo。
每个被修改的文件都会先备份成 `*.bak.<时间戳>`。

**重载一次 shell**（或重新登录）让插件重新加载，然后运行
`install.sh --verify`。

## 使用

| 操作 | 方式 |
|---|---|
| 开关虚拟键盘 | `SUPER+U` · 状态栏 **⌨** · `omarchy-shell maxt.tablet-lite keyboardToggle` |
| 收起键盘 | 键盘上的 **▼** 键 |
| 旋转 90° | `SUPER+SHIFT+R` · 状态栏 **⟳** 左键 · `omarchy-shell maxt.tablet-lite rotationNext` |
| 传感器自动旋转 | 状态栏 **⟳** 右键 · `omarchy-shell maxt.tablet-lite autoRotateToggle` |
| 指定角度 | `omarchy-shell maxt.tablet-lite setRotation 0|1|2|3|auto` |
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

## 许可

MIT，见 [LICENSE](LICENSE)。由同一作者的 omarchy-tablet-experience 精简而来。
