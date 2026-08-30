import Crypto
import Foundation
import ErrorHandle
import DataConvertable

public extension Crypto {
    
    /**
        #### 对称加密算法

        对称加密是指加解密必须使用用同一个密钥才能完成加解密算法。

        使用 AES 进行数据加密，其中提供
        
        - 对称加解密
        - 身份验证函数(即 Sign 声明块中所定义的)

        -----
        ### 对称加解密

        AES 加密，因其高效且安全，因此通常用于进行数据流加密，适用于加密大数据，但密钥需要妥善管理并安全交换。

        使用 `makeKey()` 生成密钥，并使用 `encrypt(_, key)` 加密数据，`decrypt(_, key)` 解密数据。

        ``` swift
        let plain = "Hello World!"
        // 生成对称密钥
        let key = Crypto.Symm.makeKey()
        // plain 的数据类型为 String，为 ThrowableDataConvertable，所以需要捕获并处理错误
        do {
            // 加密数据
            let cipher = try Crypto.Symm.encrypt(plain, key: key)
            // 解密数据
            let new: String = try Crypto.Symm.decrypt(cipher, key: key)

            print(new == plain)     // true
        } catch let err {
            // AES 加解密出现错误！
            print(err)
        }
        ```
        -----
        ### HMAC 消息来源验证(即 Sign 声明块中所定义的)

        HMAC 并不负责加密数据，仅负责进行身份验证，即便消息为明文，仍可以保证消息不被篡改(或说，可以判断是否被篡改从而采取行动)。但它并不负责数据是否被窃取，仅用做验证数据完整性和可靠性。

        依然使用 `makeKey()` 生成密钥，`make(_, key)` 创建签名，`validate(_, authCode, key)` 验证签名

        ``` swift
        let plain = "Hello World!"
        let key = Crypto.Symm.makeKey()
        do {
            // 创建签名
            let hmacCode = try Crypto.Symm.Sign.make(plain, key: key)
            // 验证签名
            let isValid = try Crypto.Symm.Sign.validate(plain, authCode: hmacCode, key: key)

            print(isValid ? "验证有效，消息\"\(plain)\"未被篡改" : "验证失败，消息被篡改")  // 验证有效，消息"Hello World!"未被篡改
        } catch let err {
            print(err)
        }
        ```
    */
    @frozen
    enum Symm{
        
        @frozen
        public enum Errcase: String, ErrList {
            case aesEncryptFailed = "AES 加密失败"
            case aesDecryptFailed = "AES 解密失败"
            case chunkTagConvertFailed = "加解密 块标签转换失败"
        }
        
        public typealias Key = SymmetricKey

        /// 创建一个对称加密密钥
        @inlinable
        public static func makeKey() -> Key { Key(size: symmetricKeySize) }

        /// 对数据进行加密
        ///
        /// - Parameters:
        ///     - data: 待加密的数据
        ///     - key: 用于加密的密钥，可以由 `makeKey()` 函数生成
        /// - 返回值: 加密过后的密文，只提供 Data 形式
        @inlinable
        public static func encrypt<T>(_ data: T, key: Key) -> Res<Data, Errcase> where T: DecodingThrowableDataConvertable {
            aesEncrypt(data, key: key)
        }

        /// 对数据进行解密
        ///
        /// - Parameters:
        ///     - cipher: 待解密的密文
        ///     - key:  用于解密的密钥，与加密密钥使用同一个密钥
        /// - 返回值: 解密后的明文，返回的数据类型取决于目标类型
        ///
        /// ``` swift
        /// let plain: String = try Crypto.symm.decrypt(..., key: ...)
        /// ```
        @inlinable
        public static func decrypt<D>(_ cipher: Data, key: Key) -> Res<D, Errcase> where D: EncodingThrowableDataConvertable {
            aesDecrypt(cipher, key: key)
        }
        
        /**
            #### 数据流加解密
         
            设计来用于对流式数据进行加解密，对于这类数据，AES.GCM 无需生产随机的 nonce，转为使用每个数据块的索引代替
            且使用 AAD 进行完整性验证。
         
            每个密文的长度固定，为 明文大小 + cipherExtraLength。这保证了文件流加密时无需记录文件的加密块边界
         */
        @frozen
        public enum Stream {
            
            /// 数据块加密的密文额外大小，即 `cipher.count = plain.count + cipherExtraLength`
            @inlinable
            public static var cipherExtraLength: Int64 { Self.__cipherExtraLength }
            
