# Swift RVC Mac Client 功能总览 DSL

## 1. 项目定位

- 定位：面向桌面端语音转换场景的 Swift RVC Mac Client，以“音频变声”和“实时变声”为两条主功能主线。
- 阅读方式：本文不按源码目录解释，而是按当前界面中用户实际能看到和能点击的字段、按钮、状态栏来说明。
- 主界面分层：
  - 顶部动作区：`BOOT`、`SYNC`、`AUDIO`、`RUN/STOP` 等全局动作。
  - 左侧 Patch Bay：`VOICE MODEL`、`SPEAKER ID`、`F0 METHOD`。
  - 下方共享控制区：`PARAM BANK`、`INDEX FILE`、离线参数推子与操作按钮。
  - 实时路由区：`HOST`、`INPUT`、`OUTPUT`、`MON`。
  - `REALTIME LAB`：实时专属参数。
  - 主内容区：`Single Convert`、`Batch Convert`、`Models` 等视图。
- 导航结构：
  - `Engine`：运行状态、端口、诊断与引擎控制。
  - `Models`：模型目录、索引目录、当前模型摘要。
  - `Single Convert`：单文件离线变声。
  - `Batch Convert`：批量离线变声。
- 页面切换规则：
  - 切到 `Single Convert` 时，`PARAM BANK` 默认回到 `single`。
  - 切到 `Batch Convert` 时，`PARAM BANK` 默认回到 `batch`。
  - 切到 `Models` 或 `Engine` 不会改变当前已加载模型、共享索引或实时运行状态。
- 核心能力：围绕已加载模型完成离线文件变声，或围绕设备路由完成实时变声，并通过共享的模型、索引、speaker 与参数控制面保持操作一致性。
- 主要输出：离线转换后的音频文件或输出目录；实时路径中的设备级变声流与状态回读。
- 边界：本总结只覆盖当前 Mac 客户端里用户可见的两条主功能线及其直接共享能力，不声称覆盖整个仓库。

## 2. 音频变声

### 2.1 Single Convert

- 定位：面向单个本地音频文件的离线变声工作流，强调快速试音、结果回听与输出定位。
- 主入口：
  - 主内容区的 `Single Convert`。
  - 控制台动作按钮 `REC`、`PLAY`、`OPEN`。
  - 左侧共享控制区的 `VOICE MODEL`、`SPEAKER ID`、`F0 METHOD`、`INDEX FILE`、离线参数推子。
- 当前界面字段说明：
  - `VOICE MODEL`：选择当前要使用的模型；未选模型时无法执行变声。
  - `SPEAKER ID`：针对多 speaker 模型选择说话人槽位；单 speaker 模型通常保持 `0`。
  - `F0 METHOD`：选择音高提取算法，作用于单文件和批量。
  - `INDEX FILE`：可使用自动匹配索引、显式选择列表中的索引、选择外部索引，或切换到 `No index`。
  - `PARAM BANK`：切到 `single` 后，底部推子控制当前单文件参数。
  - 单文件推子区：主要控制 `transpose`、`index rate`、`protect`、`rms mix`。
  - 右侧 `Inspector / Single Convert Controls`：补充高级参数，包括 `Index Path`、`F0 Method`、`Transpose`、`Index Rate`、`Filter Radius`、`Resample`、`RMS Mix`、`Protect`。
  - `Choose Audio`：选一个本地音频文件作为输入。
  - `Convert` 或 `REC`：开始单文件变声。
  - `Play Result` / `PLAY`：试听转换结果。
  - `Stop Preview`：停止试听。
  - `Reveal Output` / `OPEN`：在 Finder 中定位输出文件。
  - 单文件状态卡：会显示当前 `input file`、`selected index`、`loaded model`、`preview state`。
