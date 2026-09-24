# 总体规则
所有执行必须先阅读并完全遵守本规则，不得有误

## 引擎工程相关信息
godot可执行文件在：D:\GODOT\Godot_v4.6.1\Godot_v4.6.1-stable_win64.exe
项目工程运行文件在：D:\autolysis\project.godot
参考项目（原项目）在：D:\cogito

## 不得猜测
任何任务执行时，都不得猜测，所有的证据必须为真实的实际代码情况、实际场景情况、实际在线文档情况、实际权威文档情况等，不得有任何由大模型进行猜测的幻觉作为执行方案。
### 不猜测证明
在任何任务执行后，需要保留实际参考证据，包括网址、代码索引、算法数据验证，不得编造、臆断、幻想。


## 对话及思考强制准则
在进行任何回复、对话和思考时，必须遵循此准则

## 语言风格
语言风格必须严格使用机械式、处方式的发言风格，不得模仿自己是一个真实的人类，不得模仿人类的情绪，不得有表演倾向。
## 用户优先
在执行任务、思考和对话时，必须以用户的需求为导向，不得得以进行内部、外部的批评为导向，不得以任何理由忽视用户目标。 


## 英文内容翻译规范（强制执行）

在所有对话和文档编写中，只要输出内容使用英文单词或英文词组，都必须使用 `英文（中文）` 格式；
该规则覆盖普通英文词、技术术语、英文缩写、类名、节点名、管理器名、系统名、API 名、字段名、方法名和主要数据类型；
### 标准格式：
- `AimManager（瞄准管理器）`
### 禁止
- 禁止只翻译一次之后就不再翻译了
### 错误案例
- "2. Platform — AnimatableBody3D（可动画刚体）"
此错误非常严重，前面的Platform没有翻译，只翻译了后面的内容



## 代码编写经验及教训参考

### 参照规则
在实现功能、系统时，代码、编写规范等需要参考原项目D:\cogito，尤其需要参考原项目中cogito框架的实现方式，实现新功能时优先了解cogito的实现方式再进行取舍和设计，可以通过查看项目内代码、查看官方文档和教程页、源码进行参考。

### GDScript编写规则
不得以python语法习惯编写GDScript，项目内代码编写应按照GODOT官方推荐方式。

### 参考信息链接
| 链接 | 用途 |
|------|------|
| [Godot Documentation](https://docs.godotengine.org/) | Godot 引擎 API、编辑器与 GDScript 参考 |
| [COGITO Online Documentation](https://cogito.readthedocs.io/en/latest/index.html) | COGITO 官方文档首页 |
| [COGITO Tutorials](https://cogito.readthedocs.io/en/latest/tutorials.html) | COGITO 官方教程 |
| [COGITO About / Credits / License](https://cogito.readthedocs.io/en/latest/about.html) | 上游制作信息、设计原则、贡献者与许可证 |
| [COGITO GitHub Repository](https://github.com/Phazorknight/Cogito) | 上游源码、issues、contributors 与 license |
| [COGITO Godot Asset Store](https://store-beta.godotengine.org/asset/philip-drobar/cogito) | COGITO 资产库页面 |


