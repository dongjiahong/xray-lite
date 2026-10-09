use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

mod validator;
pub use validator::Validator;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub inbounds: Vec<Inbound>,
    pub outbounds: Vec<Outbound>,
    #[serde(default)]
    pub routing: RoutingConfig,
    #[serde(default)]
    pub performance: PerformanceConfig,
}

/// 资源占用相关配置。小内存机器调小，大内存机器调大。
/// 所有 `*Kb` 字段单位均为 KiB。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct PerformanceConfig {
    /// tokio 工作线程数，0 表示按 CPU 核数自动
    pub worker_threads: usize,
    /// 最大并发连接数
    pub max_connections: usize,
    /// XHTTP: 每个 H2 流的接收窗口
    pub h2_stream_window_kb: u32,
    /// XHTTP: 每个 H2 连接的接收窗口
    pub h2_connection_window_kb: u32,
    /// XHTTP: 单个 H2 连接上的最大并发流数
    pub h2_max_concurrent_streams: u32,
    /// XHTTP: 每个 H2 流允许在内存中排队等待发送的数据上限（下载方向）
    pub h2_send_buffer_kb: usize,
    /// XHTTP: 每个流内部 VLESS 管道的缓冲区大小
    pub pipe_buffer_kb: usize,
    /// UDP 转发时每个 socket 的收发缓冲区
    pub udp_socket_buffer_kb: usize,
}