- 核心能力：对单个音频文件执行 RVC 推理；支持模型绑定、speaker 选择、F0 方法选择、索引自动匹配或手动覆盖；支持转换后预览播放、停止预览和在 Finder 中定位结果。
- 主要输入：已加载模型、单个音频文件、speaker ID、F0 方法、索引路径或外部自定义索引、transpose、index rate、filter radius、resample SR、RMS mix rate、protect。
- 主要输出：单个转换结果音频文件，外加结果消息、预览状态与输出文件定位能力。
- 关键参数：`speakerId`、`transpose`、`f0Method`、`indexPath`、`indexRate`、`filterRadius`、`resampleSR`、`rmsMixRate`、`protect`。
- 典型步骤：加载模型 -> 选择单个音频文件 -> 选择 speaker / F0 / 索引 -> 调整单文件参数 -> 执行转换 -> 试听结果 -> 定位输出文件。
- 边界：单文件预览仅属于离线单文件路径，不扩展到批量或实时路径；虽然底层请求模型支持 `f0FileURL`，但当前界面未提供稳定可见的 F0 曲线文件入口，因此不作为现阶段操作说明的一部分。

### 2.2 Batch Convert

- 定位：面向多文件离线处理的批量变声工作流，强调统一参数配置和目录级输出。
- 主入口：
  - 主内容区的 `Batch Convert`。
  - 控制台动作按钮 `DIR`、`FILES`、`OUT`。
  - 左侧共享控制区的 `VOICE MODEL`、`SPEAKER ID`、`F0 METHOD`、`INDEX FILE`、离线参数推子。
- 当前界面字段说明：
  - `VOICE MODEL`、`SPEAKER ID`、`F0 METHOD`、`INDEX FILE`：与单文件路径共用同一套入口。
  - `PARAM BANK`：切到 `batch` 后，底部推子控制批量参数。
  - 右侧 `Inspector / Batch Convert Controls`：补充批量高级参数，包括 `Index Path`、`Output Format`、`Transpose`、`Index Rate`、`Filter Radius`、`Resample`、`RMS Mix`、`Protect`。
  - `Input Folder` / `DIR`：选择一个输入目录，适合整批处理。
  - `Input Files` / `FILES`：直接选多个音频文件；与输入目录二选一。
  - `Output Folder` / `OUT`：指定批量结果输出目录。
  - `Output Format`：选择批量输出格式，支持 `wav`、`flac`、`mp3`、`m4a`。
  - `Convert Batch`：开始批量处理。
  - `Open Output Folder`：打开结果目录。
  - 批量状态区：显示当前 `input directory`、`input files` 数量、`output directory`。
- 核心能力：支持“输入文件夹”与“显式文件列表”二选一的批量输入模式；按统一模型与参数批量执行变声；将结果输出到指定目录，并支持直接打开输出目录。
- 主要输入：已加载模型、输入目录或输入文件列表、输出目录、输出格式、speaker ID、F0 方法、索引路径或外部自定义索引、transpose、index rate、filter radius、resample SR、RMS mix rate、protect。
- 主要输出：指定输出目录中的批量转换结果文件，以及逐文件结果消息与目录级输出定位能力。
- 关键参数：`outputDirectoryURL`、`format`、`speakerId`、`transpose`、`f0Method`、`indexPath`、`indexRate`、`filterRadius`、`resampleSR`、`rmsMixRate`、`protect`。
- 典型步骤：加载模型 -> 选择输入目录或输入文件列表 -> 选择输出目录和输出格式 -> 设置 speaker / F0 / 索引与批量参数 -> 执行批量转换 -> 查看逐文件结果 -> 打开输出目录。
- 边界：批量路径不提供单文件试听；输出格式选择仅属于批量离线路径。

## 3. 实时变声

- 定位：面向设备级语音流处理的实时变声工作流，强调路由配置、实时调参与运行状态回读。
- 主入口：
  - 顶部动作区的 `AUDIO` 与 `RUN/STOP`。
  - 实时路由区的 `HOST`、`INPUT`、`OUTPUT`、`MON`。
  - `REALTIME LAB` 参数区。
  - 与 Patch Bay 共用的 `VOICE MODEL`、`SPEAKER ID`、`F0 METHOD`、`INDEX FILE`。
