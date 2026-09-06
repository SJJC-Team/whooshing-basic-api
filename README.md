# Whooshing 基本工具库

本项目为 [Whooshing](https://github.com/whooshing-workshop/whooshing) 系统的**基本工具库**，为系统提供最底层加解密，错误处理，日志系统以及数据转换的基本功能。它被设计成高内聚、低耦合的形式，为各类 Whooshing 模块提供强大的底层支撑。

### 特性

- **Cryptos (加密与哈希算法)**：基于 [swift-crypto](https://github.com/apple/swift-crypto) 封装。
  - **哈希算法**：支持 SHA512 摘要计算及加盐哈希（`Crypto.hash` / `Crypto.saltyHash`）。
  - **对称加密 (AES)**：支持常规块加密以及大数据流式分块加密，并提供强大的密钥派生（KDF）功能。
  - **非对称加密 (EdDSA / Curve25519)**：支持 Diffie-Hellman 密钥交换协议，以及电子签名机制。
- **ErrorHandle (统一错误处理框架)**：
  - 提供 `Err` 和 `ErrList` 协议体系。
  - 支持**错误链（Error Chains）**机制，能自动捕获抛出错误所在的文件、函数、行数，以及挂载附加元数据。
  - 每个错误必须声明 `ErrCategory`（`.external` / `.internal` / `.inherit`），区分应向外界暴露的输入错误与需要隐藏的内部错误，`.external` 还可携带修复建议与自定义 `userdata`（如 HTTP 状态码）。
- **DataConvertable (数据类型转换)**：
  - 提供安全的 `SafeDataConvertable`（如 `Int`, `Data`, `Array<Safe>`）和受检的 `ThrowableDataConvertable`（如 `String`, `Dictionary`）协议。
  - 将原生类型与 `Data` 或 `ByteBuffer` 间进行无缝、安全的快速互转。
- **NIOAdvanced (NIO 进阶与错误包装)**：
  - 扩展 SwiftNIO，提供强类型的 `EventLoopResult<Value, ErrorType>`，包装了原生的 `EventLoopFuture`。
  - 彻底解决异步回调中由于泛型错误被擦除导致捕获不到详细上下文的痛点，与 `ErrorHandle` 模块完美结合。
- **LoggingAdvanced (日志轮转与进阶扩展)**：
  - 基于 [Puppy](https://github.com/sushichop/Puppy) 实现日志轮转系统，可通过 `LoggingFactory` 集中管理路由。
  - 提供**批量链式日志（Logger Chaining）**功能，通过统一 `UUID` 追踪一连串异步日志。

----------

### 导入该依赖库

在你的 Package.swift 加入：

``` swift
.package(url: "https://github.com/whooshing-workshop/whooshing.toolbox-basic.git", from: "1.6.3")
```

根据需要导入不同的目标产品：

``` swift
dependencies:[
    .product(name: "Cryptos", package: "whooshing.toolbox-basic"),
    .product(name: "DataConvertable", package: "whooshing.toolbox-basic"),
    .product(name: "ErrorHandle", package: "whooshing.toolbox-basic"),
    .product(name: "NIOAdvanced", package: "whooshing.toolbox-basic"),
    .product(name: "LoggingAdvanced", package: "whooshing.toolbox-basic")
]
```

--------

### 使用介绍

#### 1. Cryptos 加解密库使用

提供便捷的对称和非对称加密工具，支持流式加密、密钥派生及哈希操作：

``` swift
import Cryptos

// ----- 密钥派生 -----
let masterKey = Crypto.Symm.Key(data: Data(base64Encoded: keyStr)!)
// 结合盐值与附加信息，派生出独立的加密子密钥
let key = try masterKey.derive(salt: saltData, info: sharedData).get()

// ----- 流式对称加密与解密 -----
// 可用于分块加密网络数据流或文件
let cipher = try Crypto.Symm.Stream.encrypt(chunkData, key: key, chunkTag: currentTag).get()
let originalData = try Crypto.Symm.Stream.decrypt(cipher, key: key, chunkTag: currentTag).get()

// ----- 哈希摘要计算 -----
// 若为 SafeDataConvertable 类型可直接哈希
let hashData = Crypto.hash(12345)
// 加盐哈希
var salt: Data? = nil
let saltyHash = try Crypto.saltyHash("Secret String", salt: &salt).get()
```

#### 2. ErrorHandle 错误处理

捕获上下文，追踪底层错误：

``` swift
import ErrorHandle

// 声明一个错误列表，枚举值即为该错误的 summary
enum MyErrcase: String, ErrList {
    case openFileFailed = "打开文件失败"
    case getFileFailed = "获取文件失败"
}

// 定义并抛出包含底层错误的包装错误（错误类型为 MyErrcase.ErrType，默认即 BasicError<MyErrcase>）
func someAction() throws(MyErrcase.ErrType) {
    do {
        // ...
    } catch {
        // 自动捕获发生时的 file, line, function
        // 并通过 .subErr 将底层错误链入；category 决定该错误如何向外界展示：
        //   .external(suggestions:userdata:)  由外部输入引起，可携带修复建议与附加数据（如 HTTP 状态码）
        //   .internal                         内部错误，向外界隐藏细节
        //   .inherit                          沿用底层错误的类别
        throw MyErrcase.openFileFailed.subErr(error, category: .inherit)
    }
}

// 快速抛出带描述信息的错误，并附加额外元数据给日志
throw MyErrcase.getFileFailed
    .d("目标并非是一个文件", category: .external(suggestions: ["请检查路径是否指向文件"]))
    .metadata(["path": .string("/root")])

// 使用 required(...) 把任意抛错的调用收束为指定的错误
let data = try required(throws: MyErrcase.getFileFailed, "读取失败", category: .internal) {
    try Data(contentsOf: url)
}
```

#### 3. DataConvertable 数据转换

为安全和非安全的互相转换提供明确的边界：

``` swift
import DataConvertable

// ----- 安全转换 (SafeDataConvertable) -----
// 不会抛出异常
let intData = 1024.data
let newInt = Int.new(data: intData)

let arrayData = [1, 2, 3].data
let newArray = [Int].new(data: arrayData)

// ----- 抛出式转换 (ThrowableDataConvertable) -----
// 字符串或字典转换可能会失败
let strData = try "Hello".dataRes.get()
let newStr = try String.make(data: strData).get()

let hexString = strData.hexString
let base64 = strData.base64String
```

#### 4. NIOAdvanced 异步错误收束

原生 `EventLoopFuture` 仅支持泛型标准 `Error`，这会导致经过多层 `flatMap` 回调后，抛出的明确错误类型被擦除，极难排查。`EventLoopResult` 将其包装以维持严格强类型的 `ErrorType`。

``` swift
import NIOAdvanced

// EventLoopRes<Value, MyErrcase> 即 EventLoopResult<Value, MyErrcase.ErrType>
func performAsync() -> EventLoopRes<String, MyErrcase> {
    let future: EventLoopFuture<String> = ...
    
    // 将无严格类型错误的 Future 转化为保留严格类型的 EventLoopResult
    // 原生错误会通过 .subErr 被挂载为 Error Chains
    return future.withError(MyErrcase.networkFailed, "请求远端失败", category: .internal)
}

// 使用方式类似于原生 Future，但强绑定了具体的错误类型
performAsync().map { value in
    return value + " success"
}.flatMapErrorThrowing { err throws(MyErrcase.ErrType) in
    // 在这里错误类型必定是明确的 MyErrcase.ErrType，不会被擦除
    throw err
}

// 也可以在 async/await 与 EventLoop 之间桥接：
let result: EventLoopRes<Data, MyErrcase> = eventLoop.bridge { () throws(MyErrcase.ErrType) in
    try await loadData()
}
```

#### 5. LoggingAdvanced 链式日志记录与集中式工厂

##### 使用 `LoggingFactory` 集中管理日志

通过 `LoggingFactory` 将多个日志分流策略（`LoggerStrategy`，控制台输出或 Puppy 文件轮转日志）组织为策略数组，并通过全局元数据初始化。支持多工厂实例组合与追加。

``` swift
import LoggingAdvanced

// 控制台策略：记录所有 trace 及以上等级的日志
let console = LoggerStrategy(label: "console", level: .trace)

// 文件轮转策略：label 以 "network" 开头的 logger 写入 ~/logs/network_logs/network.log
// 文件过大时自动轮转并备份旧日志，目录不存在会自动创建
let networkFile = try LoggerStrategy(
    label: "network",
    level: .info,
    config: .file(
        logPrefix: "network",
        directory: URL.homeDirectoryForCurrentUser.appendingPathComponent("logs/network_logs"),
        name: "network.log"
    )
)

// 也可以用闭包自定义分流规则
let errorFile = try LoggerStrategy(
    label: "error",
    level: .error,
    config: .file(match: { _ in true }, directory: errorLogDir, name: "error.log")
)

let factory = LoggingFactory(strategies: [console, networkFile], metadataProvider: myGlobalProvider)
// 也可以追加策略，或组合其他的 factory
let finalFactory = factory
    .append(strategies: [errorFile])
    .combine(factories: [anotherFactory])

// 启动生效全局日志拦截体系（LoggingSystem.bootstrap）
finalFactory.bootstrap()

// 从既有 logger 派生子 logger：label 追加 ".sub"，并附带额外元数据
let logger = Logger(label: "network").derive(subId: "http", metadata: ["module": "api"])
```

##### 使用链式日志记录 (Logger Chaining)

用于记录具备高度上下文关联的并发并发事件日志组：

``` swift
let logger = Logger(label: "NetworkSystem")

// 将一组相关信息通过同一 UUID 打包记录，避免高并发下多路请求的日志相互穿插
logger.infos(
    ("收到请求数据", ["size": "1024"], "Network"),
    ("正在解析数据", nil, "Parser"),
    ("处理完成", nil, "Database")
)
```

-------

### 运行环境

* **macOS** (> 10.15)
* **iOS** (> 14.0)
* **Linux** (> 20)
* **Swift** (> 6.0)
* **watchOS** (> 6.0) **[未测试]**
* **tvOS** (> 13) **[未测试]**

-------

### 注意事项

- 不同模块可以按需导入，避免引入不必要的依赖。
- Cryptos 依赖于 `swift-crypto`，请注意底层依赖的冲突。

如需了解更多，请参阅各模块内的源码注释与文档说明。

------

### 联系与反馈

如有使用问题或建议，请通过 [GitHub Issues](https://github.com/whooshing-workshop/whooshing.toolbox-basic/issues) 提交反馈。

或发至邮箱 [contact@official.whooshings.space](mailto:contact@official.whooshings.space)
