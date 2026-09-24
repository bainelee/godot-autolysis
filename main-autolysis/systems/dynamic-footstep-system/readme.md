# 动态脚步系统

本目录由原 DynamicFootstepSystem（动态脚步系统）迁入，原作者署名为 AC-Arcana（原作者署名），原说明面向 COGITO（原框架）。当前版本供 AUTOLYSIS（自溶）玩家使用。

## 文件归属

- scripts（脚本目录）：地表探测、地面配置、材质库及材质映射资源脚本。
- footstep-profiles（脚步配置目录）：七种脚步随机音频配置。
- footstep-material-library（脚步材质库目录）：示例材质与脚步配置的映射。
- assets（资源目录）：本系统使用的音频与示例材质。
- dynamic_footstep_demo_scene.tscn（动态脚步演示场景）：地面配置与材质映射示例。

文件夹采用小写字母与连字符，文件采用小写字母与下划线。类名和节点名遵循引擎规范。

## 当前接入方式

玩家场景挂载 FootstepSurfaceDetector（脚步地表探测器），由玩家完成移动后调用 update_motion（更新移动结果）方法，传入着地、速度、步态、蹲伏、冲刺及暂停结果。

地面配置继续直接附加在 CollisionShape3D（碰撞形状节点）上，不需要增加额外的地面配置子节点。探测器优先读取显式地面配置，再查询材质映射；材质未匹配时使用默认音效配置。

FootstepMaterialLibrary（脚步材质库）通过 FootstepMaterialProfile（脚步材质映射配置）关联材质与音效。脚步配置使用 AudioStreamRandomizer（随机音频流），可设置多个音频、选择权重、音调及音量随机范围。

迁移验证继续使用玩家测试目录中的 footstep_smoke_test.gd（脚步冒烟测试脚本），覆盖步态、落地、材质映射、地面配置、音频资源加载和演示场景加载。

## 来源记录

原随附说明将下列四组音效标注为 CC0（公共领域贡献许可），并给出以下来源。本次保留该来源记录，不将此声明扩展到新增归入本目录的金属音效。

- 泥土：[原始音效页面](https://freesound.org/people/HenKonen/sounds/682127/)。
- 草地：[原始音效页面](https://freesound.org/people/HenKonen/sounds/682128/)。
- 石质：[原始音效页面](https://freesound.org/people/xmike80x/sounds/706207/)。
- 木质：[原始音效页面](https://freesound.org/people/SpliceSound/sounds/150444/)。

通用音效沿用原目录资源。金属音效来自本工程迁移前已有的公共脚步音频目录；这里只调整文件归属和命名，不新增许可声明。