- 当前界面字段说明：
  - `AUDIO`：刷新音频设备与实时上下文。
  - `RUN`：在模型已加载且 `INPUT` / `OUTPUT` 已选的前提下启动实时变声。
  - `STOP`：停止实时变声。
  - `HOST`：选择音频主机 API；修改后会刷新设备上下文。
  - `INPUT`：选择输入设备，例如麦克风或虚拟输入。
  - `OUTPUT`：选择输出设备，例如扬声器、耳机或虚拟回放设备。
  - `MON`：选择监听模式；`VC` 表示监听转换后的声音，`INPUT` 表示监听原始输入。
  - `VOICE MODEL`：实时路径使用当前已加载模型，不单独维护另一份模型选择。
  - `INDEX FILE`：实时启动时沿用当前共享索引选择。
  - `F0 METHOD`：实时也复用同一套 F0 选择。
  - `REALTIME LAB / SR MODE`：决定使用模型采样率还是设备采样率。
  - `REALTIME LAB / EXTRA`：额外推理时间缓冲。
  - `REALTIME LAB / CPUS`：CPU 处理进程数。
  - `REALTIME LAB / THR`：输入阈值。
  - `REALTIME LAB / FMT`：formant 调整。
  - `REALTIME LAB / SMP`：sample length。
  - `REALTIME LAB / FAD`：fade length。
  - `REALTIME LAB / IN NR`：输入降噪。
  - `REALTIME LAB / OUT NR`：输出降噪。
  - `REALTIME LAB / PV`：phase vocoder。
  - 状态读数区：会显示 `MODEL`、`INPUT`、`OUTPUT`、`INDEX`、`BANK`、`MONITOR`、`RATE`、`DELAY`、`INFER`。
- 核心能力：刷新音频设备与 Host API 列表；选择输入设备、输出设备和监控模式；以已加载模型启动实时变声；在运行中继续下发配置更新；在停止后返回最新状态。
- 主要输入：已加载模型、可选索引路径、Host API、输入设备、输出设备、监控模式，以及共享推理参数与实时专属参数。
- 主要输出：设备级实时变声流与状态回读，不产生文件输出。
- 关键参数：共享推理参数子集 `transpose`、`indexRate`、`rmsMixRate`、`f0Method`、`indexPath`；实时专属参数 `formant`、`threshold`、`sampleLength`、`fadeLength`、`extraInferenceTime`、`cpuProcesses`、`inputNoiseReduction`、`outputNoiseReduction`、`usePhaseVocoder`、`sampleRateMode`、`hostapi`、`inputDevice`、`outputDevice`、`function`。
- 典型步骤：加载模型 -> 刷新设备列表 -> 选择 Host API / 输入设备 / 输出设备 / 监控模式 -> 设置实时专属参数与共享推理参数 -> 启动实时变声 -> 在运行中按需热更新参数 -> 停止实时变声并查看状态。
- 边界：实时路径的结果表现为设备流而非文件；实时只复用共享控制面中的部分核心推理参数，不把 `single/batch` 的 `PARAM BANK` 解释为实时模块本身。

### 3.1 实时状态回读

- 定位：向用户回报当前实时会话是否运行、当前路由与性能状态。
- 入口：
  - 顶部工具条中的 `RATE`、`DELAY`、`INFER`。
  - 中央监控面板中的 `MODEL`、`INPUT`、`OUTPUT`、`MONITOR`、`RATE`、`DELAY`、`INFER`。
  - 状态消息 `VOICE PATCH` 区域。
- 核心能力：在启动、停止、刷新设备或更新配置后返回统一状态快照。
- 主要输出：`running`、`sample rate`、`channels`、`delay time`、`infer time`、`selected route`、`last error`。
- 关键参数：`delayTimeMs`、`inferTimeMs`、`sampleRate`、`channels`、`selectedHostapi`、`selectedInputDevice`、`selectedOutputDevice`、`lastError`。
- 边界：状态回读用于说明实时运行情况，不应表述为独立文件产出或离线路径结果。

## 4. 共享基础能力

