# Template<br>
本仓库是个人的OPENWRT编译模板<br>
例子1：红米ax6、ax3600固件编译<br>
例子2：使用https://github.com/armbian/build 编译玩客云 armbian 线刷和卡刷固件<br>
[![build](https://img.shields.io/github/actions/workflow/status/rmoyulong/Template/Armbian.yml)](https://github.com/rmoyulong/Template/actions/workflows/Armbian.yml) [![downloads](https://img.shields.io/github/downloads/rmoyulong/Template/total)](https://github.com/rmoyulong/Template/releases) [![downloads@latest](https://img.shields.io/github/downloads/rmoyulong/Template/latest/total)](https://github.com/rmoyulong/Template/releases/latest)<br>
例子3：使用https://www.kernel.org/ 编译j1900&j1800卡刷debian固件<br>
GPT与MBR镜像启动兼容性对比清单<br>
这份清单结合老主板实测场景整理，能帮你快速判断不同硬件该选哪一个镜像版本，避免启动失败。<br>

| 硬件类型 | MBR 兼容版 | GPT 版 |
| :--- | :--- | :--- |
| 纯 Legacy BIOS 老主板 | ✅ 完美支持 | ❌ 多数无法识别 GPT |
| Bay Trail 32位 UEFI | ✅ 原生适配 | ✅ 支持，个别固件偶发失败 |
| 64位 UEFI 新主板 | ✅ 可用 CSM 启动 | ✅ 原生启动更快 |
| 大于 2TB 硬盘 | ❌ 仅能用前 2TB | ✅ 无容量上限 |


