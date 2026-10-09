use anyhow::Result;
use clap::Parser;
use tracing::{info, Level};
use tracing_subscriber;

mod config;
mod network;
mod protocol;
mod server;
mod transport;
mod utils;
mod handler;

use crate::config::Config;
use crate::server::Server;

#[cfg(not(target_os = "windows"))]
#[global_allocator]
static GLOBAL: tikv_jemallocator::Jemalloc = tikv_jemallocator::Jemalloc;

#[derive(Parser, Debug)]
#[command(author, version = env!("CARGO_PKG_VERSION"), about, long_about = None)]
struct Args {
    /// 配置文件路径
    #[arg(short, long, default_value = "config.json")]
    config: String,

    /// 日志级别
    #[arg(short, long, default_value = "info")]
    log_level: String,
}

// jemalloc 默认每核 4 个 arena，核数多的小内存容器里碎片会很可观；
// 同时让空闲页尽快还给系统，避免在 cgroup 内存上限下 RSS 居高不下。
#[cfg(not(target_os = "windows"))]
#[export_name = "_rjem_malloc_conf"]
pub static MALLOC_CONF: Option<&'static libc::c_char> = Some(unsafe {
    &*(b"narenas:4,dirty_decay_ms:1000,muzzy_decay_ms:0\0".as_ptr() as *const libc::c_char)
});

fn main() -> Result<()> {
    // 提高文件句柄限制 (Linux)
    #[cfg(not(target_os = "windows"))]
    {
        let mut limit = libc::rlimit {
            rlim_cur: 65535,
            rlim_max: 65535,
        };
        unsafe {
            if libc::setrlimit(libc::RLIMIT_NOFILE, &limit) != 0 {
                limit.rlim_cur = 4096;
                limit.rlim_max = 4096;
                libc::setrlimit(libc::RLIMIT_NOFILE, &limit);
            }
        }
    }

    let args = Args::parse();

    // 初始化日志
    let log_level_str = std::env::var("RUST_LOG")
        .unwrap_or_else(|_| args.log_level.clone());
    
    let log_level = match log_level_str.to_lowercase().as_str() {
        "trace" => Level::TRACE,
        "debug" => Level::DEBUG,
        "info" => Level::INFO,
        "warn" => Level::WARN,
        "error" => Level::ERROR,
        _ => Level::INFO,
    };

    tracing_subscriber::fmt()
        .with_max_level(log_level)
        .with_target(false)
        .with_thread_ids(true)
        .init();

    info!("🚀 Xray-Lite Server v{} [Manual Relay]", env!("CARGO_PKG_VERSION"));
    info!("📄 Loading config from: {}", args.config);

    // 1. Load config
    let config = Config::load(&args.config)?;
    info!("✅ Configuration loaded successfully");

    // 线程数要在建运行时之前就知道，所以配置在这里加载而不是在 async 里
    let mut runtime = tokio::runtime::Builder::new_multi_thread();
    runtime.enable_all();
    if config.performance.worker_threads > 0 {
        runtime.worker_threads(config.performance.worker_threads);
    }
    info!("⚙️ 性能参数: {:?}", config.performance);

    runtime.build()?.block_on(async move {
        // 2. Initialize and run server
        let server = Server::new(config)?;
        info!("🌐 Server initialized");

        // 运行服务器
        server.run().await
    })
}