            /// 对数据流进行加密，十分适用于文件流加密这类有记忆的流式传输加密
            ///
            /// - Parameters:
            ///     - data: 待加密的数据
            ///     - key: 用于加密的密钥，可以由 `makeKey()` 函数生成
            ///     - chunkTag: 数据流的标记，一般是该数据块的索引值
            /// - Returns: 加密过后的数据密文
            ///
            /// - warning: 对于无记忆的流式传输，比如 websocket，除非你自己建立索引计数，否则应当使用普通的 `Symm.encrypt` 代替
            @inlinable
            public static func encrypt<T>(_ data: T, key: Key, chunkTag: Int) -> Res<Data, Errcase> where T: DecodingThrowableDataConvertable {
                chunkEncrypt(data, key: key, chunkTag: chunkTag)
            }
            
            /// 对数据流密文进行解密，十分适用于文件流加密这类有记忆的流式传输加密
            ///
            /// - Parameters:
            ///     - cipher: 待解密的密文
            ///     - key:  用于解密的密钥，与加密密钥使用同一个密钥
            ///     - chunkTag: 数据流的标记，一般是该数据块的索引值
            /// - Returns: 解密后的数据明文
            ///
            /// - warning: 对于无记忆的流式传输，比如 websocket，除非你自己建立索引计数，否则应当使用普通的 `Symm.decrypt` 代替
            @inlinable
            public static func decrypt<T>(_ cipher: Data, key: Key, chunkTag: Int) -> Res<T, Errcase> where T: EncodingThrowableDataConvertable {
                chunkDecrypt(cipher, key: key, chunkTag: chunkTag)
            }
            
        }
        
        /// 消息来源验证块，实现 HMAC 的签名和认证
        @frozen
        public enum Sign {

            @frozen
            public enum Errcase: String, ErrList {
                case makeSignFailed = "签名生成失败"
                case validationFailed = "签名验证失败"
            }
            
            /// 创建签名
            ///
            /// - Parameters:
            ///     - data: 待签名的数据
            ///     - key: 用于签名的密钥，可共用加解密密钥
            /// - Returns: MAC 消息验证码，发送至对方用于验证消息是否被篡改
            /// ``` swift
            /// let mac = try Crypto.Symm.Sign.make(data, key)
            /// ```
            @inlinable
            public static func make<T>(_ data: T, key: Key) -> Data where T: DecodingSafeDataConvertable {
                try! __make(data, key: key).get()
            }
            
            @inlinable
            public static func make<T>(_ data: T, key: Key) -> Res<Data, Errcase> where T: DecodingThrowableDataConvertable {
                __make(data, key: key)
            }
            
            @inlinable
            static func __make<T>(_ data: T, key: Key) -> Res<Data, Errcase> where T: DecodingThrowableDataConvertable {
                .init(throws: .makeSignFailed, category: .inherit) {
                    .init(try HMAC<HashFunction>.authenticationCode(for: data.dataRes.get(), using: key))
                }
            }
            
            /// 验证签名
            ///
            /// - Parameters:
            ///     - data: 数据本体，需要被验证是否完整的数据
            ///     - authCode: MAC 消息验证码，由 ```Crypto.Symm.Sign.make(..., key)``` 生成
            ///     - key: 用于解密的密钥，需与加密密钥一致方可进行验证
            /// - Returns: 验证是否匹配，是 则返回 true，否 则返回 false
            @inlinable
            public static func validate<T>(_ data: T, authCode: Data, key: Key) -> Bool where T: DecodingSafeDataConvertable {
                try! __validate(data, authCode: authCode, key: key).get()
            }
            
            @inlinable
            public static func validate<T>(_ data: T, authCode: Data, key: Key) -> Res<Bool, Errcase> where T: DecodingThrowableDataConvertable {
                __validate(data, authCode: authCode, key: key)
            }
            
            @inlinable
            static func __validate<T>(_ data: T, authCode: Data, key: Key) -> Res<Bool, Errcase> where T: DecodingThrowableDataConvertable {
                .init(throws: .validationFailed, category: .inherit) {
                    try HMAC<HashFunction>.isValidAuthenticationCode(authCode, authenticating: data.dataRes.get(), using: key)
                }
            }
        }
    }
}

@available(iOS 14.0, macOS 11.0, watchOS 7.0, tvOS 14.0, *)
extension Crypto.Symm.Key {
    
    @frozen
    public enum Errcase: String, ErrList {
        case keyDeriveFailed = "密钥派生失败"
    }
    