impl Default for PerformanceConfig {
    fn default() -> Self {
        Self {
            worker_threads: 0,
            max_connections: 4096,
            h2_stream_window_kb: 1024,
            h2_connection_window_kb: 4096,
            h2_max_concurrent_streams: 128,
            h2_send_buffer_kb: 256,
            pipe_buffer_kb: 256,
            udp_socket_buffer_kb: 256,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Inbound {
    pub protocol: Protocol,
    pub listen: String,
    pub port: u16,
    pub settings: InboundSettings,
    #[serde(rename = "streamSettings")]
    pub stream_settings: StreamSettings,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Protocol {
    Vless,
    Vmess,
    Trojan,
    Shadowsocks,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InboundSettings {
    pub clients: Vec<Client>,
    #[serde(default = "default_decryption")]
    pub decryption: String,
    #[serde(default)]
    pub sniffing: SniffingConfig,
}

fn default_true() -> bool {
    true
}

/// 流量嗅探配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SniffingConfig {
    /// 是否启用嗅探
    #[serde(default)]
    pub enabled: bool,
    /// 嗅探目标类型
    #[serde(rename = "destOverride", default = "default_dest_override")]
    pub dest_override: Vec<String>,
}

impl Default for SniffingConfig {
    fn default() -> Self {
        Self {
            enabled: false, // 默认关闭
            dest_override: vec!["tls".to_string(), "http".to_string()],
        }
    }
}

fn default_dest_override() -> Vec<String> {
    vec!["tls".to_string(), "http".to_string()]
}

fn default_decryption() -> String {
    "none".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Client {
    pub id: String, // UUID
    #[serde(default)]
    pub flow: String,
    #[serde(default)]
    pub email: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamSettings {
    pub network: Network,
    pub security: Security,
    #[serde(rename = "realitySettings", skip_serializing_if = "Option::is_none")]
    pub reality_settings: Option<RealitySettings>,
    #[serde(rename = "xhttpSettings", skip_serializing_if = "Option::is_none")]
    pub xhttp_settings: Option<XhttpSettings>,
    #[serde(default)]
    pub sockopt: SockOpt,
}

/// Socket 选项配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SockOpt {
    /// TCP Fast Open - 减少握手延迟
    #[serde(rename = "tcpFastOpen", default = "default_true")]
    pub tcp_fast_open: bool,
    /// TCP No Delay (禁用 Nagle 算法) - 减少小包延迟
    #[serde(rename = "tcpNoDelay", default = "default_true")]
    pub tcp_no_delay: bool,
    /// 接受 Proxy Protocol (用于获取真实客户端 IP)
    #[serde(rename = "acceptProxyProtocol", default)]
    pub accept_proxy_protocol: bool,
}

impl Default for SockOpt {
    fn default() -> Self {
        Self {
            tcp_fast_open: true,          // 默认开启
            tcp_no_delay: true,           // 默认开启
            accept_proxy_protocol: false, // 默认关闭
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Network {
    Tcp,
    Http,
    Ws,
    Grpc,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Security {
    None,
    Tls,
    Reality,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RealitySettings {
    pub dest: String,
    #[serde(rename = "serverNames")]
    pub server_names: Vec<String>,
    #[serde(rename = "privateKey")]
    pub private_key: String,
    #[serde(rename = "publicKey", skip_serializing_if = "Option::is_none")]
    pub public_key: Option<String>,
    #[serde(rename = "shortIds")]
    pub short_ids: Vec<String>,
    #[serde(default = "default_fingerprint")]
    pub fingerprint: String,
}

fn default_fingerprint() -> String {
    "chrome".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct XhttpSettings {
    #[serde(default = "default_xhttp_mode")]
    pub mode: XhttpMode,
    #[serde(default = "default_path")]
    pub path: String,
    #[serde(default = "default_host")]
    pub host: String,
}

fn default_xhttp_mode() -> XhttpMode {
    XhttpMode::Auto // 默认自动选择
}

fn default_path() -> String {
    "/".to_string()
}

fn default_host() -> String {
    "".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum XhttpMode {
    /// 自动选择模式
    Auto,
    StreamUp,
    StreamDown,
    StreamOne,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Outbound {
    pub protocol: String,
    pub tag: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub settings: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RoutingConfig {
    #[serde(default)]
    pub rules: Vec<RoutingRule>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingRule {
    #[serde(rename = "type")]
    pub rule_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub domain: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ip: Option<Vec<String>>,
    #[serde(rename = "outboundTag")]
    pub outbound_tag: String,
}

impl Config {
    /// 从文件加载配置
    pub fn load<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = fs::read_to_string(path)?;
        let config: Config = serde_json::from_str(&content)?;

        // 验证配置
        Validator::validate(&config)?;

        Ok(config)
    }

    /// 保存配置到文件
    pub fn save<P: AsRef<Path>>(&self, path: P) -> Result<()> {
        let content = serde_json::to_string_pretty(self)?;
        fs::write(path, content)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_deserialization() {
        let json = r#"
        {
            "inbounds": [{
                "protocol": "vless",
                "listen": "0.0.0.0",
                "port": 443,
                "settings": {
                    "clients": [{
                        "id": "b831381d-6324-4d53-ad4f-8cda48b30811",
                        "flow": ""
                    }],
                    "decryption": "none"
                },
                "streamSettings": {
                    "network": "tcp",
                    "security": "reality",
                    "realitySettings": {
                        "dest": "www.apple.com:443",
                        "serverNames": ["www.apple.com"],
                        "privateKey": "test_key",
                        "shortIds": ["0123456789abcdef"]
                    }
                }
            }],
            "outbounds": [{
                "protocol": "freedom",
                "tag": "direct"
            }]
        }
        "#;

        let config: Config = serde_json::from_str(json).unwrap();
        assert_eq!(config.inbounds.len(), 1);
        assert_eq!(config.outbounds.len(), 1);
        // 不写 performance 时使用默认值
        assert_eq!(config.performance.h2_send_buffer_kb, 256);
    }

    #[test]
    fn test_performance_partial_override() {
        let p: PerformanceConfig =
            serde_json::from_str(r#"{"workerThreads": 1, "h2SendBufferKb": 64}"#).unwrap();
        assert_eq!(p.worker_threads, 1);
        assert_eq!(p.h2_send_buffer_kb, 64);
        // 没写的字段保持默认
        assert_eq!(p.max_connections, PerformanceConfig::default().max_connections);
    }

    #[test]
    fn test_performance_validation() {
        let mut p = PerformanceConfig::default();
        assert!(Validator::validate_performance(&p).is_ok());
        p.h2_send_buffer_kb = 8;
        assert!(Validator::validate_performance(&p).is_err());
    }
}
