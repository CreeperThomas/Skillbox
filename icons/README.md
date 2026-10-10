# Skillbox 图标

## selected.png — 当前应用图标源

`icons/selected.png` 是构建 `.icns` 的唯一来源，当前为 `kept/G2-indigo-violet-plate.png`。

换图标只需两步：

```bash
cp icons/kept/<你选的>.png icons/selected.png
make icon && make app
```

## kept/ — 保留的候选稿

都是本地 dsh-image-gen 网关（模型 `gpt-image-2`）生成的候选，1254×1254 PNG。

| 文件 | 底板 | S 的形态 | 说明 |
|---|---|---|---|
| **G2-indigo-violet-plate.png** | 靛蓝→紫渐变，满幅 | 前片深石墨 + 象牙色切口 | **当前图标**，有明确色彩身份，暗色 Dock 里不发白 |
| G1-indigo-teal-plate.png | 靛蓝→青绿渐变，满幅 | 同上 | 更亮更抢眼，饱和度高 |
| D-original.png | 近白 `#fbfbfb` | 同上 | 三层扇形概念稿；**白底在 Dock 里显得空**，已弃用为图标 |
| R5-E1-plus-D.png | 近白 | 青绿 | 结构对，但 S 反色（青绿是底、S 是白），仅存档 |
| R6-E1D-raised-teal-S.png | 近白 | 浮起圆润青绿 S | 修正了反色，小尺寸偏亮 |
| amber.png | 近白 | 浮起圆润琥珀金 S | 五色对比中 Dock 辨识度最高，但同样有白底问题 |

## 构建流程

`scripts/make-icon.sh` 负责把选定的方图变成合法 macOS 图标：

1. 以图角像素为背景色，检测主体范围；
2. 按 `ICON_MARGIN`（默认 1.03）留白裁切，避免四周空旷；
3. 套用系统连续圆角遮罩（圆角 = 边长 22.37%，4 倍超采样抗锯齿）；
4. 居中放在 1024×1024 画布，四周留透明边距；
5. 用 `iconutil` 打包 16 → 1024 共 10 个尺寸。

`make-app.sh` 会把 `AppIcon.icns` 放进 `Contents/Resources/` 并设置
`CFBundleIconFile` / `CFBundleIconName`。

## 重新生成候选

提示词全部保存在 `icons/prompts/`（每个候选一份 txt），批量生成脚本在 `scripts/icongen/`：

```bash
# 先写一份任务清单，格式见 scripts/icongen/jobs.example.json
node scripts/icongen/generate-icons.mjs my-jobs.json
```

脚本直接调用已安装的 dsh-image-gen 插件自身的 `image-service.js`，网关、模型、输出目录都与 DSH 内置工具一致。之所以需要它：**DSH 会话在插件加载时只解析一次配置**，若 `~/.dsh/dsh-image-gen.json` 是在会话启动之后写入的，聊天里的 `dsh_image_gen` 会一直报“未配置”——重启 DSH 即可，或用它绕过。

## 排错记录

生成过程中遇到并修掉的两个问题，留在这里避免重复踩：

- **S 的主色反转**：提示词里写 `inlaid / recessed groove`（嵌入凹槽）时，模型会把**凹槽**涂成彩色、把**字母**当成面板材料，得到"彩色块 + 白色 S"。改成"一块浮在面板上的彩色实体"即可稳定出正确结果。
- **近白底板**：模型输出带白色背景时，整张白底会变成图标面板，在暗色 Dock 里显得空旷。解决方式是让模型直接生成**满幅渐变底板**，而不是靠事后抠图——象牙色玻璃片本身接近白色，程序无法与背景白可靠分离（尝试过，会产生方块状残留）。