    /// 以本身派生新密钥
    ///
    /// - Parameters:
    ///     - salt: 派生盐，应当不重复且随机
    /// - Returns: 从父密钥创建的新派生密钥
    @inlinable
    public func derive<T>(salt: T) -> Self where T: DecodingSafeDataConvertable {
        try! __derive(salt: salt).get()
    }
    
    /// 以本身派生新密钥
    ///
    /// - Parameters:
    ///     - info: 派生密钥上下文信息
    /// - Returns: 从父密钥创建的新派生密钥
    @inlinable
    public func derive<T>(info: T) -> Self where T: DecodingSafeDataConvertable {
        try! __derive(info: info).get()
    }
    
    /// 以本身派生新密钥
    ///
    /// - Parameters:
    ///     - salt: 派生盐，应当不重复且随机
    ///     - info: 派生密钥上下文信息
    /// - Returns: 从父密钥创建的新派生密钥
    @inlinable
    public func derive<T, G>(_ salt: T, info: G) -> Self where T: DecodingSafeDataConvertable, G: DecodingSafeDataConvertable {
        try! __derive(salt: salt, info: info).get()
    }
    
    /// 以本身派生新密钥
    ///
    /// - Parameters:
    ///     - salt: 派生盐，应当不重复且随机
    /// - Returns: 从父密钥创建的新派生密钥
    @inlinable
    public func derive<T>(salt: T) -> Res<Self, Errcase> where T: DecodingThrowableDataConvertable {
        __derive(salt: salt)
    }
    
    /// 以本身派生新密钥
    ///
    /// - Parameters:
    ///     - info: 派生密钥上下文信息
    /// - Returns: 从父密钥创建的新派生密钥
    @inlinable
    public func derive<T>(info: T) -> Res<Self, Errcase> where T: DecodingThrowableDataConvertable {
        __derive(info: info)
    }
    
    /// 以本身派生新密钥
    ///
    /// - Parameters:
    ///     - salt: 派生盐，应当不重复且随机
    ///     - info: 派生密钥上下文信息
    /// - Returns: 从父密钥创建的新派生密钥
    @inlinable
    public func derive<T, G>(salt: T, info: G) -> Res<Self, Errcase> where T: DecodingThrowableDataConvertable, G: DecodingThrowableDataConvertable {
        __derive(salt: salt, info: info)
    }
    
    
    @inlinable
    func __derive<T>(info: T) -> Res<Self, Errcase> where T: DecodingThrowableDataConvertable {
        .init(throws: .keyDeriveFailed, category: .inherit) {
            try HKDF<Crypto.HashFunction>.deriveKey(inputKeyMaterial: self, info: info.dataRes.get(), outputByteCount: Crypto.symmetricKeySize.bitCount / 8)
        }
    }
    
    @inlinable
    func __derive<T>(salt: T) -> Res<Self, Errcase> where T: DecodingThrowableDataConvertable {
        .init(throws: .keyDeriveFailed, category: .inherit) {
            try HKDF<Crypto.HashFunction>.deriveKey(inputKeyMaterial: self, salt: salt.dataRes.get(), outputByteCount: Crypto.symmetricKeySize.bitCount / 8)
        }
    }
    
    @inlinable
    func __derive<T, G>(salt: T, info: G) -> Res<Self, Errcase> where T: DecodingThrowableDataConvertable, G: DecodingThrowableDataConvertable {
        .init(throws: .keyDeriveFailed, category: .inherit) {
            try HKDF<Crypto.HashFunction>.deriveKey(inputKeyMaterial: self, salt: salt.dataRes.get(), info: info.dataRes.get(), outputByteCount: Crypto.symmetricKeySize.bitCount / 8)
        }
    }
}

extension Crypto.Symm {
    @inlinable
    static func aesEncrypt<T>(_ data: T, key: Key) -> Res<Data, Errcase> where T: DecodingThrowableDataConvertable {
        // print("正在进行加密: \(try data.data().count), key: \(key.data().base64String()))")
        
        guard key.bitCount == Crypto.symmetricKeySize.bitCount else {
            return .failure(.aesEncryptFailed, "密钥长度不正确，应当为 \(Crypto.symmetricKeySize.bitCount) 位，却得到 \(key.bitCount) 位", category: .external())
        }
        
        return Result(throws: .aesEncryptFailed, "AES 加密未能成功封印明文数据", category: .inherit) {
            try AES.GCM.seal(data.dataRes.get(), using: key, nonce: .init())
        }.flatMap { sealedBox in
            guard let cipher = sealedBox.combined else {
                return .failure(.aesEncryptFailed, "AES 加密-未知错误，密文不存在", category: .inherit)
            }
            // print("加密得到: \(cipher.count)")
            return .success(cipher)
        }
    }