| 能力名 | 适用主线 | 用户可见表现 | 说明 |
| --- | --- | --- | --- |
| 模型目录刷新与加载 | 音频变声、实时变声 | `BOOT` 后可用 `SYNC` 刷新模型；`VOICE MODEL` 选择模型；`UNLD` 卸载模型；`Models` 视图查看模型列表与摘要 | 模型是两条主线的共同前提；加载模型后会同步刷新 speaker 数量、可用索引与相关状态。`UNLD` 用于清空当前加载模型并重置共享选择。 |
| 权重目录与索引目录直达 | 音频变声、实时变声 | `PTH` 打开权重目录，`IDX` 打开索引目录；`Models` 视图中也提供 `Open Weights` 与 `Open Indices` | 这组入口用于确认本地资源放置位置，常用于检查“为什么模型/索引没有出现在列表里”。 |
| 索引目录刷新与自动匹配 | 音频变声、实时变声 | `INDEX FILE` 中显示自动模式、索引列表和当前选中项；`Models` 视图可查看索引清单 | 索引被统一视为可选增强项；若未显式指定，可按模型自动匹配。 |
| 外部自定义索引覆盖 | 音频变声、实时变声 | `INDEX FILE` 可选择外部索引、清除覆盖、切回 `No index` | 自定义索引是共享覆盖机制，不在两条主线中重复定义。 |
| speaker 选择 | 音频变声、实时变声 | `SPEAKER ID` 根据当前模型的 `speakerCount` 生成候选值 | speaker 控制由共享模型元数据驱动；实时路径通过共享参数一起使用。 |
| F0 方法选择 | 音频变声、实时变声 | `F0 METHOD` 统一提供 `pm`、`dio`、`harvest`、`crepe`、`rmvpe`、`fcpe` | F0 方法属于共享推理能力；实时路径复用相同选择。 |
| 参数 bank 切换 | 音频变声 | `PARAM BANK` 在 `single` 与 `batch` 间切换，共享控制离线参数推子 | 参数 bank 只用于离线 `single/batch` 的共享控制面；实时只复用其中部分核心推理参数。 |
| 共享推理参数同步 | 音频变声、实时变声 | `transpose`、`index rate`、`RMS mix`、`F0`、`index` 在不同路径间保持一致的命名与控制逻辑 | 共享参数降低两条主线之间的学习成本，并支持实时运行中的配置下发。 |
| 状态提示与 toast / summary | 音频变声、实时变声 | 顶部状态、toast、运行摘要、错误提示 | 状态反馈属于共享体验层，用于说明当前任务是否完成、失败或仍在运行。 |

## 5. 详细操作过程

### 5.1 启动前准备

1. 点击 `BOOT` 启动后端引擎。
2. 等待状态进入可用，再点击 `SYNC` 刷新模型与索引目录。
3. 如果需要查看可用模型和索引，进入 `Models` 视图确认列表是否正常加载。

### 5.1.1 Models 视图怎么用

1. 进入 `Models` 视图后，先看左侧模型列表是否已经出现可选模型。
2. 点击 `Refresh Catalog` 可以重新扫描当前模型与索引目录。
3. 点击 `Open Weights` 可直接打开权重目录，检查 `.pth` 是否已放到正确位置。
4. 点击 `Open Indices` 可直接打开索引目录，检查 `.index` 是否已放到正确位置。
5. 选择任意模型后，右侧摘要区会显示当前模型信息。
6. 展开 `available index paths` 可查看客户端当前识别到的索引路径列表。

### 5.1.2 Engine 视图怎么用

1. 进入 `Engine` 视图可直接看到当前仓库路径、引擎根目录、端口和状态。
2. 如果引擎还没启动，可在这里点击 `Start`。
3. 如果模型刷新异常或端口状态异常，可点击 `Restart` 重启后端。
4. 若需要确认后端最近发生了什么，可展开 diagnostics 区查看 recent log。
5. 文档层面把 `Engine` 视图视为运行环境检查入口，不把 recent log 本身当成功能卖点。

