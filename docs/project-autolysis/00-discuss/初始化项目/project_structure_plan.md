# 规划项目文件结构

日期：2026 年 9 月 24 日。

本文依据本次用户要求、当前工程源码及 Degauss（消磁）原项目源码编写。目录树属于目标规划；只有“本次已实施”列出的内容已落地，其余目录随对应功能开发建立。

## 一、目标与命名规则

AUTOLYSIS（自溶）仍处于初始化及从原项目迁出阶段。新项目需要场景管理、存档、本地化、设置、操作映射等上层能力；交互、道具、玩家数值按照新项目需求重新制作。参考原项目的实际机制，不以复制旧目录作为迁移完成标准。

| 对象 | 规则 | 示例 |
| --- | --- | --- |
| 工程目录 | 小写英文，多词用连字符；序号只在确有顺序意义时使用 | dynamic-footstep-system（动态脚步系统目录）、scene-management（场景管理目录） |
| 工程文件 | 小写英文，多词用下划线，扩展名小写 | footstep_surface_detector.gd（脚步地表探测器脚本）、default_bus_layout.tres（默认音频总线资源） |
| 路径引用 | 与磁盘路径逐字符一致；同步脚本、场景、资源、项目配置和导入索引 | 不依靠操作系统忽略大小写，也不依靠资源标识掩盖错误路径 |
| 类名、节点名 | 按用户本次确认，遵循引擎规范，不套用文件名小写规则 | FootstepSurfaceDetector（脚步地表探测器）、CollisionShape3D（碰撞形状节点） |
| 函数、变量、信号 | 遵循引擎的小写下划线规范 | update_motion（更新移动结果）、sound_played（声音已播放） |
| 外部讨论文档 | 新文档采用小写下划线文件名，正文使用中文标题 | project_structure_plan.md（项目文件结构规划文档） |

本次指定的“初始化项目”中文目录保留。已有中文资料目录和历史证据不批量改名，避免破坏引用。根目录 AGENTS.md（智能体规则文件）是现有工具入口，保持原名；README.md（项目说明文件）的大小写整理列入后续仓库文档整理，当前内容保留。