    @inlinable
    static func aesDecrypt<D>(_ cipher: Data, key: Key) -> Res<D, Errcase> where D: EncodingThrowableDataConvertable {
        // print("正在进行解密: \(cipher.count), key: \(key.data().base64String()))")
        
        guard key.bitCount == Crypto.symmetricKeySize.bitCount else {
            return .failure(.aesDecryptFailed, "密钥长度不正确，应当为 \(Crypto.symmetricKeySize.bitCount) 位，却得到 \(key.bitCount) 位", category: .external())
        }
        
        return Result(throws: .aesDecryptFailed, category: .inherit) {
            let sealedBox = try AES.GCM.SealedBox(combined: cipher)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return decryptedData
        }.flatMap { decryptedData in
            // print("解密得到: \(decryptedData.count)")
            return D.make(data: decryptedData).mapError(as: Errcase.aesDecryptFailed, category: .inherit)
        }
    }

    static func aesKey(key: Data) -> Key { normalKey(key: key) }
}

extension Crypto.Symm.Stream {
    @inlinable
    static var __cipherExtraLength: Int64 { 28 }
    
    @inlinable
    static func chunkEncrypt<T>(_ data: T, key: Crypto.Symm.Key, chunkTag: Int) -> Res<Data, Crypto.Symm.Errcase> where T: DecodingThrowableDataConvertable {
        guard key.bitCount == Crypto.symmetricKeySize.bitCount else {
            return .failure(.aesEncryptFailed, "密钥长度不正确，应当为 \(Crypto.symmetricKeySize.bitCount) 位，却得到 \(key.bitCount) 位", category: .external())
        }
        
        return Result(throws: .aesEncryptFailed, category: .inherit) {
            let chunkTagData = try chunkTagToData(chunkTag)
            return try AES.GCM.seal(
                data.dataRes.get(),
                using: key,
                nonce: .init(),
                authenticating: chunkTagData
            )
        }.flatMap { sealedBox in
            guard let cipher = sealedBox.combined else {
                return .failure(.aesEncryptFailed, "AES 加密-未知错误，密文不存在", category: .inherit)
            }
            
            // 密文总长度为 plain.count + 16 + 12 bytes
            return .success(cipher)
        }
    }
    
    @inlinable
    static func chunkDecrypt<T>(_ cipher: Data, key: Crypto.Symm.Key, chunkTag: Int) -> Res<T, Crypto.Symm.Errcase> where T: EncodingThrowableDataConvertable {
        guard key.bitCount == Crypto.symmetricKeySize.bitCount else {
            return .failure(.aesDecryptFailed, "密钥长度不正确，应当为 \(Crypto.symmetricKeySize.bitCount) 位，却得到 \(key.bitCount) 位", category: .external())
        }
        
        guard cipher.count >= cipherExtraLength else {
            return .failure(.aesDecryptFailed, "密文过短，格式不正确，无法解密，至少超过 \(cipherExtraLength)，却得到 \(cipher.count) 字节", category: .external())
        }
        
        return Result(throws: .aesDecryptFailed, category: .inherit) {
            /// authentication tag.
            let chunkTagData = try chunkTagToData(chunkTag)
            let sealedBox = try AES.GCM.SealedBox(combined: cipher)
            return try AES.GCM.open(sealedBox, using: key, authenticating: chunkTagData)
        }.flatMap { plain in
            return T.make(data: plain).mapError(as: Crypto.Symm.Errcase.aesDecryptFailed, category: .inherit)
        }
    }
    
    @inlinable
    static func chunkTagToData(_ chunkTag: Int, length: Int = 12) throws(Crypto.Symm.Errcase.ErrType) -> Data {
        guard length >= 8 else {
            throw Crypto.Symm.Errcase.chunkTagConvertFailed.d("Nonce 的长度必须至少为 8 bytes 以存储块标记，得到的长度为: \(length)", category: .external())
        }
        
        var bytes = [UInt8](repeating: 0, count: length)
        withUnsafeBytes(of: chunkTag.bigEndian) { ptr in
            bytes.replaceSubrange((length - 8)..<length, with: ptr) // 把 chunkTag 填入后8字节
        }
        return .init(bytes)
    }
}

private extension Crypto.Symm {
    static func normalKey(key: Data) -> Key { Key(data: key) }
}
