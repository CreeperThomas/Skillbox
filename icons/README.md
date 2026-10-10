# Skillbox 图标

## kept/ — 保留的候选稿

这四张是用本地 dsh-image-gen 网关（模型 `gpt-image-2`）生成的候选，尺寸均为 1254×1254 PNG。

| 文件 | 结构 | S 的形态 | 说明 |
|---|---|---|---|
| `D-original.png` | 三层扇形错位（青绿 / 象牙 / 石墨） | 深色凹槽切口，象牙色 S | **当前应用图标**，Dock 小尺寸对比最强 |
| `R5-E1-plus-D.png` | 三层扇形（靛蓝 / 蓝灰 / 银白） | 青绿 | 结构正确，但 S 反色（青绿是底色块、S 是白色），仅作存档 |
| `R6-E1D-raised-teal-S.png` | 三层扇形（靛蓝 / 蓝灰 / 银白） | 浮起的圆润青绿 S | S 反色问题已修正，小尺寸偏亮 |
| `amber.png` | 三层扇形（靛蓝 / 蓝灰 / 银白） | 浮起的圆润琥珀金 S | 五色对比中 Dock 辨识度最高 |

## 生成方式

这些图**不是**手绘 SVG，而是通过 dsh-image-gen 插件的 `image-service.js` 调用配置的 OpenAI 兼容生图网关生成的。

运行中的 DSH 会话会在插件加载时缓存一次配置，因此若 `~/.dsh/dsh-image-gen.json` 是在会话启动之后写入的，聊天里的 `dsh_image_gen` 工具会报“未配置”。重启 DSH 即可，或临时绕过：

```bash
node build/gen-icons-batch.mjs build/icon-jobs-*.json
```

## 应用图标

`AppIcon.icns` 由 `scripts/make-icon.sh` 从选定稿生成：裁到主体、按 macOS 圆角遮罩、留透明边距，导出完整尺寸族后打包。
