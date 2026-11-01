# Template<br>
本仓库是个人的OPENWRT编译模板<br>
例子1：红米ax6、ax3600固件编译<br>
例子2：使用https://github.com/armbian/build 编译玩客云 armbian 线刷和卡刷固件<br>
[![build](https://img.shields.io/github/actions/workflow/status/rmoyulong/Template/Armbian.yml)](https://github.com/rmoyulong/Template/actions/workflows/Armbian.yml) [![downloads](https://img.shields.io/github/downloads/rmoyulong/Template/total)](https://github.com/rmoyulong/Template/releases) [![downloads@latest](https://img.shields.io/github/downloads/rmoyulong/Template/latest/total)](https://github.com/rmoyulong/Template/releases/latest)<br>
例子3：使用https://www.kernel.org/ 编译j1900&j1800卡刷debian固件<br>
GPT与MBR镜像启动兼容性对比清单<br>
这份清单结合老主板实测场景整理，能帮你快速判断不同硬件该选哪一个镜像版本，避免启动失败。<br>

1. 核心硬件适配范围对比<br>
表格<br>

2. 启动特性细节对比<br>
‌MBR镜像专属优势‌<br>
完全兼容2012年之前发布的所有纯传统BIOS主板，没有任何固件识别门槛分区结构简单，<br>
老主板的BIOS引导代码无需额外校验，几乎不会出现引导中断<br>
对U盘兼容性极强，哪怕是老旧的USB2.0主控U盘也能正常识别启动<br>
‌GPT镜像专属优势‌<br>
自带分区表冗余备份，意外断电后分区表损坏概率远低于MBR<br>
支持最多128个主分区，后续扩展分区更灵活，无需创建扩展分区<br>
原生适配UEFI安全启动、快速启动特性，在新主板上引导速度比MBR快30%以上<br>
支持大于2TB的系统盘，不会出现大容量硬盘容量浪费的问题<br>
3. 快速选型决策指南<br>
手里是2013年之前的老主板、Bay Trail小主机，优先选‌MBR兼容版镜像‌，100%能启动<br>
手里是2015年之后的新主板、系统盘容量大于2TB，优先选‌GPT版镜像‌，稳定性和扩展性更好<br>
不确定主板类型时，优先用MBR镜像做启动U盘，它的向下兼容性是最好的，几乎不会出现完全无法引导的情况<br>
