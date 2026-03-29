use anyhow::{anyhow, Result};
use std::sync::Arc;
use tokio::net::UdpSocket;
use webrtc_dtls::cipher_suite::CipherSuiteId;
use webrtc_dtls::config::Config;
use webrtc_dtls::conn::DTLSConn;

pub struct HueStreamer {
    conn: Arc<DTLSConn>,
}

impl HueStreamer {
    /// Connects to the Hue Bridge via DTLS for entertainment streaming.
    pub async fn connect(ip: &str, application_id: &str, client_key: &str) -> Result<Self> {
        let psk = hex::decode(client_key)
            .map_err(|e| anyhow!("Failed to decode client_key from hex: {}", e))?;
        let psk_identity = application_id.as_bytes().to_vec();

        let config = Config {
            cipher_suites: vec![CipherSuiteId::Tls_Psk_With_Aes_128_Gcm_Sha256],
            psk: Some(Arc::new(move |_hint: &[u8]| Ok(psk.clone()))),
            psk_identity_hint: Some(psk_identity),
            ..Default::default()
        };

        let socket = UdpSocket::bind("0.0.0.0:0").await?;
        socket.connect(format!("{ip}:2100")).await?;

        let conn = Arc::new(socket);
        let dtls_conn = DTLSConn::new(conn, config, true, None).await?;

        Ok(Self {
            conn: Arc::new(dtls_conn),
        })
    }

    pub async fn write_all(&mut self, buf: &[u8]) -> Result<()> {
        self.conn
            .write(buf, None)
            .await
            .map_err(|e| anyhow!("DTLS write error: {}", e))?;
        Ok(())
    }
}