### 5.2 单文件音频变声

1. 在 `VOICE MODEL` 中选择模型。
2. 如模型支持多 speaker，在 `SPEAKER ID` 中选择目标槽位。
3. 在 `F0 METHOD` 中选择音高提取方式。
4. 在 `INDEX FILE` 中决定使用自动索引、指定索引、外部索引，或不使用索引。
5. 把 `PARAM BANK` 切到 `single`。
6. 在主内容区 `Single Convert` 点击 `Choose Audio` 选择输入音频。
7. 如需更细调参，切到右侧 `Inspector / Single Convert Controls`，设置 `Filter Radius`、`Resample` 等高级项。
8. 按需调整共享推子参数，例如音高、索引混合、保护值、RMS 混合。
9. 点击 `Convert` 或控制台 `REC` 开始变声。
10. 完成后用 `Play Result` / `PLAY` 试听；满意后用 `Reveal Output` / `OPEN` 定位文件。

### 5.3 批量音频变声

1. 在 `VOICE MODEL`、`SPEAKER ID`、`F0 METHOD`、`INDEX FILE` 中完成共享设置。
2. 把 `PARAM BANK` 切到 `batch`。
3. 用 `Input Folder` / `DIR` 选择输入目录，或用 `Input Files` / `FILES` 直接选择多个文件，二选一。
4. 用 `Output Folder` / `OUT` 选择输出目录。
5. 在批量视图或右侧 `Inspector / Batch Convert Controls` 中确认 `Output Format`。
6. 如需更细调参，切到右侧 `Inspector / Batch Convert Controls`，设置 `Filter Radius`、`Resample`、`RMS Mix`、`Protect` 等高级项。
7. 调整批量参数后点击 `Convert Batch`。
8. 完成后查看结果消息，并用 `Open Output Folder` 打开输出目录。

### 5.3.1 Single / Batch Inspector 参数怎么看

1. `Index Path`：当前离线任务使用的索引路径；可以保持自动，也可以显式改成某个已识别索引。
2. `Transpose`：升降调。
3. `F0 Method`：音高提取算法。
4. `Index Rate`：索引参与程度。
5. `Filter Radius`：滤波半径，高级调优项。
6. `Resample`：输出重采样目标，`0` 通常表示不额外重采样。
7. `RMS Mix`：响度混合比例。
8. `Protect`：保护值，用于减少某些失真或不稳定表现。
9. `Output Format`：仅批量路径可见，用于决定批量输出文件格式。

### 5.4 实时变声

1. 先完成 `VOICE MODEL`、`SPEAKER ID`、`F0 METHOD`、`INDEX FILE` 的共享设置。
2. 点击 `AUDIO` 刷新实时设备。
3. 在路由区依次设置 `HOST`、`INPUT`、`OUTPUT`、`MON`。
4. 在 `REALTIME LAB` 中设置 `SR MODE`、`EXTRA`、`CPUS`、`THR`、`FMT`、`SMP`、`FAD`，并根据需要打开 `IN NR`、`OUT NR`、`PV`。
5. 确认 `INPUT` 和 `OUTPUT` 都已选定后，点击 `RUN` 启动实时变声。
6. 运行过程中，继续改动共享参数或 `REALTIME LAB` 参数时，客户端会把配置重新下发到后端。
7. 通过 `RATE`、`DELAY`、`INFER` 和监控面板观察当前状态。
8. 结束时点击 `STOP`。

### 5.5 如何理解当前界面的几个关键读数

1. `MODEL`：当前已加载模型，不等于目录里全部模型。
2. `INDEX`：当前共享索引选择，可能是自动、显式索引，或外部覆盖。
3. `BANK`：当前离线参数正在控制 `single` 还是 `batch`。
4. `RATE`：实时链路当前采样率。
5. `DELAY`：实时链路总延迟读数。
6. `INFER`：当前推理耗时读数。
7. `APP`：当前客户端进程的内存占用读数。
8. `ENGINE`：后端引擎进程的内存占用读数。
9. `PORT`：当前后端桥接服务监听端口；如果端口为空，通常说明引擎还没 ready。
10. `VOICE PATCH` 状态文案：最近一次动作的结果，例如启动成功、停止成功或报错。
11. `lastExecutionSummary`：左侧控制台底部的最近一次执行摘要，用于快速回看最近的离线转换或实时动作结果。

