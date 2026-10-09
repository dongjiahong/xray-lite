use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use bytes::Bytes;
use hyper::http::Request;
use tokio::io::AsyncWriteExt;
use xray_lite::config::PerformanceConfig;
use xray_lite::server::AsyncStream;
use xray_lite::transport::xhttp::{H2Handler, XhttpConfig, XhttpMode};

const TOTAL: usize = 32 * 1024 * 1024;

/// 客户端不读响应时，服务端下行不能无限缓冲；客户端开始读之后数据必须全部到达。
#[tokio::test]
async fn download_is_backpressured_by_slow_client() {
    let perf = PerformanceConfig::default();
    let cfg = XhttpConfig {
        mode: XhttpMode::Auto,
        path: "/".to_string(),
        host: String::new(),
        performance: perf.clone(),
    };

    let written = Arc::new(AtomicUsize::new(0));
    let written_in_handler = written.clone();
    let handler = move |mut stream: Box<dyn AsyncStream>| {
        let written = written_in_handler.clone();
        async move {
            let block = vec![0xABu8; 16 * 1024];
            let mut sent = 0;
            while sent < TOTAL {
                stream.write_all(&block).await?;
                sent += block.len();
                written.store(sent, Ordering::SeqCst);
            }
            stream.shutdown().await?;
            Ok(())
        }
    };

    let (client_io, server_io) = tokio::io::duplex(64 * 1024);
    let h2_handler = H2Handler::new(cfg);
    tokio::spawn(async move {
        let _ = h2_handler.handle(server_io, handler).await;
    });

    let (mut send_request, connection) = h2::client::handshake(client_io).await.unwrap();
    tokio::spawn(async move {
        let _ = connection.await;
    });

    let request = Request::builder()
        .method("POST")
        .uri("https://example.com/")
        .header("content-type", "application/octet-stream")
        .body(())
        .unwrap();
    let (response, _send_body) = send_request.send_request(request, false).unwrap();
    let response = response.await.unwrap();
    let mut body = response.into_body();

    // 客户端故意不读，等服务端能塞多少塞多少
    tokio::time::sleep(Duration::from_secs(2)).await;
    let stalled_at = written.load(Ordering::SeqCst);
    // 理论占用: h2 发送缓冲 + 内部管道 + 客户端接收窗口(64KiB)，再留 1MiB 余量
    let upper_bound = (perf.h2_send_buffer_kb + perf.pipe_buffer_kb + 64) * 1024 + 1024 * 1024;
    assert!(
        stalled_at < upper_bound,
        "客户端不读取时服务端仍写入了 {} 字节(上限 {})，说明下行没有反压",
        stalled_at,
        upper_bound
    );

    let mut received = 0usize;
    while let Some(chunk) = body.data().await {
        let chunk: Bytes = chunk.unwrap();
        received += chunk.len();
        let _ = body.flow_control().release_capacity(chunk.len());
    }
    assert_eq!(received, TOTAL);
}
