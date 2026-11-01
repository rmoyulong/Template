# Template

本仓库是个人的 OPENWRT 编译模板。

[![build](https://img.shields.io/github/actions/workflow/status/rmoyulong/Template/Armbian.yml){target="_blank"}](https://github.com/rmoyulong/Template/actions/workflows/Armbian.yml)
[![downloads](https://img.shields.io/github/downloads/rmoyulong/Template/total){target="_blank"}](https://github.com/rmoyulong/Template/releases)
[![downloads@latest](https://img.shields.io/github/downloads/rmoyulong/Template/latest/total){target="_blank"}](https://github.com/rmoyulong/Template/releases/latest)

## 编译示例

- &zwnj;**例子 1**&zwnj;：红米 ax6、ax3600 固件编译
- &zwnj;**例子 2**&zwnj;：使用 [armbian/build](https://github.com/armbian/build){target="_blank"} 编译玩客云 armbian 线刷和卡刷固件
- &zwnj;**例子 3**&zwnj;：使用 [kernel.org](https://www.kernel.org/){target="_blank"} 编译 j1900 & j1800 卡刷 debian 固件

## GPT 与 MBR 镜像启动兼容性对比清单

这份清单结合老主板实测场景整理，能帮你快速判断不同硬件该选哪一个镜像版本，避免启动失败。

### 1. 核心硬件适配范围对比

| 硬件类型 | MBR 兼容版 | GPT 版 |
| :--- | :--- | :--- |
| 纯 Legacy BIOS 老主板 | ✅ 完美支持 | ❌ 多数无法识别 GPT |
| Bay Trail 32位 UEFI | ✅ 原生适配 | ✅ 支持，个别固件偶发失败 |
| 64位 UEFI 新主板 | ✅ 可用 CSM 启动 | ✅ 原生启动更快 |
| 大于 2TB 硬盘 | ❌ 仅能用前 2TB | ✅ 无容量上限 |

### 2. 启动特性细节对比

&zwnj;**MBR 镜像专属优势**&zwnj;

- 完全兼容 2012 年之前发布的所有纯传统 BIOS 主板，没有任何固件识别门槛
- 分区结构简单，老主板的 BIOS 引导代码无需额外校验，几乎不会出现引导中断
- 对 U 盘兼容性极强，哪怕是老旧的 USB2.0 主控 U 盘也能正常识别启动

&zwnj;**GPT 镜像专属优势**&zwnj;

- 自带分区表冗余备份，意外断电后分区表损坏概率远低于 MBR
- 支持最多 128 个主分区，后续扩展分区更灵活，无需创建扩展分区
- 原生适配 UEFI 安全启动、快速启动特性，在新主板上引导速度比 MBR 快 30% 以上
- 支持大于 2TB 的系统盘，不会出现大容量硬盘容量浪费的问题

### 3. 快速选型决策指南

- 手里是 2013 年之前的老主板、Bay Trail 小主机，优先选 &zwnj;**MBR 兼容版镜像**&zwnj;，100% 能启动
- 手里是 2015 年之后的新主板、系统盘容量大于 2TB，优先选 &zwnj;**GPT 版镜像**&zwnj;，稳定性和扩展性更好
- 不确定主板类型时，优先用 MBR 镜像做启动 U 盘，它的向下兼容性是最好的，几乎不会出现完全无法引导的情况