### 5.6 哪些字段是共享的，哪些字段只在当前页面生效

| 字段或区域 | 作用范围 | 说明 |
| --- | --- | --- |
| `VOICE MODEL` | 全局共享 | 当前加载模型会同时影响单文件、批量和实时路径。 |
| `SPEAKER ID` | 离线与实时共享 | 选择后会同步到单文件和批量；实时启动时沿用当前 speaker 相关共享上下文。 |
| `F0 METHOD` | 离线与实时共享 | 在 Patch Bay 中修改后，单文件、批量和实时都复用同一选择。 |
| `INDEX FILE` | 离线与实时共享 | 当前索引选择会同步到 single / batch，并作为实时启动与配置更新的索引来源。 |
| `PARAM BANK` | 仅离线页面切换 | 只决定底部离线参数当前控制的是 `single` 还是 `batch`，不改变实时模块归属。 |
| 离线推子 `PIT / IDX / GRD / RMS` | 当前 bank 生效 | 当 `PARAM BANK=single` 时改的是单文件参数；当 `PARAM BANK=batch` 时改的是批量参数。 |
| 离线扩展推子 `FILTER / RESAMP / RMS / GUARD` | 当前 bank 生效 | 同样受 `PARAM BANK` 影响，分别绑定到 single 或 batch 的高级参数。 |
| `Single Convert` 主内容区字段 | 仅单文件页面 | 输入文件、试听、单文件结果定位只作用于单文件流程。 |
| `Batch Convert` 主内容区字段 | 仅批量页面 | 输入目录、输入文件列表、输出目录、批量格式只作用于批量流程。 |
| `Inspector / Single Convert Controls` | 仅单文件页面 | 右侧高级参数面板，专门调单文件离线参数。 |
| `Inspector / Batch Convert Controls` | 仅批量页面 | 右侧高级参数面板，专门调批量离线参数。 |
| `HOST / INPUT / OUTPUT / MON` | 仅实时页面 | 只影响实时路由和监听方式，不改变离线任务。 |
| `REALTIME LAB` | 仅实时页面 | 只影响实时推理链路；运行中修改会继续下发到后端。 |
| `Models` 视图 | 全局信息页 | 用于查看和确认模型、索引、摘要，不直接执行离线或实时任务。 |
| `Engine` 视图 | 全局运行页 | 用于查看引擎状态、端口和日志，不负责变声参数调节。 |

### 5.7 页面之间怎么串起来使用

1. 首次使用时，通常先去 `Engine` 确认后端已启动，再去 `Models` 确认模型和索引已经被识别。
2. 完成资源确认后，再回到 `Single Convert` 或 `Batch Convert` 做离线任务。
3. 如果要做实时变声，不需要进入单独的实时页面；实时控制分散在顶部动作区、路由区和 `REALTIME LAB`。
4. 当你在 `Single Convert` 与 `Batch Convert` 之间切换时，模型、speaker、F0 和索引仍然延续，但 `PARAM BANK` 会自动切回对应页面的默认模式。
5. 当实时已经在运行时，修改共享参数或 `REALTIME LAB` 参数会触发配置更新；离线页面的输入文件或输出目录不会因此被覆盖。

## 6. 范围边界

- 明确包含：离线单文件变声、离线批量变声、实时设备路由与实时变声、与两条主线直接相关的模型/索引/speaker/F0/参数控制与状态反馈。
- 明确排除：训练、数据集处理、索引训练、UVR、ONNX、CKPT 工具、资产审计，以及任何不直接服务于音频变声或实时变声主路径的附属模块。
- 不作为卖点：traceback、底层诊断日志、依赖兼容细节、调试状态、后端异常栈、资源完整性检查等运行细节。