文件夹使用连字符是本项目用户规则。类名、节点名、函数和变量参照 [Godot（游戏引擎）4.6 脚本风格指南](https://docs.godotengine.org/en/4.6/tutorials/scripting/gdscript/gdscript_styleguide.html#naming-conventions)。

## 二、工程内容与外部资料分离

项目根目录为 [当前工程目录](D:/autolysis)，原项目为 [参考工程目录](D:/cogito)。所有手工维护的运行时代码、场景、资源、界面与工程测试均归入 main-autolysis（工程内容目录）。

根目录只保留工程入口、仓库配置、仓库说明、智能体规则、工程内容目录和外部资料目录。引擎生成的缓存目录与版本管理目录属于工具元数据，不是游戏内容目录。

以下为目标布局示意。括号内容为说明，不属于真实文件名。

```text
autolysis（项目根目录）/
├── project.godot（工程入口配置）
├── readme.md（项目说明，现有大写文件名待整理）
├── AGENTS.md（智能体规则固定入口）
├── .gitignore（版本忽略规则）
├── .git（版本管理元数据）/
├── .godot（引擎生成缓存）/
├── main-autolysis（工程内容）/
│   ├── systems（游戏系统）/
│   ├── player（玩家实体与接入）/
│   ├── components（跨系统通用附加模块）/
│   ├── scenes（启动、关卡与物体装配场景）/
│   ├── ui（用户界面）/
│   ├── assets（跨系统共享资源）/
│   └── tests（跨系统集成测试）/
└── docs（外部文档与证据）/
    ├── .gdignore（引擎目录忽略标记）
    └── project-autolysis（自溶项目资料）/
        └── 00-discuss（讨论记录）/
            └── 初始化项目/
                ├── project_structure_plan.md（本讨论文档）
                └── structure-evidence（本次迁移证据）/
```

文档目录已增加引擎忽略标记，避免历史场景、脚本副本进入工程扫描。可执行测试放在工程内容目录，测试日志、迁移映射、设计讨论放在文档目录；游戏资源不得依赖文档目录。[Godot（游戏引擎）4.6 工程组织说明](https://docs.godotengine.org/en/4.6/tutorials/best_practices/project_organization.html#ignoring-specific-folders)确认，被忽略目录中的资源不能作为正常加载资源使用。

玩家实际存档与用户设置写入引擎用户数据目录，不写回工程资源目录，也不写入讨论文档目录。这里要求集中管理的是工程源文件，不是玩家运行时数据。

## 三、目标功能目录

```text
main-autolysis（工程内容）/
├── systems（游戏系统）/
│   ├── dynamic-footstep-system（动态脚步系统，已迁移）/
│   │   ├── scripts（脚本）/
│   │   ├── footstep-profiles（脚步音效配置）/
│   │   ├── footstep-material-library（脚步材质库）/
│   │   ├── assets（系统专属资源）/
│   │   │   ├── audio（音频）/
│   │   │   └── materials（材质）/
│   │   ├── dynamic_footstep_demo_scene.tscn（动态脚步演示场景）
│   │   └── readme.md（系统说明与来源记录）
│   ├── scene-management（场景管理）/
│   ├── save-system（存档系统）/
│   ├── localization（本地化）/
│   ├── settings（设置）/
│   ├── input-mapping（操作映射）/
│   ├── interaction（交互，重新制作）/
│   ├── items（道具，重新制作）/
│   ├── player-stats（玩家数值，重新制作）/
│   ├── production（制药流程，预留）/
│   ├── orders（上级要求与订单，预留）/
│   └── shipping（药品发送，预留）/
├── player（玩家实体与接入）/
│   ├── autolysis_player.gd（自溶玩家脚本）
│   ├── autolysis_player.tscn（自溶玩家场景）
│   ├── components（玩家专属接入模块）/
│   ├── assets（玩家专属资源）/
│   └── tests（玩家与脚步集成测试）/
├── components（跨系统通用附加模块）/
├── scenes（场景装配）/
│   ├── bootstrap.tscn（启动装配场景，规划）
│   ├── levels（正式关卡）/
│   ├── test-levels（开发测试关卡）/
│   └── prefabs（复用物体场景）/
│       ├── furniture（家具）/
│       ├── items（可放置道具）/
│       ├── machines（器械）/
│       └── raw-materials（原料）/
├── ui（用户界面）/
│   ├── menus（主菜单、暂停及设置界面）/
│   ├── hud（游戏内状态与交互提示）/
│   └── widgets（共享界面控件）/
├── assets（跨系统共享资源）/
│   ├── audio（音频）/
│   │   ├── buses（音频总线，已建立）/
│   │   ├── music（音乐）/
│   │   └── sound-effects（共享音效）/
│   ├── materials（共享材质）/
│   ├── textures（共享贴图）/
│   ├── models（共享模型）/
│   ├── fonts（共享字体）/
│   └── shaders（共享着色器）/
└── tests（跨系统集成测试）/
```

制药、订单、发送三个预留目录只对应已确认的游戏描述，不代表配方、任务条件、运输方式或失败规则已经确定。仅在对应需求进入实施时建目录和文件。

### 文件归属原则

1. 一个功能的脚本、专属资源和专属测试优先就近放置。小系统不强制建立空的脚本、场景、资源三级目录；文件增加后再分层。
2. 只有多个系统实际共享的资源进入公共资源目录。脚步音效归脚步系统；设置界面归界面目录，设置读写与应用逻辑归设置系统。
3. 玩家目录负责移动、视角、碰撞和各系统的玩家侧接入，不积累全局存档、菜单或道具规则。
4. 交互系统持有交互规则与物体交互入口；玩家侧检测与输入接入留在玩家目录。已有交互代码是新系统的实施起点，不重复建立另一套平行入口。
5. 道具系统持有道具规则与数据定义；物体装配场景持有具体模型、碰撞和挂载关系。玩家数值系统持有数值状态与变化规则，玩家实体负责接入。
6. 通用附加模块目录仅接收已经跨系统复用的内容，不因为暂时难以分类就放入其中。系统内的实现细节不要求其他系统直接读取私有字段。

## 四、五类上层系统的参考与取舍

以下目录均位于工程内容目录中的 systems（游戏系统目录）下。表中职责是本项目规划；原项目行为由链接对应源码证明。

| 系统目录 | 本项目规划职责 | 原项目实际依据 | 迁移时需要处理的依赖 |
| --- | --- | --- | --- |
| scene-management（场景管理） | 场景装载、切换、加载过渡、连接点定位；协调恢复时机 | [原场景切换](D:/cogito/addons/cogito/SceneManagement/cogito_scene_manager.gd:437)、[原加载界面](D:/cogito/addons/cogito/SceneManagement/loading_screen.gd:16)、[原场景入口](D:/cogito/addons/cogito/SceneManagement/cogito_scene.gd:15) | 原场景管理器兼管存档，并读取旧玩家身体节点；新项目应拆开状态读写与场景切换 |
| save-system（存档系统） | 存档槽、文件读写、临时场景快照、状态恢复；规划数据版本字段 | [原场景状态资源](D:/cogito/addons/cogito/SceneManagement/cogito_scene_state.gd:26)、[原玩家状态资源保存](D:/cogito/addons/cogito/SceneManagement/cogito_player_state.gd:184)、[原检查点调用](D:/cogito/main-degauss/scripts/save_checkpoint_zone.gd:66) | 不直接复制旧玩家状态类型；新交互、道具、玩家数值分别提供需要保存与恢复的状态 |
| localization（本地化） | 翻译资源、语言选择、语言偏好启动应用 | [原翻译资源登记](D:/cogito/project.godot:265)、[原语言选择初始化](D:/cogito/addons/cogito/Localization/scripts/language_select.gd:12)、[原语言切换与配置](D:/cogito/addons/cogito/Localization/scripts/language_select.gd:68) | 原项目由语言控件初始化时应用语言；新项目语言初始化应独立于设置界面是否打开 |
| settings（设置） | 默认值、配置读取与保存、画面音频及玩家操作偏好的应用 | [原设置路径常量](D:/cogito/addons/cogito/EasyMenus/Scripts/options_constants.gd:6)、[原设置保存](D:/cogito/addons/cogito/EasyMenus/Scripts/OptionsTabMenu.gd:293)、[原启动加载](D:/cogito/addons/cogito/EasyMenus/Scripts/startup_loader.gd:53) | 区分玩家偏好与开发者项目配置；界面负责显示和提交，持久化与启动应用不依赖界面类 |
| input-mapping（操作映射） | 已确认动作的默认绑定、重绑定、序列化、恢复、输入设备变化 | [原映射序列化](D:/cogito/addons/input_helper/input_helper.gd:255)、[原映射恢复](D:/cogito/addons/input_helper/input_helper.gd:293)、[原重绑定界面](D:/cogito/addons/cogito/EasyMenus/Scripts/OptionsTabMenu.gd:497) | 原默认绑定串位于设置界面类；新项目由操作映射系统维护默认绑定，仅加入新项目已确认动作 |

原项目实际自动加载入口见 [原项目自动加载配置](D:/cogito/project.godot:28)。当前新项目的 [工程配置](D:/autolysis/project.godot:11)尚未注册上述五类上层系统；目标目录不等于已经实现或已经接入。

原 [全局配置入口](D:/cogito/addons/cogito/cogito_globals.gd:4)及 [框架设置资源](D:/cogito/addons/cogito/cogito_settings.gd:10)包含新游戏场景、初始世界状态及存档前缀等开发配置。这类数据应由拥有相应职责的系统维护，不能与玩家可调整的音量、画质等配置混为一份任意全局字典。

### 旧玩法依赖不能直接带入

- 原 [玩家恢复流程](D:/cogito/addons/cogito/SceneManagement/cogito_scene_manager.gd:125)直接恢复旧背包与快捷栏；同文件第 153、201 行附近继续恢复道具充能、玩家属性和旧交互状态。
- 原 [玩家保存流程](D:/cogito/addons/cogito/SceneManagement/cogito_scene_manager.gd:215)读取旧背包、快捷栏、任务、道具、属性和交互组件。[原玩家状态定义](D:/cogito/addons/cogito/SceneManagement/cogito_player_state.gd:6)直接声明旧背包与槽位类型。
- 原 [场景对象保存](D:/cogito/addons/cogito/SceneManagement/cogito_scene_manager.gd:386)按持久化分组收集对象，调用其保存方法。可以参考收集流程，但持久化标识、字段和恢复契约需要按新对象重新确定。
- 原 [全局仓库](D:/cogito/main-degauss/scripts/degauss_stash_manager.gd:39)将旧背包写入场景管理器世界字典，不能因为它位于全局层就直接迁入。
- 原 [启动按键加载](D:/cogito/addons/cogito/EasyMenus/Scripts/startup_loader.gd:65)读取设置界面类中的默认绑定；原 [动作清单](D:/cogito/addons/cogito/EasyMenus/Scripts/OptionsTabMenu.gd:85)包含战斗、快捷栏及旧背包动作，不能自动转化为新项目需求。

任务、频率、战斗音乐等原项目自动加载内容，目前不属于已确认的迁移清单。游戏中的上级要求也不等于必须照搬旧任务系统。

## 五、三个重新制作系统与启动顺序

| 系统 | 已确认现状 | 后续结构安排 |
| --- | --- | --- |
| 交互 | 已有 [物体交互入口](D:/autolysis/main-autolysis/components/interactions/autolysis_interaction_component.gd:1)和 [玩家交互控制器](D:/autolysis/main-autolysis/player/components/autolysis_interaction_controller.gd:1)；不能描述为尚无实现 | 在现有成果上继续开发；物体交互入口后续归入交互系统，玩家接入保留在玩家目录；同步场景与测试引用 |
| 道具 | 当前已有道具与原料的装配场景，本次未核实出独立的新道具规则系统 | 先确定新道具的数据、行为和持有方式，再实现；场景存在不代表旧背包或旧槽位规则适用 |
| 玩家数值 | 当前玩家脚本保留移动、视角等行为；用户明确要求玩家数值重新制作 | 先确定具体数值及变化规则，再接入玩家和存档；不预设生命、体力等旧字段必然存在 |

建议启动顺序如下，属于后续实施安排：

1. 读取设置并应用启动所需的窗口、画质、音频偏好。
2. 注册本项目动作默认绑定，再应用用户保存的绑定；按语言偏好或约定默认语言应用本地化。
3. 初始化存档访问能力和场景切换能力，再进入主菜单或目标关卡。
4. 关卡与玩家完成装配后，由各新系统按确定的顺序恢复状态，最后开放操作。

是否使用自动加载由实际生命周期决定。需要跨场景存在的入口可以自动加载；交互组件、物体实例和玩家数值实例不因为放在系统目录就自动变成单例。数据格式、接口名称、失败恢复规则及旧存档兼容要求，留待对应功能讨论确定。

## 六、本次已实施的迁移

动态脚步系统已迁入 [脚步系统目录](D:/autolysis/main-autolysis/systems/dynamic-footstep-system)。

| 原名称或归属 | 当前名称或归属 |
| --- | --- |
| DynamicFootstepSystem（原动态脚步目录） | dynamic-footstep-system（动态脚步系统目录），位于工程系统目录下 |
| Scripts（原脚本目录） | scripts（脚本目录） |
| FootstepProfiles（原脚步配置目录） | footstep-profiles（脚步配置目录） |
| FootstepMaterialLibrary（原脚步材质库目录） | footstep-material-library（脚步材质库目录） |
| Assets（原资源目录）、Audio（原音频目录）、Materials（原材质目录） | assets（资源目录）、audio（音频目录）、materials（材质目录）；音频分类目录均改为小写 |
| DynamicFootstepDemoScene.tscn（原动态脚步演示场景） | dynamic_footstep_demo_scene.tscn（动态脚步演示场景） |
| footstep_Grass-01.ogg（原草地脚步音频示例） | footstep_grass_01.ogg（草地脚步音频示例） |
| Prototype_DarkGrey.tres（原深灰原型材质） | prototype_dark_grey.tres（深灰原型材质） |
| 公共音效目录中的金属脚步音频 | 15 个被脚步配置实际引用的音频及其导入文件归入脚步系统的金属音频目录，文件名和扩展名规范为小写 |
| 根目录 default_bus_layout.tres（默认音频总线资源） | 迁入 [工程音频总线目录](D:/autolysis/main-autolysis/assets/audio/buses/default_bus_layout.tres)，并在 [项目音频配置](D:/autolysis/project.godot:17)显式登记 |

本次迁移清单共 100 个文件，包含导入文件和脚本标识文件。完整逐文件映射及迁移前内容哈希见 [路径映射证据](D:/autolysis/docs/project-autolysis/00-discuss/初始化项目/structure-evidence/path_mapping.json)。

脚步算法、类名、节点名和信号保持原有实现。脚本标识随脚本移动，音频导入配置保留原标识及参数，导入缓存由引擎重新生成。玩家场景、默认场景、脚步配置、材质库、演示场景和脚步测试均已更新实际路径。

当前默认场景仍将脚步配置附加在原碰撞形状上，未增加地面配置节点；实际结构见 [默认场景](D:/autolysis/main-autolysis/scenes/01-autolysis-test.tscn:398)，验证入口见 [脚步回归脚本](D:/autolysis/main-autolysis/player/tests/footstep_smoke_test.gd:135)。

默认音频总线路径可通过项目设置指定，依据 [Godot（游戏引擎）4.6 音频总线配置](https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html#class-projectsettings-property-audio-buses-default-bus-layout)。本次迁移保持原总线内容，仅改变资源位置与配置引用。

历史讨论中的旧路径是当时的证据，不批量替换。当前路径以本次映射、实际工程文件和本次验证结果为准。

## 七、后续目录整理顺序

下列是当前已发现但尚未执行的其他命名与归属调整，不能据本次脚步迁移宣称全工程已经符合新规范。

| 现有内容 | 目标安排 | 调整时需要同步 |
| --- | --- | --- |
| 01-autolysis-test.tscn（当前测试场景） | 移入测试关卡目录，文件名改为 autolysis_test.tscn（自溶测试场景） | 默认场景配置、测试加载路径、场景引用与文档索引 |
| prefab_furnitures（原家具目录）、prefab_items（原道具目录）、prefab_machines（原器械目录）、prefab_raw_materials（原原料目录） | 按目标树改为简短的家具、道具、器械及原料分类目录 | 所有场景外部资源路径 |
| sound_fx（原共享音效目录）、lfs_radio（原电台音频目录）、lock_and_switch（原锁与开关目录）等 | 逐项调整为小写连字符目录；确认内容后再决定是否继续作为共享资源 | 音频导入源路径、场景与资源引用 |
| base_color（原基础颜色目录）、glow_color（原发光颜色目录） | base-color（基础颜色目录）、glow-color（发光颜色目录） | 材质引用 |
| Prototype Textures（原原型贴图目录）及其大写子目录 | prototype-textures（原型贴图目录）及小写分类 | 材质贴图路径、导入配置 |
| 其余大写音频文件名、大写扩展名 | 按实际用途改为小写下划线文件名 | 全部引用及导入文件；不复制资源形成双份 |
| 当前位于通用附加模块目录中的交互入口 | 后续归入交互系统；玩家侧接入保留原职责 | 脚本路径、类索引、装配场景、现有交互测试 |
| 当前直接位于界面目录的准星 | 后续归入游戏内界面分类 | 玩家场景挂载路径与交互验证 |

建议先完成剩余目录命名整理，再逐项迁移上层能力。每批迁移保持当前默认场景可启动；在上层存档接入前先确定三个新系统的状态契约，避免为了兼容旧保存代码而复建旧玩法。

每批调整都需：保留迁移清单与资源标识；更新所有有效引用；让引擎完成导入；检查不存在依赖旧路径的加载；运行受影响的现有测试。已有历史日志不当作本次验证结果。

## 八、本次验收与证据

本节由本次实际命令结果填写；完整命令参数、退出码及标准输出保存在 [迁移证据目录](D:/autolysis/docs/project-autolysis/00-discuss/初始化项目/structure-evidence)。

- 迁移前：工程导入无引擎错误；脚步冒烟测试通过 25 项。
- 迁移后：工程导入无引擎错误；脚步冒烟测试通过 25 项。
- 玩家回归测试通过 20 项；默认场景启动并运行 180 帧，无引擎错误。
- 独立静态审查通过：100 项迁移目标存在且旧位置已移除；脚步目录内 99 个文件、12 个子目录符合命名规则；36 个音频、4 个脚本、4 个脚本标识文件与迁移前哈希一致。
- 55 个场景、资源及导入文件的资源标识保持一致；166 处资源路径存在且大小写匹配；108 处外部资源标识与目标匹配；290 个有效工程文本文件中没有迁移清单旧资源路径残留。详细检查与命令见本目录证据。

| 验证项目 | 实际结果记录 |
| --- | --- |
| 迁移前导入与脚步基线 | [导入结果](D:/autolysis/docs/project-autolysis/00-discuss/初始化项目/structure-evidence/baseline_import.json)、[脚步基线结果](D:/autolysis/docs/project-autolysis/00-discuss/初始化项目/structure-evidence/baseline_footstep.json) |
| 迁移后导入与脚步回归 | [导入结果](D:/autolysis/docs/project-autolysis/00-discuss/初始化项目/structure-evidence/final_import.json)、[脚步结果](D:/autolysis/docs/project-autolysis/00-discuss/初始化项目/structure-evidence/final_footstep.json) |
| 玩家回归与默认场景启动 | [玩家结果](D:/autolysis/docs/project-autolysis/00-discuss/初始化项目/structure-evidence/final_player.json)、[默认场景结果](D:/autolysis/docs/project-autolysis/00-discuss/初始化项目/structure-evidence/final_main_scene.json) |
| 命名、路径、标识及内容一致性 | [静态检查结果](D:/autolysis/docs/project-autolysis/00-discuss/初始化项目/structure-evidence/static_verification.json)、[静态检查命令](D:/autolysis/docs/project-autolysis/00-discuss/初始化项目/structure-evidence/static_verification_commands.txt) |

测试采用指定的 Godot（游戏引擎）4.6.1 可执行文件。脚步测试使用每秒 60 帧的固定步进，无界面模式不验证扬声器实际输出；本次验证针对迁移后的加载、逻辑和资源引用。
